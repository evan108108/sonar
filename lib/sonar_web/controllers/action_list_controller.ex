defmodule SonarWeb.ActionListController do
  use SonarWeb, :controller

  def index(conn, _params) do
    actions =
      Sonar.ActionRegistry.all()
      |> Enum.map(fn action ->
        %{
          name: action.name |> String.replace("sonar_", ""),
          description: action.description,
          method: to_string(action.method),
          path: action.path,
          params:
            Enum.map(action.params, fn p ->
              %{
                name: p.name,
                type: to_string(p.type),
                required: p.required,
                description: p.description
              }
            end)
        }
      end)

    json(conn, actions)
  end
end
