# SPDX-FileCopyrightText: 2024 Mob contributors <https://github.com/manhvu/mob/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule MobNew.MixProject do
  use Mix.Project

  @version "0.1.30"

  @description """
  Project generator for the Mob mobile framework. Installs a global
  `mix mob.new` command to generate native SwiftUI/Compose apps or
  LiveView-wrapped mobile projects.
  """

  def project do
    [
      app: :mob_new,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      description: @description,
      aliases: aliases(),
      package: package(),
      docs: docs(),
      deps: deps(),
      dialyzer: [
        plt_add_apps: [:mix, :hex, :ex_unit]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :eex]
    ]
  end

  defp elixirc_paths(:test) do
    elixirc_paths(:dev) ++ ["test/support"]
  end

  defp elixirc_paths(_env) do
    ["lib"]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      # Dev/Test dependencies
      {:ex_doc, "~> 0.32", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:mimic, "~> 2.0", only: [:test]}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: "https://github.com/manhvu/mob",
      logo: nil,
      extra_section: "GUIDES",
      extras: [
        {"README.md", title: "Home"},
        "CHANGELOG.md"
      ],
      groups_for_modules: [
        "Mix Tasks": [~r"Mix\.Tasks\..*"],
        "Project Generation": [~r"MobNew\..*"],
        Utilities: [~r"MobNew\.Util\..*"]
      ]
    ]
  end

  defp package do
    [
      maintainers: [
        "Manh Vu <manhvu@users.noreply.github.com>"
      ],
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*
      CHANGELOG* AGENTS.md priv),
      links: %{
        "GitHub" => "https://github.com/manhvu/mob",
        "Changelog" => "https://github.com/manhvu/mob/blob/main/mob_new/CHANGELOG.md",
        "HexDocs" => "https://hexdocs.pm/mob",
        "Discord" => "https://discord.gg/mob",
        "Website" => "https://mobframework.com"
      }
    ]
  end

  defp aliases do
    [
      credo: "credo --strict"
    ]
  end
end
