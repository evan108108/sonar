defmodule Sonar.ActionRegistry do
  @moduledoc """
  Central registry of all Sonar actions. Each action is defined once
  and served as both an HTTP endpoint (via Phoenix) and an MCP tool
  (via stdio JSON-RPC). Add an action here, get both surfaces for free.
  """

  alias Sonar.Action

  def all do
    identity_actions() ++
    peer_actions() ++
    message_actions() ++
    system_actions()
  end

  def find(name) do
    Enum.find(all(), fn a -> a.name == name end)
  end

  def mcp_tool_schemas do
    Enum.map(all(), fn action ->
      properties =
        action.params
        |> Enum.map(fn p ->
          schema = %{"type" => to_string(p.type), "description" => p.description}
          {p.name, schema}
        end)
        |> Map.new()

      required =
        action.params
        |> Enum.filter(& &1.required)
        |> Enum.map(& &1.name)

      %{
        "name" => action.name,
        "description" => action.description,
        "inputSchema" => %{
          "type" => "object",
          "properties" => properties,
          "required" => required
        }
      }
    end)
  end

  @doc "Execute an action by name with the given args map"
  def execute(name, args \\ %{}) do
    case find(name) do
      nil -> {:error, "Unknown action: #{name}"}
      action -> action.handler.(args)
    end
  end

  # --- Action Definitions ---

  defp identity_actions do
    [
      %Action{
        name: "sonar_identity",
        description: "Get this Sonar instance's identity.",
        method: :get,
        path: "/api/identity",
        params: [],
        handler: fn _args -> {:ok, Sonar.Identity.get()} end
      },
      %Action{
        name: "sonar_identity_update",
        description: "Update this instance's name or capabilities.",
        method: :put,
        path: "/api/identity",
        params: [
          Action.param("name", :string, description: "New instance name"),
          Action.param("capabilities", :array, description: "Capability tags")
        ],
        handler: fn args ->
          changes = %{}
          changes = if args["name"], do: Map.put(changes, :name, args["name"]), else: changes
          changes = if args["capabilities"], do: Map.put(changes, :capabilities, args["capabilities"]), else: changes
          Sonar.Identity.update(changes)
          {:ok, Sonar.Identity.get()}
        end
      }
    ]
  end

  defp peer_actions do
    [
      %Action{
        name: "sonar_peers",
        description: "List all known peers.",
        method: :get,
        path: "/api/peers",
        params: [],
        handler: fn _args ->
          peers = Sonar.Peers.list()
          {:ok, Enum.map(peers, &peer_json/1)}
        end
      },
      %Action{
        name: "sonar_peer_register",
        description: "Register a new peer by hostname.",
        method: :post,
        path: "/api/peers",
        params: [
          Action.param("name", :string, required: true, description: "Peer name"),
          Action.param("hostname", :string, required: true, description: "Peer hostname"),
          Action.param("port", :integer, description: "Peer port (default 8400)")
        ],
        handler: fn args -> Sonar.Peers.create(args) end
      },
      %Action{
        name: "sonar_peer_trust",
        description: "Set trust level for a peer (basic, trusted, intimate).",
        method: :put,
        path: "/api/peers/:peer_id/trust",
        params: [
          Action.param("peer_id", :string, required: true, description: "Peer ID"),
          Action.param("trust_level", :string, required: true, description: "Trust level")
        ],
        handler: fn args ->
          case Sonar.Peers.get(args["peer_id"]) do
            nil -> {:error, :not_found}
            peer -> Sonar.Peers.set_trust(peer, args["trust_level"])
          end
        end
      }
    ]
  end

  defp message_actions do
    [
      %Action{
        name: "sonar_send",
        description: "Send a message to a peer. Returns immediately with a message_id.",
        method: :post,
        path: "/api/messages/send",
        params: [
          Action.param("peer_id", :string, required: true, description: "Target peer ID (use the 'id' field from sonar_peers, NOT instance_id)"),
          Action.param("question", :string, required: true, description: "The message to send"),
          Action.param("context", :string, description: "Additional context"),
          Action.param("expires_at", :integer, description: "TTL as epoch ms")
        ],
        handler: fn args -> Sonar.Messages.send_message(args) end
      },
      %Action{
        name: "sonar_inbox",
        description: "Check inbox for incoming messages from peers.",
        method: :get,
        path: "/api/messages/inbox",
        params: [
          Action.param("status", :string, description: "Filter by status"),
          Action.param("limit", :integer, description: "Max results (default 50)")
        ],
        handler: fn args ->
          opts = []
          opts = if args["status"], do: [{:status, args["status"]} | opts], else: opts
          opts = if args["limit"], do: [{:limit, args["limit"]} | opts], else: opts
          messages = Sonar.Messages.inbox(opts)
          {:ok, Enum.map(messages, &message_json/1)}
        end
      },
      %Action{
        name: "sonar_message",
        description: "Get a specific message by ID.",
        method: :get,
        path: "/api/messages/:message_id",
        params: [
          Action.param("message_id", :string, required: true, description: "Message ID")
        ],
        handler: fn args ->
          case Sonar.Messages.get(args["message_id"]) do
            nil -> {:error, :not_found}
            msg -> {:ok, message_json(msg)}
          end
        end
      },
      %Action{
        name: "sonar_reply",
        description: "Reply to an incoming message.",
        method: :post,
        path: "/api/messages/:message_id/reply",
        params: [
          Action.param("message_id", :string, required: true, description: "Message ID"),
          Action.param("answer", :string, required: true, description: "Your response")
        ],
        handler: fn args ->
          case Sonar.Messages.get(args["message_id"]) do
            nil -> {:error, :not_found}
            msg -> Sonar.Messages.reply(msg, args["answer"])
          end
        end
      }
    ]
  end

  defp system_actions do
    [
      %Action{
        name: "sonar_health",
        description: "Check Sonar health and connectivity.",
        method: :get,
        path: "/api/health",
        params: [],
        handler: fn _args ->
          {:ok, %{
            status: "ok",
            app: "sonar",
            version: Application.spec(:sonar, :vsn) |> to_string(),
            node: Node.self() |> to_string()
          }}
        end
      },
      %Action{
        name: "sonar_card",
        description: "Get this instance's server card.",
        method: :get,
        path: "/.well-known/sonar/card.json",
        params: [],
        handler: fn _args ->
          identity = Sonar.Identity.get()
          {:ok, %{
            version: "1.0",
            agent: %{
              name: identity.name,
              instance_id: identity.instance_id,
              version: identity.version,
              description: "Sonar peer-to-peer agent relay"
            },
            capabilities: identity.capabilities,
            authentication: %{type: "bearer", pairing_required: true}
          }}
        end
      }
    ]
  end

  # --- JSON serialization helpers ---

  defp peer_json(peer) do
    %{
      id: peer.id,
      name: peer.name,
      hostname: peer.hostname,
      port: peer.port,
      instance_id: peer.instance_id,
      connection_status: peer.connection_status,
      trust_level: peer.trust_level,
      discovery_method: peer.discovery_method,
      capabilities: Jason.decode!(peer.capabilities || "[]"),
      last_seen_at: peer.last_seen_at
    }
  end

  defp message_json(msg) do
    %{
      id: msg.id,
      peer_id: msg.peer_id,
      direction: msg.direction,
      question: msg.question,
      context: msg.context,
      answer: msg.answer,
      status: msg.status,
      expires_at: msg.expires_at,
      answered_at: msg.answered_at
    }
  end
end
