defmodule Livebook.Hubs.EnterpriseClient do
  @moduledoc false
  use GenServer

  alias Livebook.Hubs.Broadcasts
  alias Livebook.Hubs.Enterprise
  alias Livebook.Secrets.Secret
  alias Livebook.WebSocket.ClientConnection

  @registry Livebook.HubsRegistry
  @supervisor Livebook.HubsSupervisor

  defstruct [:server, :hub, :connection_error, connected?: false, secrets: []]

  @type registry_name :: {:via, Registry, {Livebook.HubsRegistry, String.t()}}

  @doc """
  Connects the Enterprise client with WebSocket server.
  """
  @spec start_link(Enterprise.t()) :: GenServer.on_start()
  def start_link(%Enterprise{} = enterprise) do
    GenServer.start_link(__MODULE__, enterprise, name: registry_name(enterprise.id))
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
  Sends a request to the WebSocket server.
  """
  @spec send_request(String.t() | registry_name() | pid(), WebSocket.proto()) :: {atom(), term()}
  def send_request(id, %_struct{} = data) when is_binary(id) do
    send_request(registry_name(id), data)
  end

  def send_request(pid, %_struct{} = data) do
    with {:ok, server} <- GenServer.call(pid, :fetch_server) do
      ClientConnection.send_request(server, data)
    end
  end

  @doc """
  Returns a list of cached secrets.
  """
  @spec get_secrets(String.t()) :: list(Secret.t())
  def get_secrets(id) do
    GenServer.call(registry_name(id), :get_secrets)
  end

  @doc """
  Returns the latest error from connection.
  """
  @spec get_connection_error(String.t()) :: Secret.t() | nil
  def get_connection_error(id) do
    GenServer.call(registry_name(id), :get_connection_error)
  end

  @doc """
  Returns if the given enterprise is connected.
  """
  @spec connected?(String.t()) :: boolean()
  def connected?(id) do
    GenServer.call(registry_name(id), :connected?)
  catch
    :exit, _ -> false
  end

  ## GenServer callbacks

  @impl true
  def init(%Enterprise{url: url, token: token} = enterprise) do
    headers = [{"X-Auth-Token", token}]
    {:ok, pid} = ClientConnection.start_link(self(), url, headers)

    {:ok, %__MODULE__{hub: enterprise, server: pid}}
  end

  @impl true
  def handle_call(:fetch_server, _caller, state) do
    if state.connected? do
      {:reply, {:ok, state.server}, state}
    else
      {:reply, {:transport_error, state.connection_error}, state}
    end
  end

  def handle_call(:get_secrets, _caller, state) do
    {:reply, state.secrets, state}
  end

  def handle_call(:get_connection_error, _caller, state) do
    {:reply, state.connection_error, state}
  end

  def handle_call(:connected?, _caller, state) do
    {:reply, state.connected?, state}
  end

  @impl true
  def handle_info({:connect, :ok, _}, state) do
    Broadcasts.hub_connected()
    {:noreply, %{state | connected?: true, connection_error: nil}}
  end

  def handle_info({:connect, :error, reason}, state) do
    Broadcasts.hub_connection_failed(reason)
    {:noreply, %{state | connected?: false, connection_error: reason}}
  end

  def handle_info({:event, :secret_created, %{name: name, value: value}}, state) do
    secret = %Secret{name: name, value: value, origin: {:hub, state.hub.id}}
    Broadcasts.secret_created(secret)

    {:noreply, put_secret(state, secret)}
  end

  def handle_info({:event, :secret_updated, %{name: name, value: value}}, state) do
    secret = %Secret{name: name, value: value, origin: {:hub, state.hub.id}}
    Broadcasts.secret_updated(secret)

    {:noreply, put_secret(state, secret)}
  end

  def handle_info({:disconnect, :ok, :disconnected}, state) do
    Broadcasts.hub_disconnected()
    {:stop, :normal, state}
  end

  # Private

  defp registry_name(id) do
    {:via, Registry, {@registry, id}}
  end

  defp put_secret(state, secret) do
    %{state | secrets: [secret | Enum.reject(state.secrets, &(&1.name == secret.name))]}
  end
end
