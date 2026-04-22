defmodule Sonar.Repo do
  use Ecto.Repo,
    otp_app: :sonar,
    adapter: Ecto.Adapters.SQLite3
end
