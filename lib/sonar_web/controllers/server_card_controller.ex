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
        endpoint: endpoint_url(conn),
        port: Sonar.PortFile.bound_port()
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

  # Advertise the host the caller actually reached us on plus the bound
  # port. SonarWeb.Endpoint.url/0 is built from config (host "localhost"),
  # which is useless to a remote peer.
  defp endpoint_url(conn) do
    "http://#{conn.host}:#{Sonar.PortFile.bound_port()}"
  end
end
