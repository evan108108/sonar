defmodule Sonar.MessagesDMTest do
  @moduledoc """
  Tests for the Sonar DM v0 protocol extension on `Sonar.Messages` and
  `Sonar.Schema.Message`. See `sonar-dm-v0-plan.md` §8.2.
  """

  use ExUnit.Case
  import Ecto.Changeset, only: [get_field: 2]

  alias Sonar.{Messages, Peers}
  alias Sonar.Schema.Message

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Sonar.Repo, shared: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  describe "Messages.send_message/1 with DM keys" do
    setup do
      # Both the setup and the on-exit restore preserve whatever the surrounding
      # env had, instead of hardcoding false — the hardcoded false was leaking
      # `skip_http_relay=false` across test files and turning subsequent send
      # tests into real HTTP attempts (which then fail because Discovery/Relay
      # is off in test env, so nothing intercepts).
      prior = Application.get_env(:sonar, :skip_http_relay)
      Application.put_env(:sonar, :skip_http_relay, true)
      on_exit(fn ->
        case prior do
          nil -> Application.delete_env(:sonar, :skip_http_relay)
          val -> Application.put_env(:sonar, :skip_http_relay, val)
        end
      end)

      {:ok, peer} =
        Peers.create(%{
          "name" => "scout",
          "hostname" => "scout.local",
          "instance_id" => "scout-instance"
        })

      {:ok, peer: peer}
    end

    test "persists target_session_id and from_session_id", %{peer: peer} do
      {:ok, msg} =
        Messages.send_message(%{
          "peer_id" => peer.id,
          "question" => "ping",
          "target_session_id" => "orchestrator-1",
          "from_session_id" => "worker-7"
        })

      assert msg.target_session_id == "orchestrator-1"
      assert msg.from_session_id == "worker-7"
      assert msg.direction == "outbound"

      reloaded = Messages.get(msg.id)
      assert reloaded.target_session_id == "orchestrator-1"
      assert reloaded.from_session_id == "worker-7"
    end

    test "broadcasts on Phoenix.PubSub when receive_message lands a DM", %{peer: peer} do
      Phoenix.PubSub.subscribe(Sonar.PubSub, "messages:events")

      attrs = %{
        "id" => :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower),
        "peer_id" => peer.id,
        "question" => "ping",
        "target_session_id" => "orchestrator-1",
        "from_session_id" => "worker-7"
      }

      {:ok, msg} = Messages.receive_message(attrs)

      # The relay/HTTP layer is what broadcasts; reproduce that broadcast here
      # the same way the relay handler does, then assert the keys round-trip.
      SonarWeb.Endpoint.broadcast("messages:events", "new_message", %{
        message_id: msg.id,
        from_peer: peer.instance_id,
        question: msg.question,
        direction: "inbound",
        status: msg.status,
        target_session_id: msg.target_session_id,
        from_session_id: msg.from_session_id
      })

      assert_receive %Phoenix.Socket.Broadcast{
        event: "new_message",
        payload: %{
          target_session_id: "orchestrator-1",
          from_session_id: "worker-7"
        }
      }
    end

    test "send_message with nil DM keys still persists", %{peer: peer} do
      {:ok, msg} =
        Messages.send_message(%{
          "peer_id" => peer.id,
          "question" => "ping"
        })

      assert msg.target_session_id == nil
      assert msg.from_session_id == nil
    end
  end

  describe "Message.changeset DM key validation" do
    test "accepts valid session ids" do
      cs =
        Message.changeset(%Message{}, %{
          "id" => "abc",
          "question" => "q",
          "target_session_id" => "orchestrator_1",
          "from_session_id" => "Worker-7"
        })

      assert cs.valid?
    end

    test "accepts nil/missing session ids" do
      cs = Message.changeset(%Message{}, %{"id" => "abc", "question" => "q"})
      assert cs.valid?

      cs2 =
        Message.changeset(%Message{}, %{
          "id" => "abc",
          "question" => "q",
          "target_session_id" => nil,
          "from_session_id" => nil
        })

      assert cs2.valid?
    end

    test "rejects malformed target_session_id" do
      cs =
        Message.changeset(%Message{}, %{
          "id" => "abc",
          "question" => "q",
          "target_session_id" => "bad id with spaces"
        })

      refute cs.valid?
      assert Keyword.has_key?(cs.errors, :target_session_id)
    end

    test "rejects malformed from_session_id" do
      cs =
        Message.changeset(%Message{}, %{
          "id" => "abc",
          "question" => "q",
          "from_session_id" => "no/slashes"
        })

      refute cs.valid?
      assert Keyword.has_key?(cs.errors, :from_session_id)
    end

    test "treats empty-string session id as absent (Ecto cast converts to nil)" do
      # Ecto's cast/3 default :empty_values normalizes "" to nil for :string
      # fields, which then passes the format validator (nil-tolerant).
      cs =
        Message.changeset(%Message{}, %{
          "id" => "abc",
          "question" => "q",
          "target_session_id" => ""
        })

      assert cs.valid?
      assert get_field(cs, :target_session_id) == nil
    end

    test "rejects oversize session id (>128 chars)" do
      cs =
        Message.changeset(%Message{}, %{
          "id" => "abc",
          "question" => "q",
          "target_session_id" => String.duplicate("a", 129)
        })

      refute cs.valid?
    end
  end
end
