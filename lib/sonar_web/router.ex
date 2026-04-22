defmodule SonarWeb.Router do
  use SonarWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Local API — no auth, localhost only
  # Agent runtimes connect here to send/receive messages
  scope "/api", SonarWeb do
    pipe_through :api

    # System
    get "/health", HealthController, :index
    get "/identity", IdentityController, :show
    put "/identity", IdentityController, :update

    # Peers
    get "/peers", PeersController, :index
    get "/peers/:id", PeersController, :show
    post "/peers", PeersController, :create
    put "/peers/:id", PeersController, :update
    delete "/peers/:id", PeersController, :delete

    # Messages
    get "/messages/inbox", MessagesController, :inbox
    get "/messages/:id", MessagesController, :show
    post "/messages/send", MessagesController, :send_message
    post "/messages/:id/reply", MessagesController, :reply
  end
end
