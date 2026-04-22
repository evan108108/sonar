defmodule SonarWeb.TokensController do
  use SonarWeb, :controller

  import Ecto.Query

  alias Sonar.{Audit, Repo}
  alias Sonar.Schema.{Peer, PeerToken}

  def create(conn, %{"peer_id" => peer_id} = params) do
    case Repo.get(Peer, peer_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Peer not found"})

      peer ->
        raw_token = "sonar_" <> (:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower))
        hash = :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)

        attrs = %{
          "id" => gen_id(),
          "peer_id" => peer.id,
          "token_hash" => hash,
          "scopes" => Map.get(params, "scopes", "query"),
          "expires_at" => parse_expires_at(params["expires_at"])
        }

        case %PeerToken{} |> PeerToken.changeset(attrs) |> Repo.insert() do
          {:ok, token} ->
            Audit.log(%{
              action: "token.issued",
              peer_id: peer.id,
              peer_name: peer.name,
              response_status: 201
            })

            conn
            |> put_status(201)
            |> json(%{
              id: token.id,
              peer_id: token.peer_id,
              scopes: token.scopes,
              expires_at: token.expires_at,
              inserted_at: token.inserted_at,
              token: raw_token
            })

          {:error, changeset} ->
            conn |> put_status(422) |> json(%{error: format_errors(changeset)})
        end
    end
  end

  def index(conn, %{"peer_id" => peer_id}) do
    case Repo.get(Peer, peer_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Peer not found"})

      _peer ->
        tokens =
          Repo.all(
            from(t in PeerToken,
              where: t.peer_id == ^peer_id,
              order_by: [desc: t.inserted_at]
            )
          )

        json(conn, Enum.map(tokens, &token_to_json/1))
    end
  end

  def revoke(conn, %{"peer_id" => peer_id, "token_id" => token_id}) do
    case Repo.get_by(PeerToken, id: token_id, peer_id: peer_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Token not found"})

      token ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        {:ok, token} =
          token
          |> Ecto.Changeset.change(revoked_at: now)
          |> Repo.update()

        Audit.log(%{
          action: "token.revoked",
          peer_id: token.peer_id,
          response_status: 200
        })

        json(conn, token_to_json(token))
    end
  end

  defp token_to_json(token) do
    %{
      id: token.id,
      peer_id: token.peer_id,
      scopes: token.scopes,
      expires_at: token.expires_at,
      last_used_at: token.last_used_at,
      revoked_at: token.revoked_at,
      inserted_at: token.inserted_at
    }
  end

  defp parse_expires_at(nil), do: nil
  defp parse_expires_at(""), do: nil

  defp parse_expires_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp parse_expires_at(%DateTime{} = dt), do: DateTime.truncate(dt, :second)
  defp parse_expires_at(_), do: nil

  defp gen_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
