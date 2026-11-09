defmodule Sonar.EventsLocalOnlyTest do
  @moduledoc """
  The `messages:events` topic is the feed to THIS node's Sonata (its
  PluginManager joins it over the channel socket). It must never leave the
  node.

  Sonar.Relay joins paired peers into one Erlang cluster, and
  `Phoenix.PubSub.broadcast/3` (the PG2 adapter behind
  `SonarWeb.Endpoint.broadcast/3`) fans out to every node in that cluster.
  So when scout-cloud received a DM from evan-mac over the relay and
  announced `new_message` to its own Sonata, the same event reached
  evan-mac's Sonata too. That Sonata materialised its own outbound DM as an
  inbound `sonar_dm` workerEvent and handed it to a local worker
  (message 6f4406fe, 2026-11-09).

  The test stands up a second BEAM node, joins a sink process to the
  PubSub's pg groups there, and asserts that a relay-delivered DM reaches
  the local channel subscriber and NOT the remote node.
  """

  use ExUnit.Case, async: false

  alias Sonar.Peers

  @scope Phoenix.PubSub

  setup_all do
    started_dist? =
      if Node.alive?() do
        false
      else
        {:ok, _} = Node.start(:"sonar_events_test@127.0.0.1", :longnames)
        true
      end

    # Control the peer over stdio (no dependence on dist for :peer.call), then
    # join it to this node's cluster explicitly with the same cookie.
    {:ok, peer, remote} =
      :peer.start_link(%{
        name: :"sonar_events_remote_#{System.unique_integer([:positive])}",
        host: ~c"127.0.0.1",
        longnames: true,
        connection: :standard_io,
        args: [~c"-setcookie", Atom.to_charlist(Node.get_cookie())]
      })

    true = Node.connect(remote)

    {:ok, _} = :peer.call(peer, :pg, :start, [@scope])
    sink = :peer.call(peer, :erlang, :spawn, [:timer, :sleep, [:infinity]])

    groups = :pg.which_groups(@scope)
    assert groups != [], "expected Sonar.PubSub to have joined a pg group locally"
    for g <- groups, do: :ok = :peer.call(peer, :pg, :join, [@scope, g, sink])

    # pg membership syncs asynchronously; wait until this node sees the sink.
    wait_until(fn -> Enum.all?(groups, &(sink in :pg.get_members(@scope, &1))) end)

    on_exit(fn ->
      try do
        :peer.stop(peer)
      catch
        _, _ -> :ok
      end

      if started_dist?, do: Node.stop()
    end)

    %{peer: peer, sink: sink}
  end

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Sonar.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  test "a relay-delivered DM's new_message stays on this node", %{peer: peer, sink: sink} do
    {:ok, _peer_row} =
      Peers.create(%{
        "name" => "sona",
        "hostname" => "evan-mac.local",
        "instance_id" => "origin-instance"
      })

    # Discovery (and with it the relay handler) is off in test env.
    start_supervised!(Sonar.Relay.MessageHandler)

    :ok = Phoenix.PubSub.subscribe(Sonar.PubSub, "messages:events")

    GenServer.cast(
      Sonar.Relay.MessageHandler,
      {:sonar_message, "origin-instance",
       %{"message_id" => "msg-echo-1", "question" => "hello", "from_session_id" => "worker-1"}}
    )

    # The local Sonata (channel subscriber) still gets it.
    assert_receive %Phoenix.Socket.Broadcast{
                     event: "new_message",
                     payload: %{message_id: "msg-echo-1"}
                   },
                   1_000

    # Nothing crossed to the other node.
    Process.sleep(200)
    {:messages, remote_msgs} = :peer.call(peer, :erlang, :process_info, [sink, :messages])

    leaked =
      Enum.filter(remote_msgs, fn
        {:forward_to_local, "messages:events", _, _} -> true
        _ -> false
      end)

    assert leaked == [],
           "messages:events leaked to remote node: #{inspect(leaked, limit: 3)}"
  end

  test "every messages:events emit is node-local", %{peer: peer, sink: sink} do
    :ok = Phoenix.PubSub.subscribe(Sonar.PubSub, "messages:events")

    for event <- ~w(new_message reply_received reply_sent ack_forward) do
      SonarWeb.Events.emit(event, %{message_id: "m-#{event}"})
      assert_receive %Phoenix.Socket.Broadcast{event: ^event}, 1_000
    end

    Process.sleep(200)
    {:messages, remote_msgs} = :peer.call(peer, :erlang, :process_info, [sink, :messages])
    assert remote_msgs == []
  end

  defp wait_until(fun, tries \\ 50) do
    cond do
      fun.() ->
        :ok

      tries == 0 ->
        flunk("condition never became true")

      true ->
        Process.sleep(20)
        wait_until(fun, tries - 1)
    end
  end
end
