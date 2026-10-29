defmodule Sonar.PortPicker do
  @moduledoc """
  Chooses the HTTP port at boot.

  `PORT` is the preferred port. When `SONAR_PORT_RANGE` (e.g. `"4001-4020"`)
  is set and the preferred port is already held, the first free port in the
  range wins. Another daemon squatting the port (NoMachine's nxd binds *:4000
  as root on reboot) then costs a port number instead of the whole plugin.

  The range is deliberately small and fixed rather than ephemeral: remote
  peers recover a moved port by probing that same range for our card
  (`Sonar.PeerHealth`), which only works if the range is known on both ends.

  Called from `config/runtime.exs`, so it must only depend on `:kernel`.
  """

  @doc "Parses `\"4001-4020\"` into `4001..4020`. Anything malformed is nil."
  def parse_range(nil), do: nil

  def parse_range(spec) when is_binary(spec) do
    with [lo, hi] <- String.split(String.trim(spec), "-", parts: 2),
         {lo, ""} <- Integer.parse(String.trim(lo)),
         {hi, ""} <- Integer.parse(String.trim(hi)),
         true <- lo > 0 and hi <= 65_535 and lo <= hi do
      lo..hi
    else
      _ -> nil
    end
  end

  @doc """
  Returns the preferred port when it's free (or when there is no range to
  fall back to), else the first free port in `range`. If every candidate is
  held, returns the preferred port so the endpoint fails loudly with
  eaddrinuse rather than silently binding somewhere unexpected.

  `free?` is injectable for tests; it defaults to a real bind probe.
  """
  def pick(preferred, range, ip \\ {0, 0, 0, 0}, free? \\ &free?/2)

  def pick(preferred, nil, _ip, _free?), do: preferred

  def pick(preferred, range, ip, free?) do
    candidates = [preferred | Enum.reject(range, &(&1 == preferred))]
    Enum.find(candidates, preferred, &free?.(&1, ip))
  end

  @doc """
  True when `port` can be bound on `ip` right now. A real bind sees
  listeners owned by other users (root daemons) that `lsof` run as the
  current user can't.
  """
  def free?(port, ip) do
    case :gen_tcp.listen(port, [:binary, active: false, reuseaddr: false, ip: ip]) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end
end
