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

    %Message{}
    |> Message.changeset(Map.merge(attrs, %{"id" => id, "direction" => "outbound", "status" => "pending"}))
    |> Repo.insert()
  end

  def reply(message, answer) do
    message
    |> Message.changeset(%{
      "answer" => answer,
      "status" => "answered",
      "answered_at" => DateTime.utc_now()
    })
    |> Repo.update()
  end

  def receive_message(attrs) do
    %Message{}
    |> Message.changeset(Map.merge(attrs, %{"direction" => "inbound", "status" => "pending"}))
    |> Repo.insert()
  end

  defp gen_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
end
