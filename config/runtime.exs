import Config

# Always start the server in releases
if System.get_env("PHX_SERVER") || config_env() == :prod do
  config :sonar, SonarWeb.Endpoint, server: true
end

# Port config — defaults to 4000
config :sonar, SonarWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

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

  config :sonar, SonarWeb.Endpoint,
    http: [ip: {127, 0, 0, 1}],
    secret_key_base: secret_key_base
end
