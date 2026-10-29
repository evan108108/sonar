defmodule Sonar.Peers do
  @moduledoc """
  Context module for peer operations.
  """

  import Ecto.Query
  alias Sonar.Repo
  alias Sonar.Schema.Peer

  def list do
    Repo.all(from(p in Peer, order_by: [desc: p.inserted_at]))
  end

  def get(id) do
    Repo.get(Peer, id)
  end

  def find_by_instance_id(nil), do: nil

  def find_by_instance_id(instance_id) do
    Repo.one(from(p in Peer, where: p.instance_id == ^instance_id))
  end

  def find_by_hostname(hostname) do
    Repo.one(from(p in Peer, where: p.hostname == ^hostname, limit: 1))
  end

  def create(attrs) do
    id = gen_id()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs =
      attrs
      |> Map.put("id", id)
      |> Map.put_new("last_seen_at", now)

    %Peer{}
    |> Peer.changeset(attrs)
    |> Repo.insert()
  end

  def update(peer, attrs) do
    peer
    |> Peer.changeset(attrs)
    |> Repo.update()
  end

  @trust_order %{"basic" => 1, "trusted" => 2, "intimate" => 3}

  def delete(peer) do
    Repo.delete(peer)
  end

  @doc """
  Folds `drop` into `keep` in one transaction: `drop`'s tokens and messages
  move to `keep`, `keep` takes `drop`'s address (the one that answered) and
  the higher of the two trust levels, and `drop` is deleted. `keep` is the
  row that already holds the instance_id, so its name — the one callers
  address — survives.
  """
  def merge(%Peer{id: id} = keep, %Peer{id: id}), do: {:ok, keep}

  def merge(%Peer{} = keep, %Peer{} = drop) do
    Repo.transaction(fn ->
      from(t in Sonar.Schema.PeerToken, where: t.peer_id == ^drop.id)
      |> Repo.update_all(set: [peer_id: keep.id])

      from(m in Sonar.Schema.Message, where: m.peer_id == ^drop.id)
      |> Repo.update_all(set: [peer_id: keep.id])

      Repo.delete!(drop)

      keep
      |> Peer.changeset(%{
        "hostname" => drop.hostname,
        "port" => drop.port,
        "trust_level" => higher_trust(keep.trust_level, drop.trust_level),
        "connection_status" => drop.connection_status,
        "last_seen_at" => latest(keep.last_seen_at, drop.last_seen_at)
      })
      |> Repo.update!()
    end)
  end

  @doc """
  Follows a peer that reports a new port in an inbound request (`from_port`).
  Only ever called after the sender matched a known instance_id.
  """
  def follow_port(%Peer{} = peer, port) when is_integer(port) and port > 0 and port <= 65_535 do
    if port == peer.port, do: {:ok, peer}, else: __MODULE__.update(peer, %{"port" => port})
  end

  def follow_port(%Peer{} = peer, port) when is_binary(port) do
    case Integer.parse(port) do
      {n, ""} -> follow_port(peer, n)
      _ -> {:ok, peer}
    end
  end

  def follow_port(%Peer{} = peer, _), do: {:ok, peer}

  defp higher_trust(a, b) do
    if Map.get(@trust_order, a, 0) >= Map.get(@trust_order, b, 0), do: a, else: b
  end

  defp latest(nil, b), do: b
  defp latest(a, nil), do: a
  defp latest(a, b), do: if(DateTime.compare(a, b) == :lt, do: b, else: a)

  def at_least_trust?(%Peer{trust_level: level}, needed) do
    Map.get(@trust_order, level, 0) >= Map.get(@trust_order, needed, 0)
  end

  def set_trust(peer, level) when level in ~w(basic trusted intimate) do
    peer
    |> Peer.changeset(%{"trust_level" => level})
    |> Repo.update()
  end

  defp gen_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
end
