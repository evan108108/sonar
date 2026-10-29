defmodule Sonar.PortPickerTest do
  use ExUnit.Case, async: true

  alias Sonar.PortPicker

  describe "parse_range/1" do
    test "parses lo-hi" do
      assert PortPicker.parse_range("4001-4020") == 4001..4020
      assert PortPicker.parse_range(" 4001 - 4003 ") == 4001..4003
    end

    test "rejects malformed or out-of-bounds specs" do
      assert PortPicker.parse_range(nil) == nil
      assert PortPicker.parse_range("") == nil
      assert PortPicker.parse_range("4001") == nil
      assert PortPicker.parse_range("4020-4001") == nil
      assert PortPicker.parse_range("0-10") == nil
      assert PortPicker.parse_range("4001-70000") == nil
      assert PortPicker.parse_range("a-b") == nil
    end
  end

  describe "pick/4" do
    test "no range means the preferred port, unprobed" do
      assert PortPicker.pick(4000, nil, {127, 0, 0, 1}, fn _, _ -> flunk("probed") end) == 4000
    end

    test "preferred port wins when free" do
      assert PortPicker.pick(4001, 4001..4020, {127, 0, 0, 1}, fn _, _ -> true end) == 4001
    end

    test "held preferred port falls through to the first free port in the range" do
      held = MapSet.new([4000, 4001, 4002])
      free? = fn port, _ip -> not MapSet.member?(held, port) end
      assert PortPicker.pick(4000, 4001..4020, {127, 0, 0, 1}, free?) == 4003
    end

    test "a preferred port inside the range is tried once, first" do
      parent = self()
      free? = fn port, _ip -> send(parent, {:probed, port}) && port == 4005 end
      assert PortPicker.pick(4003, 4001..4005, {127, 0, 0, 1}, free?) == 4005
      assert_received {:probed, 4003}
      probed = for {:probed, p} <- flush(), do: p
      refute 4003 in probed
    end

    test "everything held returns the preferred port so the bind fails loudly" do
      assert PortPicker.pick(4000, 4001..4003, {127, 0, 0, 1}, fn _, _ -> false end) == 4000
    end
  end

  describe "free?/2" do
    test "sees a port held by another listener" do
      {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
      {:ok, port} = :inet.port(socket)

      refute PortPicker.free?(port, {127, 0, 0, 1})

      :gen_tcp.close(socket)
      assert PortPicker.free?(port, {127, 0, 0, 1})
    end

    test "picks past a really-held port" do
      {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
      {:ok, held} = :inet.port(socket)

      picked = PortPicker.pick(held, (held + 1)..(held + 20), {127, 0, 0, 1})
      assert picked != held
      assert picked in (held + 1)..(held + 20)

      :gen_tcp.close(socket)
    end
  end

  defp flush(acc \\ []) do
    receive do
      msg -> flush([msg | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
