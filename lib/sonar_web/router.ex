defmodule SonarWeb.Router do
  use SonarWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Public routes — no auth
  scope "/api", SonarWeb do
    pipe_through :api

    get "/health", HealthController, :index
    get "/identity", IdentityController, :show
  end
end
