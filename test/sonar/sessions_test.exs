defmodule Sonar.SessionsTest do
  @moduledoc """
  Tests for the `Sonar.Sessions` context (session discovery for DMs).

  Sonata is not running during the test suite, so `list_local/0` exercises
  the transport-failure path — it must return an empty list and queried_at
  rather than raising.
  """

  use ExUnit.Case

  alias Sonar.{Peers, Sessions}

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Sonar.Repo, shared: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  describe "list_local/0" do
    test "returns the documented shape on success or transport failure" do
      {:ok, payload} = Sessions.list_local()

      assert is_map(payload)
      assert is_list(payload.sessions)
      assert is_integer(payload.queried_at)
    end

    test "returns an empty list when Sonata loopback is unreachable" do
      # Sonata is not running in the test suite — this is the common case.
      {:ok, payload} = Sessions.list_local()
      assert payload.sessions == []
    end
  end

  describe "list_remote/1" do
    test "returns peer_not_paired when peer is in 'discovered' status" do
      {:ok, peer} =
        Peers.create(%{
          "name" => "scout",
          "hostname" => "scout.local",
          "connection_status" => "discovered"
        })

      assert {:error, :peer_not_paired} = Sessions.list_remote(peer.id)
    end

    test "returns peer_not_found for unknown peer id" do
      assert {:error, :peer_not_found} = Sessions.list_remote("does-not-exist")
    end

    test "returns sonata_unreachable when paired peer host is unreachable" do
      {:ok, peer} =
        Peers.create(%{
          "name" => "scout",
          "hostname" => "127.0.0.1",
          "port" => 1,
          "connection_status" => "paired"
        })

      assert {:error, :sonata_unreachable} = Sessions.list_remote(peer.id)
    end
  end
end
