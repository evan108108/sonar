defmodule SonarWeb.ServerCardController do
  use SonarWeb, :controller

  def show(conn, _params) do
    identity = Sonar.Identity.get()

    card = %{
      version: "1.0",
      agent: %{
        name: identity.name,
        instance_id: identity.instance_id,
        version: Application.spec(:sonar, :vsn) |> to_string(),
        description: "Sonar peer-to-peer agent relay"
      },
      capabilities: identity.capabilities,
      transport: %{
        type: "http",
        endpoint: SonarWeb.Endpoint.url()
      },
      authentication: %{
        type: "bearer",
        pairing_required: true
      }
    }

    conn
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> json(card)
  end
end
