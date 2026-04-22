defmodule Sonar.Schema.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  schema "messages" do
    field(:direction, :string, default: "inbound")
    field(:question, :string)
    field(:context, :string)
    field(:answer, :string)
    field(:status, :string, default: "pending")
    field(:expires_at, :utc_datetime)
    field(:callback_url, :string)
    field(:answered_at, :utc_datetime)

    belongs_to(:peer, Sonar.Schema.Peer, type: :string)

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :id,
      :peer_id,
      :direction,
      :question,
      :context,
      :answer,
      :status,
      :expires_at,
      :callback_url,
      :answered_at
    ])
    |> validate_required([:id, :question])
    |> validate_inclusion(:direction, ~w(inbound outbound))
    |> validate_inclusion(:status, ~w(pending processing answered declined expired))
  end
end
