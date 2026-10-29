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

  # Advertise where remote peers should reach us. SONAR_PUBLIC_HOST (e.g. a
  # Tailscale hostname or public DNS name) wins when set — the host the
  # caller used may be LAN-only or a loopback name that doesn't route from
  # other networks. Falls back to conn.host, which at least matches however
  # the current caller got here. SonarWeb.Endpoint.url/0 (config host
  # "localhost") is useless to a remote peer, so we never use it.
  defp endpoint_url(conn) do
    host =
      case System.get_env("SONAR_PUBLIC_HOST") do
        nil -> conn.host
        "" -> conn.host
        public -> public
      end

    "http://#{host}:#{Sonar.PortFile.bound_port()}"
  end
end
