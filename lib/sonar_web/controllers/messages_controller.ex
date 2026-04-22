defmodule SonarWeb.MessagesController do
  use SonarWeb, :controller

  alias Sonar.Messages

  def inbox(conn, params) do
    opts =
      [
        limit: parse_int(params["limit"]) || 50,
        status: params["status"]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    messages = Messages.inbox(opts)
    json(conn, Enum.map(messages, &message_to_json/1))
  end

  def show(conn, %{"id" => id}) do
    case Messages.get(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Message not found"})
      message -> json(conn, message_to_json(message))
    end
  end

  def send_message(conn, %{"peer_id" => peer_id, "question" => question} = params) do
    attrs = %{
      "peer_id" => peer_id,
      "question" => question,
      "context" => params["context"],
      "expires_at" => parse_datetime(params["expires_at"]),
      "callback_url" => params["callback_url"]
    }

    case Messages.send_message(attrs) do
      {:ok, message} ->
        conn
        |> put_status(202)
        |> json(%{
          message_id: message.id,
          status: "pending",
          poll_url: "/api/messages/#{message.id}"
        })

      {:error, changeset} ->
        conn |> put_status(422) |> json(%{error: format_errors(changeset)})
    end
  end

  def send_message(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing required fields: peer_id, question"})
  end

  def reply(conn, %{"id" => id, "answer" => answer}) do
    case Messages.get(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Message not found"})

      message ->
        case Messages.reply(message, answer) do
          {:ok, message} ->
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
