defmodule SonarWeb.SessionsController do
  use SonarWeb, :controller

  @doc """
  Local-or-remote session listing. With `peer_id`, queries the paired peer's
  Sonar (paired-trust only — see plan §11.2). Without it, queries the local
  Sonata DM registry over loopback.
  """
  def index(conn, params) do
    case params["peer_id"] do
      empty when empty in [nil, ""] ->
        local(conn, params)

      peer_id ->
        case Sonar.Sessions.list_remote(peer_id) do
          {:ok, payload} ->
            json(conn, payload)

          {:error, :peer_not_found} ->
            conn |> put_status(404) |> json(%{error: "peer_not_found"})

          {:error, :peer_not_paired} ->
            conn |> put_status(403) |> json(%{error: "peer_not_paired"})

          {:error, :sonata_unreachable} ->
            conn |> put_status(502) |> json(%{error: "sonata_unreachable"})

          {:error, other} ->
            conn |> put_status(502) |> json(%{error: inspect(other)})
        end
    end
  end

  @doc """
  Locally-registered sessions only. This is what remote peers query through
  Phoenix when discovering DM targets. Never recursively forwards.
  """
  def local(conn, _params) do
    {:ok, payload} = Sonar.Sessions.list_local()
    json(conn, payload)
  end
end
