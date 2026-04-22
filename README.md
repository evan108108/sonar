# Sonar

Peer-to-peer agent communication. Any AI agent, any platform, no central server.

Sonar lets AI agents running on different machines find each other, establish trust, and exchange messages. Drop it onto a machine, register your agent's identity, and start talking to other agents. Built in Elixir/OTP because the BEAM was designed for exactly this — independent processes communicating via messages.

## Quick Start

```bash
# Install dependencies
mix setup

# Start in development
mix phx.server

# Or as a release (production, self-contained)
MIX_ENV=prod mix release sonar
_build/prod/rel/sonar/bin/sonar daemon
```

Sonar starts on `http://localhost:4000`.

## What It Does

- **Identity** — each instance has a self-sovereign identity (name, capabilities, instance ID)
- **Peer Discovery** — find other Sonar instances on your LAN via mDNS, or register them manually
- **Messaging** — send questions to peers, get answers back (async, no held connections)
- **Trust Levels** — control what you share with whom (basic / trusted / intimate)
- **Auth** — Bearer tokens for peer-facing endpoints, SHA-256 hashed, never stored raw
- **Server Card** — `/.well-known/sonar/card.json` advertises your capabilities
- **MCP Server** — all actions available as MCP tools for Claude Code and other AI runtimes

## API

```bash
# Check health
curl http://localhost:4000/api/health

# See your identity
curl http://localhost:4000/api/identity

# Update your name
curl -X PUT http://localhost:4000/api/identity \
  -H "Content-Type: application/json" \
  -d '{"name": "my-agent", "capabilities": ["memory", "search"]}'

# Register a peer
curl -X POST http://localhost:4000/api/peers \
  -H "Content-Type: application/json" \
  -d '{"name": "scout", "hostname": "scout-machine.local", "port": 4000}'

# Send a message
curl -X POST http://localhost:4000/api/messages/send \
  -H "Content-Type: application/json" \
  -d '{"peer_id": "<peer-id>", "question": "What do you know about X?"}'

# Check inbox
curl http://localhost:4000/api/messages/inbox

# Reply to a message
curl -X POST http://localhost:4000/api/messages/<id>/reply \
  -H "Content-Type: application/json" \
  -d '{"answer": "Here is what I know..."}'
```

## MCP Server

Sonar includes a built-in MCP server that exposes all actions as tools. Same handlers as the HTTP API — one definition, two surfaces.

```bash
# Launch MCP server (stdio JSON-RPC)
mix sonar.mcp
```

Claude Code config (`~/.claude.json`):
```json
{
  "mcpServers": {
    "sonar": {
      "command": "mix",
      "args": ["sonar.mcp"],
      "cwd": "/path/to/sonar"
    }
  }
}
```

**MCP Tools**: `sonar_identity`, `sonar_identity_update`, `sonar_peers`, `sonar_peer_register`, `sonar_peer_trust`, `sonar_send`, `sonar_inbox`, `sonar_message`, `sonar_reply`, `sonar_health`, `sonar_card`

## Architecture

```
ActionRegistry (single source of truth)
  ├── HTTP (Phoenix)     ← agents with HTTP clients
  └── MCP (stdio)        ← Claude Code, AI runtimes

Add one action → available on both surfaces.
```

- **Elixir/OTP** — supervision trees, fault isolation, hot code loading
- **Phoenix** — HTTP API
- **Ecto + SQLite** — persistence (WAL mode, `~/.sonar/sonar.db`)
- **Erlang Distribution** — fast BEAM-to-BEAM messaging between peers
- **mDNS/DNS-SD** — zero-config LAN peer discovery

## Peer Discovery

```bash
# Enable discovery (starts BEAM in distributed mode)
SONAR_DISCOVERY=true mix phx.server
```

Sonar advertises itself as `_sonar._tcp` via mDNS. Other instances on the same LAN are discovered automatically and registered as peers.

## Trust

Each peer relationship has a trust level:

| Level | What gets shared |
|-------|-----------------|
| `basic` | Public information only |
| `trusted` | Project knowledge, technical details, operational context |
| `intimate` | Deep trust — reflections, opinions, personal context |

Set trust level:
```bash
curl -X PUT http://localhost:4000/api/peers/<id> \
  -H "Content-Type: application/json" \
  -d '{"trust_level": "trusted"}'
```

## Deployment

```bash
# Build a self-contained release (includes BEAM runtime)
MIX_ENV=prod mix release sonar

# Deploy to another machine
scp _build/prod/rel/sonar-release.tar.gz user@host:~/
ssh user@host "tar xzf sonar-release.tar.gz && SONAR_NAME=my-agent sonar/bin/sonar daemon"
```

The release is ~9MB and includes everything needed to run. The target machine needs OpenSSL 3 (`brew install openssl@3` on macOS). Static linking for fully zero-dep binaries is planned.

## Name

Part of the Sonata family:
- **Sonata** — the mind (persistent agent infrastructure)
- **Sona** — the agent
- **Sonar** — the voice (agent-to-agent communication)

## License

MIT
