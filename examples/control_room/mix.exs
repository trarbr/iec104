defmodule ControlRoom.MixProject do
  use Mix.Project

  def project do
    [
      app: :control_room,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ControlRoom.Application, []}
    ]
  end

  defp deps do
    [
      {:iec104, path: "../../"}
    ]
  end
end
