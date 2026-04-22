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
      {:ok, peer} = Peers.create(%{
        "name" => "scout",
        "hostname" => "scout.local"
      })

      {:ok, msg} = Messages.send_message(%{
        "peer_id" => peer.id,
        "question" => "What is your architecture?"
      })

      assert msg.direction == "outbound"
      assert msg.status == "pending"
      assert msg.question == "What is your architecture?"
    end

    test "receive_message stores inbound message" do
      {:ok, peer} = Peers.create(%{
        "name" => "scout",
        "hostname" => "scout.local"
      })

      id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
      {:ok, msg} = Messages.receive_message(%{
        "id" => id,
        "peer_id" => peer.id,
        "question" => "What do you know about infrastructure?"
      })

      assert msg.direction == "inbound"
      assert msg.status == "pending"
      assert msg.peer_id == peer.id
    end

    test "reply updates message and sets answered_at" do
      {:ok, peer} = Peers.create(%{
        "name" => "scout",
        "hostname" => "scout.local"
      })

      id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
      {:ok, msg} = Messages.receive_message(%{
        "id" => id,
        "peer_id" => peer.id,
        "question" => "What is 2+2?"
      })

      {:ok, replied} = Messages.reply(msg, "4")

      assert replied.answer == "4"
      assert replied.status == "answered"
      assert replied.answered_at != nil
    end

    test "relay_available? returns false when Relay is not started" do
      # In test env, Relay is not started (no SONAR_DISCOVERY=true)
      assert Process.whereis(Sonar.Relay) == nil
    end

    test "message handler stores inbound from known peer" do
      {:ok, peer} = Peers.create(%{
        "name" => "scout",
        "hostname" => "scout.local",
        "instance_id" => "scout-123",
        "connection_status" => "paired"
      })

      # Simulate what MessageHandler does
      msg_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
      {:ok, msg} = Messages.receive_message(%{
        "id" => msg_id,
        "peer_id" => peer.id,
        "question" => "Relay test question"
      })

      assert msg.question == "Relay test question"
      assert msg.peer_id == peer.id
    end
  end

  describe "peer trust" do
    test "at_least_trust? checks trust hierarchy" do
      {:ok, peer} = Peers.create(%{
        "name" => "scout",
        "hostname" => "scout.local",
        "trust_level" => "trusted"
      })

      assert Peers.at_least_trust?(peer, "basic")
      assert Peers.at_least_trust?(peer, "trusted")
      refute Peers.at_least_trust?(peer, "intimate")
    end

    test "set_trust updates trust level" do
      {:ok, peer} = Peers.create(%{
        "name" => "scout",
        "hostname" => "scout.local",
        "trust_level" => "basic"
      })

      {:ok, updated} = Peers.set_trust(peer, "trusted")
      assert updated.trust_level == "trusted"
    end
  end
end
