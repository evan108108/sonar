defmodule Sonar.PortFileTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  test "write/2 publishes the port and leaves no temp file", %{tmp_dir: dir} do
    assert :ok = Sonar.PortFile.write(dir, 4007)
    assert File.read!(Path.join(dir, "sonar.port")) == "4007"
    refute File.exists?(Path.join(dir, "sonar.port.tmp"))
  end

  test "write/2 overwrites a stale file", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "sonar.port"), "4000")
    assert :ok = Sonar.PortFile.write(dir, 4001)
    assert File.read!(Path.join(dir, "sonar.port")) == "4001"
  end

  test "bound_port/0 falls back to the configured port when the server isn't running" do
    assert Sonar.PortFile.bound_port() ==
             Application.get_env(:sonar, SonarWeb.Endpoint)[:http][:port]
  end
end
