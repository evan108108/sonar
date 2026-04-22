defmodule Sonar.Fixtures do
  @moduledoc """
  Test fixtures for creating known data in tests.
  Each test gets a sandboxed transaction that rolls back — fixtures are isolated.
  """

  alias Sonar.Repo
  alias Sonar.Schema.{Peer, Message, PeerToken}

  def peer(attrs \\ %{}) do
    defaults = %{
      id: gen_id(),
      name: "test-peer",
      hostname: "test-peer.local",
      port: 8400,
      instance_id: gen_id(),
      discovery_method: "manual",
      connection_status: "discovered",
      trust_level: "basic",
      capabilities: "[]"
    }

    %Peer{}
    |> Peer.changeset(Map.merge(defaults, attrs) |> stringify_keys())
    |> Repo.insert!()
  end

  def message(attrs \\ %{}) do
    peer = attrs[:peer] || peer()

    defaults = %{
      id: gen_id(),
      peer_id: peer.id,
      direction: "inbound",
      question: "What is your purpose?",
      status: "pending"
    }

    %Message{}
    |> Message.changeset(Map.merge(defaults, Map.delete(attrs, :peer)) |> stringify_keys())
    |> Repo.insert!()
  end

  def outbound_message(attrs \\ %{}) do
    message(Map.merge(%{direction: "outbound"}, attrs))
  end

  def peer_token(attrs \\ %{}) do
    peer = attrs[:peer] || peer()
    raw_token = "sonar_" <> (gen_id() |> String.slice(0..31))
    token_hash = :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)

    defaults = %{
      id: gen_id(),
      peer_id: peer.id,
      token_hash: token_hash,
      scopes: "query"
    }

    token =
      %PeerToken{}
      |> PeerToken.changeset(Map.merge(defaults, Map.delete(attrs, :peer)) |> stringify_keys())
      |> Repo.insert!()

    {token, raw_token}
  end

  defp gen_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
