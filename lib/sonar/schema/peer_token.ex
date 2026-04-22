defmodule Sonar.Schema.PeerToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  schema "peer_tokens" do
    field(:token_hash, :string)
    field(:scopes, :string, default: "query")
    field(:expires_at, :utc_datetime)
    field(:last_used_at, :utc_datetime)
    field(:revoked_at, :utc_datetime)

    belongs_to(:peer, Sonar.Schema.Peer, type: :string)

    timestamps()
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:id, :peer_id, :token_hash, :scopes, :expires_at, :revoked_at])
    |> validate_required([:id, :peer_id, :token_hash])
    |> unique_constraint(:token_hash)
  end
end
