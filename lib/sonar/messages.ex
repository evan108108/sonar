defmodule Sonar.Messages do
  @moduledoc """
  Context module for message operations.
  """

  import Ecto.Query
  alias Sonar.Repo
  alias Sonar.Schema.Message

  def inbox(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    status = Keyword.get(opts, :status)

    query =
      from(m in Message,
        where: m.direction == "inbound",
        order_by: [desc: m.inserted_at],
        limit: ^limit
      )

    query = if status, do: where(query, [m], m.status == ^status), else: query
    Repo.all(query)
  end

  def get(id) do
    Repo.get(Message, id)
  end

  def send_message(attrs) do
    id = gen_id()

    result =
      %Message{}
      |> Message.changeset(
        Map.merge(attrs, %{"id" => id, "direction" => "outbound", "status" => "pending"})
      )
      |> Repo.insert()

    # Attempt delivery via Erlang distribution if peer is connected
    case result do
      {:ok, message} ->
        maybe_relay_message(message)
        {:ok, message}

      error ->
        error
    end
  end

  def reply(message, answer) do
    result =
      message
      |> Message.changeset(%{
        "answer" => answer,
        "status" => "answered",
        "answered_at" => DateTime.utc_now()
      })
      |> Repo.update()

    # Push response back to peer if connected
    case result do
      {:ok, updated} ->
        maybe_relay_response(updated)
        {:ok, updated}

      error ->
        error
    end
  end

  def receive_message(attrs) do
    %Message{}
    |> Message.changeset(Map.merge(attrs, %{"direction" => "inbound", "status" => "pending"}))
    |> Repo.insert()
  end

  defp maybe_relay_message(message) do
    if relay_available?() and message.peer_id do
      Sonar.Relay.send_message(message.peer_id, %{
        "question" => message.question,
        "context" => message.context,
        "message_id" => message.id,
        "expires_at" => message.expires_at
      })
    end
  end

  defp maybe_relay_response(message) do
    if relay_available?() and message.peer_id and message.answer do
      Sonar.Relay.send_message(message.peer_id, %{
        "response_to" => message.id,
        "answer" => message.answer
      })
    end
  end

  defp relay_available? do
    Process.whereis(Sonar.Relay) != nil
  end

  defp gen_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
end
