defmodule Sonar.Repo.Migrations.CreateInitialTables do
  use Ecto.Migration

  def change do
    # Agent identity — single row, this instance's identity
    create table(:identity, primary_key: false) do
      add :id, :string, primary_key: true, default: "singleton"
      add :name, :string, null: false
      add :instance_id, :string, null: false
      add :capabilities, :string, default: "[]"
      add :cert_fingerprint, :string

      timestamps()
    end

    # Known peers — other Sonar instances
    create table(:peers, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :hostname, :string, null: false
      add :port, :integer, default: 8400
      add :instance_id, :string
      add :cert_fingerprint, :string
      add :discovery_method, :string, default: "manual"
      add :connection_status, :string, default: "discovered"
      add :trust_level, :string, default: "basic"
      add :capabilities, :string, default: "[]"
      add :last_seen_at, :utc_datetime
      add :server_card_json, :text

      timestamps()
    end

    create index(:peers, [:connection_status])
    create index(:peers, [:hostname])
    create unique_index(:peers, [:instance_id])

    # Auth tokens for peers
    create table(:peer_tokens, primary_key: false) do
      add :id, :string, primary_key: true
      add :peer_id, references(:peers, type: :string, on_delete: :delete_all), null: false
      add :token_hash, :string, null: false
      add :scopes, :string, null: false, default: "query"
      add :expires_at, :utc_datetime
      add :last_used_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps()
    end

    create unique_index(:peer_tokens, [:token_hash])
    create index(:peer_tokens, [:peer_id])

    # Messages — async question/answer between peers
    create table(:messages, primary_key: false) do
      add :id, :string, primary_key: true
      add :peer_id, references(:peers, type: :string, on_delete: :nilify_all)
      add :direction, :string, null: false, default: "inbound"
      add :question, :text, null: false
      add :context, :text
      add :answer, :text
      add :status, :string, null: false, default: "pending"
      add :expires_at, :utc_datetime
      add :callback_url, :string
      add :answered_at, :utc_datetime

      timestamps()
    end

    create index(:messages, [:status])
    create index(:messages, [:peer_id])
    create index(:messages, [:direction])

    # Audit log — all peer interactions
    create table(:audit_log, primary_key: false) do
      add :id, :string, primary_key: true
      add :peer_id, references(:peers, type: :string, on_delete: :nilify_all)
      add :peer_name, :string
      add :action, :string, null: false
      add :request_body, :text
      add :response_status, :integer
      add :response_time_ms, :integer

      timestamps(updated_at: false)
    end

    create index(:audit_log, [:inserted_at])
    create index(:audit_log, [:peer_id])
  end
end
