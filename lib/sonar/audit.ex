defmodule Sonar.Audit do
  @moduledoc """
  Writes to the audit_log table. Captures every peer-facing relay interaction
  so the local agent can inspect what happened without re-reading logs.
  """

  import Ecto.Query
  alias Sonar.Repo

  @doc """
  Record a single audit event. Safe to call from a controller — never raises;
  a logging failure should not break the primary request.
  """
  def log(attrs) do
    row = %{
      id: gen_id(),
      peer_id: attrs[:peer_id],
      peer_name: attrs[:peer_name],
      action: attrs[:action] || "unknown",
      request_body: truncate(attrs[:request_body]),
      response_status: attrs[:response_status],
      response_time_ms: attrs[:response_time_ms],
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    try do
      Repo.insert_all("audit_log", [row])
      :ok
    rescue
      _ -> :error
    end
  end

  def recent(limit \\ 50) do
    Repo.all(
      from(a in "audit_log",
        order_by: [desc: a.inserted_at],
        limit: ^limit,
        select: %{
          id: a.id,
          peer_id: a.peer_id,
          peer_name: a.peer_name,
          action: a.action,
          response_status: a.response_status,
          response_time_ms: a.response_time_ms,
          inserted_at: a.inserted_at
        }
      )
    )
  end

  defp gen_id, do: :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)

  defp truncate(nil), do: nil
  defp truncate(s) when is_binary(s) and byte_size(s) > 8192, do: binary_part(s, 0, 8192)
  defp truncate(s) when is_binary(s), do: s
  defp truncate(other), do: inspect(other) |> truncate()
end
