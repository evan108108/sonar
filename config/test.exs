import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :sonar, SonarWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "UCIkvIS3sb0bh/QYUMuJThdgKucR1wfYFPbNnuUqKkSVUeeEH0zDEfyHhWK5q+LW",
  server: false

# Use file-based SQLite for tests (in-memory has pool issues with sandbox)
config :sonar, Sonar.Repo,
  database: "/tmp/sonar_test.db",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

# Skip auto-migrator in test — test_helper.exs handles it
config :sonar, skip_migrator: true

# Skip HTTP relay fallback in tests — fake peer hostnames would hang curl
config :sonar, skip_http_relay: true

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Point session discovery at a guaranteed-dead port so the "Sonata loopback
# unreachable" tests are deterministic even when a live Sonata runs on the host.
config :sonar, sonata_targets_url: "http://127.0.0.1:1/api/dm/targets"

# Discovery/Relay would hit the DB from a process outside the test's own
# Ecto SQL Sandbox ownership → ownership crash. Turn off in tests; the
# relay_test.exs "started by default" assertion is now false in test env,
# but that expectation is prod-shaped anyway.
config :sonar, :discovery_enabled, false

# PeerHealth polls peers from outside the test's Sandbox ownership, same as
# Discovery. Tests call Sonar.PeerHealth.check_peer/2 directly instead.
config :sonar, :peer_health_enabled, false
