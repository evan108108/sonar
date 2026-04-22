defmodule SonarWeb.Plugs.BearerAuth do
  @moduledoc """
  Authenticates peer-facing requests via `Authorization: Bearer <token>`.

  The raw token is SHA-256 hashed and looked up against `peer_tokens.token_hash`.
  Tokens must not be revoked and, if they carry an `expires_at`, must not be expired.
  On success, assigns `current_peer` and `current_token` and bumps `last_used_at`.
  """

  import Plug.Conn

  alias Sonar.Repo
  alias Sonar.Schema.{Peer, PeerToken}

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with {:ok, raw_token} <- extract_token(conn),
         {:ok, token} <- lookup_token(raw_token),
         :ok <- check_expiration(token),
         {:ok, peer} <- load_peer(token) do
      token = touch_token(token)

      conn
      |> assign(:current_peer, peer)
      |> assign(:current_token, token)
    else
      _ -> unauthorized(conn)
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> raw] when byte_size(raw) > 0 -> {:ok, raw}
      _ -> :error
    end
  end

  defp lookup_token(raw_token) do
    hash = :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)

    case Repo.get_by(PeerToken, token_hash: hash) do
      nil -> :error
      %PeerToken{revoked_at: nil} = token -> {:ok, token}
      _ -> :error
    end
  end

  defp check_expiration(%PeerToken{expires_at: nil}), do: :ok

  defp check_expiration(%PeerToken{expires_at: %DateTime{} = exp}) do
    if DateTime.compare(exp, DateTime.utc_now()) == :gt, do: :ok, else: :error
  end

  defp load_peer(%PeerToken{peer_id: peer_id}) do
    case Repo.get(Peer, peer_id) do
      nil -> :error
      peer -> {:ok, peer}
    end
  end

  defp touch_token(token) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, updated} =
      token
      |> Ecto.Changeset.change(last_used_at: now)
      |> Repo.update()

    updated
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", ~s(Bearer realm="sonar"))
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
    |> halt()
  end
end
