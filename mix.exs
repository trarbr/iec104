defmodule IEC104.MixProject do
  use Mix.Project

  def project do
    [
      app: :iec104,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:nimble_options, "~> 0.3.0"},
      {:ex_doc, "~> 0.22", only: :dev, runtime: false}
    ]
  end
end
