defmodule Sonar.PeerHealthTest do
  use ExUnit.Case

  import Sonar.Fixtures

  alias Sonar.{PeerHealth, Peers, Repo}
  alias Sonar.Schema.{Message, Peer}

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  # A fake network: %{"host:port" => instance_id}. Health answers for every
  # listed address; card.json carries the listed instance_id.
  defp net(hosts) do
    fn url, _timeout ->
      uri = URI.parse(url)

      case Map.fetch(hosts, "#{uri.host}:#{uri.port}") do
        {:ok, id} ->
          case uri.path do
            "/api/health" -> {:ok, ~s({"status":"ok","app":"sonar","node":"sonar@#{uri.host}"})}
            "/.well-known/sonar/card.json" -> {:ok, Jason.encode!(%{agent: %{instance_id: id}})}
          end

        :error ->
          {:error, :econnrefused}
      end
    end
  end

  defp check(peer, hosts, range \\ 4001..4005),
    do: PeerHealth.check_peer(peer, get: net(hosts), range: range, connect: false)

  test "a healthy peer is marked seen and un-stuck from offline" do
    p =
      peer(%{
        hostname: "scout-cloud",
        port: 4001,
        instance_id: "scout-id",
        connection_status: "offline"
      })

    assert {:ok, checked} = check(p, %{"scout-cloud:4001" => "scout-id"})
    assert checked.connection_status == "discovered"
    assert checked.port == 4001
  end

  test "a peer that moved ports is found in the range by instance_id" do
    p = peer(%{hostname: "scout-cloud", port: 4001, instance_id: "scout-id"})

    assert {:ok, moved} = check(p, %{"scout-cloud:4004" => "scout-id"})
    assert moved.port == 4004
    assert Repo.get(Peer, p.id).port == 4004
  end

  test "a card with a different instance_id is never adopted" do
    p = peer(%{hostname: "scout-cloud", port: 4001, instance_id: "scout-id", last_seen_at: nil})

    assert {:error, offline} = check(p, %{"scout-cloud:4002" => "someone-else"})
    assert offline.connection_status == "offline"
    assert Repo.get(Peer, p.id).port == 4001
  end

  test "no range configured means no probing" do
    p = peer(%{hostname: "scout-cloud", port: 4001, instance_id: "scout-id", last_seen_at: nil})
    assert {:error, _} = check(p, %{"scout-cloud:4002" => "scout-id"}, nil)
  end

  test "a recently seen peer is not clobbered to offline by one failed probe" do
    p = peer(%{hostname: "scout-cloud", port: 4001, instance_id: "scout-id"})
    {:ok, p} = Peers.update(p, %{"last_seen_at" => DateTime.utc_now()})

    assert {:error, still} = check(p, %{})
    assert still.connection_status == "discovered"
  end

  test "an unbound row learns its instance_id from the card" do
    p = peer(%{hostname: "evans-macbook-pro", port: 4001, instance_id: nil})

    assert {:ok, bound} = check(p, %{"evans-macbook-pro:4001" => "sona-id"})
    assert bound.instance_id == "sona-id"
  end

  test "an unbound row whose card names our own instance is left alone" do
    me = Sonar.Identity.get().instance_id
    p = peer(%{hostname: "loopback", port: 4001, instance_id: nil})

    assert {:ok, same} = check(p, %{"loopback:4001" => me})
    assert same.instance_id == nil
  end

  test "an unbound reachable row merges into the stale row holding its instance_id" do
    stale =
      peer(%{
        name: "sona",
        hostname: "192.168.0.51",
        port: 4000,
        instance_id: "sona-id",
        trust_level: "basic",
        connection_status: "offline"
      })

    live =
      peer(%{
        name: "evan-laptop",
        hostname: "evans-macbook-pro.tail079090.ts.net",
        port: 4001,
        instance_id: nil,
        trust_level: "trusted"
      })

    msg = outbound_message(%{peer: live, question: "hello?"})

    assert {:ok, merged} = check(live, %{"evans-macbook-pro.tail079090.ts.net:4001" => "sona-id"})

    # The id-holding row survives under its own name, with the live address
    # and the higher trust level; the dupe is gone and its history moved.
    assert merged.id == stale.id
    assert merged.name == "sona"
    assert merged.hostname == "evans-macbook-pro.tail079090.ts.net"
    assert merged.port == 4001
    assert merged.trust_level == "trusted"
    assert merged.connection_status == "discovered"
    assert Repo.get(Peer, live.id) == nil
    assert Repo.get(Message, msg.id).peer_id == stale.id
  end

  test "an id-less row on a dead port finds the peer by host and merges into its id row" do
    # Scout's side after we move from 4000 to 4001: "sona" is the dead LAN row
    # that holds our id, "evan-laptop" the Tailscale row with no id, still on :4000.
    sona =
      peer(%{
        name: "sona",
        hostname: "192.168.0.51",
        port: 4000,
        instance_id: "sona-id",
        last_seen_at: nil
      })

    laptop =
      peer(%{
        name: "evan-laptop",
        hostname: "evans-macbook-pro.tail079090.ts.net",
        port: 4000,
        instance_id: nil,
        trust_level: "trusted"
      })

    assert {:ok, merged} =
             check(laptop, %{"evans-macbook-pro.tail079090.ts.net:4001" => "sona-id"})

    assert merged.id == sona.id
    assert merged.name == "sona"
    assert {merged.hostname, merged.port} == {"evans-macbook-pro.tail079090.ts.net", 4001}
    assert merged.trust_level == "trusted"
    assert Repo.get(Peer, laptop.id) == nil
  end

  test "an id-less row's probe never adopts our own card" do
    me = Sonar.Identity.get().instance_id
    p = peer(%{hostname: "loopback", port: 4000, instance_id: nil, last_seen_at: nil})

    assert {:error, _} = check(p, %{"loopback:4002" => me})
    assert Repo.get(Peer, p.id).port == 4000
  end

  describe "Peers.follow_port/2" do
    test "adopts a new valid port" do
      p = peer(%{port: 4001})
      assert {:ok, %{port: 4003}} = Peers.follow_port(p, 4003)
      assert {:ok, %{port: 4005}} = Peers.follow_port(p, "4005")
    end

    test "ignores missing or invalid ports" do
      p = peer(%{port: 4001})
      assert {:ok, %{port: 4001}} = Peers.follow_port(p, nil)
      assert {:ok, %{port: 4001}} = Peers.follow_port(p, "abc")
      assert {:ok, %{port: 4001}} = Peers.follow_port(p, 0)
      assert {:ok, %{port: 4001}} = Peers.follow_port(p, 70_000)
    end
  end
end
