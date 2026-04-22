defmodule Sonar.Peers do
  @moduledoc """
  Context module for peer operations.
  """

  import Ecto.Query
  alias Sonar.Repo
  alias Sonar.Schema.Peer

  def list do
    Repo.all(from p in Peer, order_by: [desc: p.inserted_at])
  end

  def get(id) do
    Repo.get(Peer, id)
  end

  def create(attrs) do
    id = gen_id()

    %Peer{}
    |> Peer.changeset(Map.put(attrs, "id", id))
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

  defp gen_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
end
