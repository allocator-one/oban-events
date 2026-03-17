defmodule ObanEvents.MixProject do
  use Mix.Project

  @version "1.0.3"
  @source_url "https://github.com/allocator-one/oban-events"

  def project do
    [
      app: :oban_events,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],

      # Hex
      description: description(),
      package: package(),

      # Docs
      name: "ObanEvents",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:oban, "~> 2.0"},
      {:uuidv7, "~> 0.2 or ~> 1.0"},
      # Postgrex needed for Oban in test environment
      {:postgrex, ">= 0.0.0", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  defp description do
    "Event handling with persistent, transactional async handlers via Oban"
  end

  defp package do
    [
      maintainers: ["Goran Pedić"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Infra One" => "https://infra.one/"
      },
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end
end
