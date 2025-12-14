defmodule Lab4.MixProject do
  use Mix.Project

  def project do
    [
      app: :lab4,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: Lab4.CLI]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Lab4.Application, []}
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},

      # Erlang XML parser (expat-based), used from Elixir
      {:exml, git: "https://github.com/paulgray/exml.git"}
    ]
  end
end
