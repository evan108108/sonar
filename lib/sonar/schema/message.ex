defmodule Sonar.Schema.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  @session_id_format ~r/\A[A-Za-z0-9_-]{1,128}\z/

  schema "messages" do
    field(:direction, :string, default: "inbound")
    field(:question, :string)
    field(:context, :string)
    field(:answer, :string)
    field(:status, :string, default: "pending")
    field(:failure_reason, :string)
    field(:expires_at, :utc_datetime)
    field(:callback_url, :string)
    field(:remote_message_id, :string)
    field(:answered_at, :utc_datetime)
    field(:target_session_id, :string)
    field(:from_session_id, :string)

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
      :failure_reason,
      :expires_at,
      :callback_url,
      :remote_message_id,
      :answered_at,
      :target_session_id,
      :from_session_id
    ])
    |> validate_required([:id, :question])
    |> validate_inclusion(:direction, ~w(inbound outbound))
    |> validate_inclusion(:status, ~w(pending processing answered declined expired relayed failed))
    |> validate_optional_session_id(:target_session_id)
    |> validate_optional_session_id(:from_session_id)
  end

  # Only validate format when the field is present — nil/missing passes.
  defp validate_optional_session_id(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      cond do
        is_nil(value) -> []
        is_binary(value) and Regex.match?(@session_id_format, value) -> []
        true -> [{field, "has invalid format"}]
      end
    end)
  end
end
