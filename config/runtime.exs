import Config

# Always start the server in releases
if System.get_env("PHX_SERVER") || config_env() == :prod do
  config :sonar, SonarWeb.Endpoint, server: true
end

# Bind to 0.0.0.0 by default in prod — see the prod block below.
bind_ip =
  if config_env() == :prod and System.get_env("SONAR_BIND_LOCAL") != "true",
    do: {0, 0, 0, 0},
    else: {127, 0, 0, 1}

# Port config — PORT is the preferred port (default 4000). With
# SONAR_PORT_RANGE set ("4001-4020"), a held PORT falls through to the first
# free port in the range; the bound port is published via Sonar.PortFile.
# Peers probe the same range to find us after a move.
port_range = Sonar.PortPicker.parse_range(System.get_env("SONAR_PORT_RANGE"))
preferred_port = String.to_integer(System.get_env("PORT", "4000"))
port = Sonar.PortPicker.pick(preferred_port, port_range, bind_ip)

config :sonar, SonarWeb.Endpoint, http: [port: port]
config :sonar, :peer_port_range, port_range

# DB path — plugin data dir takes precedence, then SONAR_DB, then default
# Skip in test env — test.exs sets the sandboxed DB path
if config_env() != :test do
  db_path =
    case System.get_env("SONATA_PLUGIN_DATA_DIR") do
      nil -> System.get_env("SONAR_DB", Path.expand("~/.sonar/sonar.db"))
      plugin_dir -> Path.join(plugin_dir, "sonar.db")
    end

  config :sonar, Sonar.Repo, database: db_path
end

if config_env() == :prod do
  # Generate a secret key base if not provided
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      :crypto.strong_rand_bytes(64) |> Base.encode64()

  # Bind to 0.0.0.0 by default — sonar is a peer-to-peer relay, cross-host
  # HTTP is its whole purpose. Auth is enforced at the request layer (bearer
  # tokens per the card.json pairing flow); exposing the port to the LAN is
  # correct for this plugin. SONAR_BIND_LOCAL=true opts back into loopback
  # only (e.g. for single-host dev/test setups that don't want the port
  # listening on the LAN). bind_ip is computed above so the port probe
  # tests the same address the endpoint binds.
  config :sonar, SonarWeb.Endpoint,
    http: [ip: bind_ip, port: port],
    secret_key_base: secret_key_base
end
