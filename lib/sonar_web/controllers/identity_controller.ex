defmodule SonarWeb.IdentityController do
  use SonarWeb, :controller

  def show(conn, _params) do
    json(conn, Sonar.Identity.get())
  end

  def update(conn, params) do
    allowed = Map.take(params, ~w(name capabilities))

    allowed =
      case allowed["capabilities"] do
        list when is_list(list) -> Map.put(allowed, :capabilities, list)
        _ -> Map.delete(allowed, "capabilities")
      end

    allowed =
      case allowed["name"] do
        name when is_binary(name) and name != "" -> Map.put(allowed, :name, name)
        _ -> Map.delete(allowed, "name")
      end

    Sonar.Identity.update(allowed)
    json(conn, Sonar.Identity.get())
  end
end
