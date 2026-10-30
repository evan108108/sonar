defmodule SonarWeb.ServerCardController do
  use SonarWeb, :controller

  def show(conn, _params) do
    identity = Sonar.Identity.get()
    port = Sonar.PortFile.bound_port()

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
        endpoint: endpoint_url(port),
        port: port
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

  # Advertise where remote peers should reach us. SONAR_PUBLIC_HOST is the
  # one knob — set it to whatever hostname actually routes to this instance
  # for the peers that will see this card (a Tailscale name, a public DNS
  # name, a LAN hostname, etc.). When it's unset we have no honest answer,
  # so `endpoint` is null rather than a fabricated URL built from whatever
  # host the current caller happened to use (which may be loopback or
  # LAN-only and useless to the next peer who reads the card).
  defp endpoint_url(port) do
    case System.get_env("SONAR_PUBLIC_HOST") do
      nil -> nil
      "" -> nil
      public -> "http://#{public}:#{port}"
    end
  end
end
