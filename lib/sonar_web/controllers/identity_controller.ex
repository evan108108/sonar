defmodule SonarWeb.IdentityController do
  use SonarWeb, :controller

  def show(conn, _params) do
    identity = Sonar.Identity.get()
    json(conn, identity)
  end
end
