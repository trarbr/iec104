defmodule ControlRoom.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    args = [
      host: System.get_env("substation_host", "localhost") |> String.to_charlist(),
      port: System.get_env("substation_port", "2404") |> String.to_integer()
    ]

    children = [
      {ControlRoom, args}
    ]

    opts = [strategy: :one_for_one, name: ControlRoom.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
