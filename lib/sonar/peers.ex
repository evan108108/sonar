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

  def delete(peer) do
    Repo.delete(peer)
  end

  @trust_order %{"basic" => 1, "trusted" => 2, "intimate" => 3}

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
