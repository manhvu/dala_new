# SPDX-FileCopyrightText: 2024 Dala contributors <https://github.com/manhvu/dala/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule DalaNew.MixProject do
  use Mix.Project

  @version "0.3.2"

  @description """
  Project generator for the Dala mobile framework.
  """

  def project do
    [
      app: :dala_new,
      version: @version,
      elixir: "~> 1.18",
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
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:mimic, "~> 2.0", only: [:test]}
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/logo/Dala_logo_512.png",
      source_ref: "v#{@version}",
      source_url: "https://github.com/manhvu/dala_new",
      logo: nil,
      extra_section: "GUIDES",
      extras: [
        {"README.md", title: "Home"}
      ],
      groups_for_modules: [
        "Mix Tasks": [~r"Mix\.Tasks\..*"],
        "Project Generation": [~r"DalaNew\..*"],
        Utilities: [~r"DalaNew\.Util\..*"]
      ]
    ]
  end

  defp package do
    [
      maintainers: [
        "Manh Vu <manhvu@users.noreply.github.com>"
      ],
      licenses: ["MIT", "MPL-2.0"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*
       AGENTS.md priv),
      links: %{
        "GitHub" => "https://github.com/manhvu/dala_new",
        "HexDocs" => "https://hexdocs.pm/dala_new"
      }
    ]
  end

  defp aliases do
    [
      credo: "credo --strict"
    ]
  end
end
