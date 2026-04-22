defmodule Sonar.Schema.Peer do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  schema "peers" do
    field(:name, :string)
    field(:hostname, :string)
    field(:port, :integer, default: 8400)
    field(:instance_id, :string)
    field(:cert_fingerprint, :string)
    field(:discovery_method, :string, default: "manual")
    field(:connection_status, :string, default: "discovered")
    field(:trust_level, :string, default: "basic")
    field(:capabilities, :string, default: "[]")
    field(:last_seen_at, :utc_datetime)
    field(:server_card_json, :string)

    has_many(:tokens, Sonar.Schema.PeerToken, foreign_key: :peer_id)
    has_many(:messages, Sonar.Schema.Message, foreign_key: :peer_id)

    timestamps()
  end

  def changeset(peer, attrs) do
    peer
    |> cast(attrs, [
      :id,
      :name,
      :hostname,
      :port,
      :instance_id,
      :cert_fingerprint,
      :discovery_method,
      :connection_status,
      :trust_level,
      :capabilities,
      :last_seen_at,
      :server_card_json
    ])
    |> validate_required([:id, :name, :hostname])
    |> validate_inclusion(:connection_status, ~w(discovered paired offline revoked))
    |> validate_inclusion(:trust_level, ~w(basic trusted intimate))
    |> unique_constraint(:instance_id)
  end
end
