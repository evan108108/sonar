defmodule SonarWeb.MessagesChannel do
  use Phoenix.Channel

  @impl true
  def join("messages:events", _payload, socket) do
    {:ok, socket}
  end
end
