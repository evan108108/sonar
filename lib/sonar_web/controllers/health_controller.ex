defmodule SonarWeb.HealthController do
  use SonarWeb, :controller

  def index(conn, _params) do
    json(conn, %{
      status: "ok",
      app: "sonar",
      version: Application.spec(:sonar, :vsn) |> to_string(),
      uptime: System.monotonic_time(:second),
      node: Node.self() |> to_string()
    })
  end
end
