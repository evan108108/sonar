defmodule SonarWeb.SonarSocket do
  use Phoenix.Socket

  channel "messages:*", SonarWeb.MessagesChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
