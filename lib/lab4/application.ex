defmodule Lab4.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Lab4.PeerRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Lab4.RuntimeSupervisor},
      {Lab4.Router, []}
    ]

    opts = [strategy: :one_for_one, name: Lab4.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
