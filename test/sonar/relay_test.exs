defmodule Sonar.RelayTest do
  use ExUnit.Case

  alias Sonar.{Messages, Peers}

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Sonar.Repo, shared: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  describe "message relay logic" do
    test "send_message stores outbound message" do
      {:ok, peer} =
        Peers.create(%{
          "name" => "scout",
          "hostname" => "scout.local"
        })

      {:ok, msg} =
        Messages.send_message(%{
          "peer_id" => peer.id,
          "question" => "What is your architecture?"
        })

      # Test env sets skip_http_relay: true, which counts as a successful
      # relay — send_message persists the outcome instead of leaving "pending".
      assert msg.direction == "outbound"
      assert msg.status == "relayed"
      assert msg.failure_reason == nil
      assert msg.question == "What is your architecture?"
    end

    test "receive_message stores inbound message" do
      {:ok, peer} =
        Peers.create(%{
          "name" => "scout",
          "hostname" => "scout.local"
        })

      id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

      {:ok, msg} =
        Messages.receive_message(%{
          "id" => id,
          "peer_id" => peer.id,
          "question" => "What do you know about infrastructure?"
        })

      assert msg.direction == "inbound"
      assert msg.status == "pending"
      assert msg.peer_id == peer.id
    end

    test "reply updates message and sets answered_at" do
      {:ok, peer} =
        Peers.create(%{
          "name" => "scout",
          "hostname" => "scout.local"
        })

      id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

      {:ok, msg} =
        Messages.receive_message(%{
          "id" => id,
          "peer_id" => peer.id,
          "question" => "What is 2+2?"
        })

      {:ok, replied} = Messages.reply(msg, "4")

      assert replied.answer == "4"
      assert replied.status == "answered"
      assert replied.answered_at != nil
    end

    test "Relay is NOT started in test env (discovery_enabled: false override)" do
      # Discovery defaults to on in prod, but test env sets
      # `config :sonar, :discovery_enabled, false` so the Discovery/Relay
      # supervisor tree stays out of Ecto SQL Sandbox's :manual ownership.
      # Prod-shaped assertion "started by default" is exercised by the
      # deploy sanity checks, not this suite.
      assert Process.whereis(Sonar.Relay) == nil
    end

    test "message handler stores inbound from known peer" do
      {:ok, peer} =
        Peers.create(%{
          "name" => "scout",
          "hostname" => "scout.local",
          "instance_id" => "scout-123",
          "connection_status" => "paired"
        })

      # Simulate what MessageHandler does
      msg_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

      {:ok, msg} =
        Messages.receive_message(%{
          "id" => msg_id,
          "peer_id" => peer.id,
          "question" => "Relay test question"
        })

      assert msg.question == "Relay test question"
      assert msg.peer_id == peer.id
    end

    test "response frame updates the local audit's answer without re-relaying" do
      # Regression for: maybe_relay_response was casting `{:sonar_message,
      # ...}` with a `%{"response_to", "answer"}` shape. The remote handler
      # then tried to store it as a new inbound message, which failed schema
      # validation (missing question) and silently dropped the reply.
      # Since the cross-node cast can't be exercised in a single-node test,
      # we drive the state transition the way :sonar_response would: hand
      # the local audit row to `update_answer` and assert (a) the row is
      # updated in place, (b) NO new message row is inserted, (c) status
      # transitions to "answered".
      {:ok, peer} =
        Peers.create(%{
          "name" => "scout",
          "hostname" => "scout.local",
          "instance_id" => "scout-123",
          "connection_status" => "discovered"
        })

      # An outbound message we sent to scout earlier
      {:ok, sent} =
        Messages.send_message(%{
          "peer_id" => peer.id,
          "question" => "What is your architecture?"
        })

      before_count = Sonar.Repo.aggregate(Sonar.Schema.Message, :count, :id)

      {:ok, updated} = Messages.update_answer(sent.id, "42")

      after_count = Sonar.Repo.aggregate(Sonar.Schema.Message, :count, :id)

      assert updated.id == sent.id
      assert updated.answer == "42"
      assert updated.status == "answered"
      assert after_count == before_count, "update_answer must NOT insert a new row"
    end

    test "Sonar.Relay.send_response returns :not_connected when peer isn't connected" do
      # Verifies the new send_response public API exists and returns the
      # expected error tuple for unknown peer_ids. Actual cross-node send
      # would require booting a second BEAM.
      #
      # Discovery is off in test env (see config/test.exs), so Sonar.Relay
      # isn't running under the app supervisor. Start a bare instance just
      # for this call.
      {:ok, _pid} = Sonar.Relay.start_link([])
      on_exit(fn ->
        pid = Process.whereis(Sonar.Relay)
        if pid, do: GenServer.stop(pid)
      end)

      assert {:error, :not_connected} =
               Sonar.Relay.send_response("not-a-real-peer", "msg-id", "answer")
    end
  end

  describe "peer trust" do
    test "at_least_trust? checks trust hierarchy" do
      {:ok, peer} =
        Peers.create(%{
          "name" => "scout",
          "hostname" => "scout.local",
          "trust_level" => "trusted"
        })

      assert Peers.at_least_trust?(peer, "basic")
      assert Peers.at_least_trust?(peer, "trusted")
      refute Peers.at_least_trust?(peer, "intimate")
    end

    test "set_trust updates trust level" do
      {:ok, peer} =
        Peers.create(%{
          "name" => "scout",
          "hostname" => "scout.local",
          "trust_level" => "basic"
        })

      {:ok, updated} = Peers.set_trust(peer, "trusted")
      assert updated.trust_level == "trusted"
    end
  end
end
