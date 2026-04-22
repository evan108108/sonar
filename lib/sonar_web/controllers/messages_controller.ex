defmodule SonarWeb.MessagesController do
  use SonarWeb, :controller

  import Ecto.Query
  alias Sonar.Repo
  alias Sonar.Schema.Message

  # List incoming messages (inbox)
  def inbox(conn, params) do
    status = params["status"]

    query =
      from(m in Message,
        where: m.direction == "inbound",
        order_by: [desc: m.inserted_at],
        limit: ^(parse_int(params["limit"]) || 50)
      )

    query = if status, do: where(query, [m], m.status == ^status), else: query
    messages = Repo.all(query)
    json(conn, Enum.map(messages, &message_to_json/1))
  end

  # Get a specific message by ID
  def show(conn, %{"id" => id}) do
    case Repo.get(Message, id) do
      nil -> conn |> put_status(404) |> json(%{error: "Message not found"})
      message -> json(conn, message_to_json(message))
    end
  end

  # Send a message to a peer (outbound)
  def send_message(conn, %{"peer_id" => peer_id, "question" => question} = params) do
    id = gen_id()

    changeset = Message.changeset(%Message{}, %{
      "id" => id,
      "peer_id" => peer_id,
      "direction" => "outbound",
      "question" => question,
      "context" => params["context"],
      "status" => "pending",
      "expires_at" => parse_datetime(params["expires_at"]),
      "callback_url" => params["callback_url"]
    })

    case Repo.insert(changeset) do
      {:ok, message} ->
        # TODO: deliver to peer via Erlang distribution or HTTP
        conn |> put_status(202) |> json(%{
          message_id: message.id,
          status: "pending",
          poll_url: "/api/messages/#{message.id}"
        })

      {:error, changeset} ->
        conn |> put_status(422) |> json(%{error: format_errors(changeset)})
    end
  end

  # Reply to an incoming message
  def reply(conn, %{"id" => id, "answer" => answer} = _params) do
    case Repo.get(Message, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Message not found"})

      message ->
        changeset = Message.changeset(message, %{
          "answer" => answer,
          "status" => "answered",
          "answered_at" => DateTime.utc_now()
        })

        case Repo.update(changeset) do
          {:ok, message} ->
            # TODO: deliver response to peer via callback_url or Erlang distribution
            maybe_deliver_callback(message)
            json(conn, message_to_json(message))

          {:error, changeset} ->
            conn |> put_status(422) |> json(%{error: format_errors(changeset)})
        end
    end
  end

  defp message_to_json(message) do
    %{
      id: message.id,
      peer_id: message.peer_id,
      direction: message.direction,
      question: message.question,
      context: message.context,
      answer: message.answer,
      status: message.status,
      expires_at: message.expires_at,
      answered_at: message.answered_at,
      inserted_at: message.inserted_at
    }
  end

  defp maybe_deliver_callback(%{callback_url: nil}), do: :ok
  defp maybe_deliver_callback(%{callback_url: _url} = _message) do
    # TODO: POST response to callback_url
    :ok
  end

  defp gen_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  defp parse_int(nil), do: nil
  defp parse_int(s) when is_binary(s), do: String.to_integer(s)
  defp parse_int(i) when is_integer(i), do: i

  defp parse_datetime(nil), do: nil
  defp parse_datetime(ms) when is_integer(ms), do: DateTime.from_unix!(ms, :millisecond)
  defp parse_datetime(s) when is_binary(s), do: parse_datetime(String.to_integer(s))

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
