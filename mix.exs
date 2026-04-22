defmodule Sonar.MixProject do
  use Mix.Project

  def project do
    [
      app: :sonar,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      releases: releases(),
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Sonar.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:ecto_sql, "~> 3.12"},
      {:ecto_sqlite3, "~> 0.17"},
      {:mox, "~> 1.0", only: :test},
      {:mdns, "~> 1.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp releases do
    [
      sonar: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, &copy_plugin_manifest/1, :tar, &repack_with_manifest/1]
      ]
    ]
  end

  # Copy sonar.plugin.json into the release root. Mix's built-in :tar step
  # archives only bin/erts-*/lib/releases, so loose files here are ignored —
  # the post-tar repack step is what actually ships the manifest.
  defp copy_plugin_manifest(release) do
    source = Path.expand("sonar.plugin.json", __DIR__)
    dest = Path.join(release.path, "sonar.plugin.json")
    File.cp!(source, dest)
    release
  end

  # Repack the release tarball so it includes sonar.plugin.json at the root.
  # Sonata's PluginManager expects to find `<name>.plugin.json` at the tarball
  # root when installing. Runs after :tar — overwrites the same tarball path.
  defp repack_with_manifest(release) do
    # release.path is _build/<env>/rel/<name>; the tar lives at _build/<env>/<name>-<version>.tar.gz
    tar_path =
      Path.join(
        Path.dirname(Path.dirname(release.path)),
        "#{release.name}-#{release.version}.tar.gz"
      )

    unless File.exists?(tar_path) do
      raise "repack_with_manifest: expected tarball at #{tar_path}"
    end

    # Extract to a temp dir, add the manifest at the root, repack.
    tmp = Path.join(System.tmp_dir!(), "sonar-plugin-repack-#{:os.system_time(:millisecond)}")
    File.mkdir_p!(tmp)

    try do
      {_, 0} = System.cmd("tar", ["xzf", tar_path, "-C", tmp])
      File.cp!(Path.expand("sonar.plugin.json", __DIR__), Path.join(tmp, "sonar.plugin.json"))

      entries =
        File.ls!(tmp)
        |> Enum.sort()

      {_, 0} = System.cmd("tar", ["czf", tar_path] ++ Enum.flat_map(entries, &["-C", tmp, &1]))
    after
      File.rm_rf!(tmp)
    end

    release
  end

  defp aliases do
    [
      setup: ["deps.get"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
