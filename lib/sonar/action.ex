defmodule Sonar.Action do
  @moduledoc """
  Defines an action — a single operation that is exposed as both
  an HTTP endpoint and an MCP tool. Add an action once, get both surfaces.
  """

  defstruct [
    :name,
    :description,
    :method,
    :path,
    :params,
    :handler,
    scope: nil
  ]

  @type param :: %{
    name: String.t(),
    type: :string | :integer | :boolean | :array | :object,
    required: boolean(),
    description: String.t()
  }

  @type t :: %__MODULE__{
    name: String.t(),
    description: String.t(),
    method: :get | :post | :put | :delete,
    path: String.t(),
    params: [param()],
    handler: (map() -> {:ok, any()} | {:error, any()}),
    scope: String.t() | nil
  }

  def param(name, type, opts \\ []) do
    %{
      name: name,
      type: type,
      required: Keyword.get(opts, :required, false),
      description: Keyword.get(opts, :description, "")
    }
  end
end
