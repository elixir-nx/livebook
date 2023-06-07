defmodule Livebook.Hubs.TeamClient do
  @moduledoc false
  use GenServer
  require Logger

  alias Livebook.Hubs.Broadcasts
  alias Livebook.Hubs.Team
  alias Livebook.Teams.Connection

  @registry Livebook.HubsRegistry
  @supervisor Livebook.HubsSupervisor

  defstruct [:hub, :connection_error, connected?: false, secrets: []]

  @type registry_name :: {:via, Registry, {Livebook.HubsRegistry, String.t()}}

  @doc """
  Connects the Team client with WebSocket server.
  """
  @spec start_link(Team.t()) :: GenServer.on_start()
  def start_link(%Team{} = team) do
    GenServer.start_link(__MODULE__, team, name: registry_name(team.id))
  end

  @doc """
  Stops the WebSocket server.
  """
  @spec stop(String.t()) :: :ok
  def stop(id) do
    if pid = GenServer.whereis(registry_name(id)) do
      DynamicSupervisor.terminate_child(@supervisor, pid)
    end

    :ok
  end

  @doc """
  Returns the latest error from connection.
  """
  @spec get_connection_error(String.t()) :: String.t() | nil
  def get_connection_error(id) do
    GenServer.call(registry_name(id), :get_connection_error)
  catch
    :exit, _ -> "connection refused"
  end

  @doc """
  Returns if the Team client is connected.
  """
  @spec connected?(String.t()) :: boolean()
  def connected?(id) do
    GenServer.call(registry_name(id), :connected?)
  catch
    :exit, _ -> false
  end

  ## GenServer callbacks

  @impl true
  def init(%Team{} = team) do
    headers = [
      {"x-user", to_string(team.user_id)},
      {"x-org", to_string(team.org_id)},
      {"x-org-key", to_string(team.org_key_id)},
      {"x-session-token", team.session_token}
    ]

    {:ok, _pid} = Connection.start_link(self(), headers)
    {:ok, %__MODULE__{hub: team}}
  end

  @impl true
  def handle_call(:get_connection_error, _caller, state) do
    {:reply, state.connection_error, state}
  end

  def handle_call(:connected?, _caller, state) do
    {:reply, state.connected?, state}
  end

  @impl true
  def handle_info(:connected, state) do
    Broadcasts.hub_connected(state.hub.id)
    {:noreply, %{state | connected?: true, connection_error: nil}}
  end

  def handle_info({:connection_error, reason}, state) do
    Broadcasts.hub_connection_failed(state.hub.id, reason)
    {:noreply, %{state | connected?: false, connection_error: reason}}
  end

  def handle_info({:server_error, reason}, state) do
    Broadcasts.hub_server_error(state.hub.id, "#{state.hub.hub_name}: #{reason}")
    :ok = Livebook.Hubs.delete_hub(state.hub.id)

    {:noreply, %{state | connected?: false}}
  end

  # Private

  defp registry_name(id) do
    {:via, Registry, {@registry, id}}
  end
end
