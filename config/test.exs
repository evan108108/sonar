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

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
