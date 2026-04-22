ExUnit.start()

# Migrate the in-memory test DB — this is the standard Phoenix pattern.
# Each test still gets an isolated sandbox transaction that rolls back.
Ecto.Migrator.run(Sonar.Repo, :up, all: true)
Ecto.Adapters.SQL.Sandbox.mode(Sonar.Repo, :manual)
