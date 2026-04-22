defmodule SonarWeb.TrustController do
  use SonarWeb, :controller

  alias Sonar.Peers

  def update(conn, %{"peer_id" => peer_id, "trust_level" => level})
      when level in ~w(basic trusted intimate) do
    case Peers.get(peer_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "peer_not_found"})

      peer ->
        case Peers.set_trust(peer, level) do
          {:ok, updated} ->
            json(conn, %{peer_id: updated.id, trust_level: updated.trust_level})

          {:error, changeset} ->
            conn |> put_status(422) |> json(%{error: format_errors(changeset)})
        end
    end
  end

  def update(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{
      error: "missing or invalid fields: peer_id, trust_level in [basic, trusted, intimate]"
    })
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
