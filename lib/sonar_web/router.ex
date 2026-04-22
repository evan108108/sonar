defmodule SonarWeb.Router do
  use SonarWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Peer-facing API — requires Bearer token
  pipeline :peer_auth do
    plug :accepts, ["json"]
    plug SonarWeb.Plugs.BearerAuth
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

    # Peer tokens
    post "/peers/:peer_id/tokens", TokensController, :create
    get "/peers/:peer_id/tokens", TokensController, :index
    delete "/peers/:peer_id/tokens/:token_id", TokensController, :revoke

    # Messages
    get "/messages/inbox", MessagesController, :inbox
    get "/messages/:id", MessagesController, :show
    post "/messages/send", MessagesController, :send_message
    post "/messages/:id/reply", MessagesController, :reply
  end

  scope "/relay", SonarWeb do
    pipe_through :peer_auth

    get "/health", HealthController, :index
  end

  # Public discovery endpoint — how peers find out what this instance can do
  scope "/", SonarWeb do
    pipe_through :api

    get "/.well-known/sonar/card.json", ServerCardController, :show
  end
end
