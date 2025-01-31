defmodule Livebook.Hubs.TeamClient do
  use GenServer
  require Logger

  alias Livebook.Apps
  alias Livebook.FileSystem
  alias Livebook.FileSystems
  alias Livebook.Hubs
  alias Livebook.Secrets
  alias Livebook.Teams

  @registry Livebook.HubsRegistry
  @supervisor Livebook.HubsSupervisor

  defstruct [
    :connection_pid,
    :hub,
    :connection_status,
    :derived_key,
    :deployment_group_id,
    connected?: false,
    secrets: [],
    file_systems: [],
    deployment_groups: [],
    app_deployments: [],
    agents: [],
    app_deployment_statuses: nil
  ]

  @type registry_name :: {:via, Registry, {Livebook.HubsRegistry, String.t()}}

  @doc """
  Connects the Team client with WebSocket server.
  """
  @spec start_link(Hubs.Team.t()) :: GenServer.on_start()
  def start_link(%Hubs.Team{} = team) do
    GenServer.start_link(__MODULE__, team, name: registry_name(team.id))
  end

  @doc """
  Returns the client pid for the given hub id.
  """
  @spec get_pid(String.t()) :: pid() | nil
  def get_pid(id) do
    GenServer.whereis(registry_name(id))
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
  Returns a list of cached secrets.
  """
  @spec get_secrets(String.t()) :: list(Secrets.Secret.t())
  def get_secrets(id) do
    GenServer.call(registry_name(id), :get_secrets)
  end

  @doc """
  Returns a list of cached file systems.
  """
  @spec get_file_systems(String.t()) :: list(FileSystem.t())
  def get_file_systems(id) do
    GenServer.call(registry_name(id), :get_file_systems)
  end

  @doc """
  Returns the latest status from connection.
  """
  @spec get_connection_status(String.t()) :: String.t() | nil
  def get_connection_status(id) do
    GenServer.call(registry_name(id), :get_connection_status)
  catch
    :exit, _ -> "connection refused"
  end

  @doc """
  Returns a list of cached deployment groups.
  """
  @spec get_deployment_groups(String.t()) :: list(Teams.DeploymentGroup.t())
  def get_deployment_groups(id) do
    GenServer.call(registry_name(id), :get_deployment_groups)
  end

  @doc """
  Returns a list of cached app deployments.
  """
  @spec get_app_deployments(String.t()) :: list(Teams.AppDeployment.t())
  def get_app_deployments(id) do
    GenServer.call(registry_name(id), :get_app_deployments)
  end

  @doc """
  Returns a list of cached app deployments that should be deployed on
  this instance.
  """
  @spec get_agent_app_deployments(String.t()) :: list(Teams.AppDeployment.t())
  def get_agent_app_deployments(id) do
    GenServer.call(registry_name(id), :get_agent_app_deployments)
  end

  @doc """
  Returns information necessary to download and decrypt archive for
  app deployment with the given id.
  """
  @spec get_app_deployment_download_info(String.t(), String.t()) ::
          {:ok, Teams.AppDeployment.t(), derived_key :: binary()} | :error
  def get_app_deployment_download_info(id, app_deployment_id) do
    GenServer.call(registry_name(id), {:get_app_deployment_download_info, app_deployment_id})
  end

  @doc """
  Returns a list of cached agents.
  """
  @spec get_agents(String.t()) :: list(Teams.Agent.t())
  def get_agents(id) do
    GenServer.call(registry_name(id), :get_agents)
  end

  @doc """
  Returns if the Team client uses Livebook Teams identity provider.
  """
  @spec identity_enabled?(String.t()) :: boolean()
  def identity_enabled?(id) do
    GenServer.call(registry_name(id), :identity_enabled?)
  end

  @doc """
  Returns a list of cached environment variables.
  """
  @spec get_environment_variables(String.t()) :: list(Teams.Agent.t())
  def get_environment_variables(id) do
    GenServer.call(registry_name(id), :get_environment_variables)
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

  @doc """
  Enqueues the synchronous event to be handled by the Team client.
  """
  @spec handle_event(String.t(), {atom(), LivebookProto.event_proto()}) :: :ok
  def handle_event(id, {topic, data}) do
    GenServer.cast(registry_name(id), {:event, topic, data})
  end

  ## GenServer callbacks

  @impl true
  def init(%Hubs.Team{offline: nil} = team) do
    Apps.Manager.subscribe()

    derived_key = Teams.derive_key(team.teams_key)

    headers =
      if team.user_id do
        [
          {"x-lb-version", Livebook.Config.app_version()},
          {"x-user", to_string(team.user_id)},
          {"x-org", to_string(team.org_id)},
          {"x-org-key", to_string(team.org_key_id)},
          {"x-session-token", team.session_token}
        ]
      else
        [
          {"x-lb-version", Livebook.Config.app_version()},
          {"x-org", to_string(team.org_id)},
          {"x-org-key", to_string(team.org_key_id)},
          {"x-agent-name", Livebook.Config.agent_name()},
          {"x-agent-key", team.session_token}
        ]
      end

    {:ok, pid} = Teams.Connection.start_link(self(), headers)
    {:ok, %__MODULE__{connection_pid: pid, hub: team, derived_key: derived_key}}
  end

  def init(%Hubs.Team{} = team) do
    derived_key = Teams.derive_key(team.teams_key)

    {:ok,
     %__MODULE__{
       hub: team,
       secrets: team.offline.secrets,
       file_systems: team.offline.file_systems,
       derived_key: derived_key
     }}
  end

  @impl true
  def handle_call(:get_connection_status, _caller, state) do
    {:reply, state.connection_status, state}
  end

  def handle_call(:connected?, _caller, state) do
    {:reply, state.connected?, state}
  end

  def handle_call(:get_secrets, _caller, %{deployment_group_id: nil} = state) do
    {:reply, state.secrets, state}
  end

  def handle_call(:get_secrets, _caller, state) do
    case find_deployment_group(state.deployment_group_id, state.deployment_groups) do
      nil ->
        {:reply, state.secrets, state}

      %{secrets: agent_secrets} ->
        {:reply, Enum.uniq_by(agent_secrets ++ state.secrets, & &1.name), state}
    end
  end

  def handle_call(:get_file_systems, _caller, state) do
    {:reply, state.file_systems, state}
  end

  def handle_call(:get_deployment_groups, _caller, state) do
    {:reply, state.deployment_groups, state}
  end

  def handle_call(:get_app_deployments, _caller, state) do
    {:reply, state.app_deployments, state}
  end

  def handle_call(:get_agent_app_deployments, _caller, state) do
    if state.deployment_group_id do
      app_deployments =
        Enum.filter(state.app_deployments, &(&1.deployment_group_id == state.deployment_group_id))

      {:reply, app_deployments, state}
    else
      {:reply, [], state}
    end
  end

  def handle_call({:get_app_deployment_download_info, app_deployment_id}, _caller, state) do
    reply =
      if app_deployment = Enum.find(state.app_deployments, &(&1.id == app_deployment_id)) do
        {:ok, app_deployment, state.derived_key}
      else
        :error
      end

    {:reply, reply, state}
  end

  def handle_call(:get_agents, _caller, state) do
    {:reply, state.agents, state}
  end

  def handle_call(:get_environment_variables, _caller, state) do
    environment_variables = Enum.flat_map(state.deployment_groups, & &1.environment_variables)
    {:reply, environment_variables, state}
  end

  def handle_call(:identity_enabled?, _caller, %{deployment_group_id: nil} = state) do
    {:reply, false, state}
  end

  def handle_call(:identity_enabled?, _caller, %{deployment_group_id: id} = state) do
    case fetch_deployment_group(id, state) do
      {:ok, deployment_group} -> {:reply, deployment_group.teams_auth, state}
      _ -> {:reply, false, state}
    end
  end

  @impl true
  def handle_info(:connected, state) do
    Hubs.Broadcasts.hub_connected(state.hub.id)

    {:noreply, %{state | connected?: true, connection_status: nil}}
  end

  def handle_info({:connection_error, reason}, state) do
    Hubs.Broadcasts.hub_connection_failed(state.hub.id, reason)

    {:noreply, %{state | connected?: false, connection_status: reason}}
  end

  def handle_info({:server_error, reason}, state) do
    Hubs.Broadcasts.hub_server_error(state.hub.id, "#{state.hub.hub_name}: #{reason}")
    :ok = Hubs.delete_hub(state.hub.id)

    {:noreply, %{state | connected?: false}}
  end

  def handle_info({:event, topic, data}, state) do
    Logger.debug("Received event #{topic} with data: #{inspect(data)}")

    {:noreply, handle_event(topic, data, state)}
  end

  def handle_info({:apps_manager_status, _}, state)
      when not state.connected? or state.deployment_group_id == nil do
    {:noreply, state}
  end

  def handle_info({:apps_manager_status, entries}, %{hub: %{id: id}} = state) do
    app_deployment_statuses =
      for %{app_spec: %Apps.TeamsAppSpec{hub_id: ^id} = app_spec, running?: running?} <- entries do
        status = if running?, do: :available, else: :preparing

        %LivebookProto.AppDeploymentStatus{
          id: app_spec.app_deployment_id,
          deployment_group_id: state.deployment_group_id,
          version: app_spec.version,
          status: status
        }
      end

    # The manager can send the status list even if it didn't change,
    # or it changed for non-teams app spec, so we check to send the
    # event only when necessary
    if app_deployment_statuses == state.app_deployment_statuses do
      {:noreply, state}
    else
      report = %LivebookProto.AppDeploymentStatusReport{
        app_deployment_statuses: app_deployment_statuses
      }

      Logger.debug("Sending apps manager report to Teams server #{inspect(report)}")

      message = LivebookProto.AppDeploymentStatusReport.encode(report)
      :ok = Teams.Connection.send_message(state.connection_pid, message)

      {:noreply, %{state | app_deployment_statuses: app_deployment_statuses}}
    end
  end

  @impl true
  def handle_cast({:event, topic, data}, state) do
    Logger.debug("Received event #{topic} with data: #{inspect(data)}")

    {:noreply, handle_event(topic, data, state)}
  end

  # Private

  defp registry_name(id) do
    {:via, Registry, {@registry, id}}
  end

  defp put_secret(state, secret) do
    state = remove_secret(state, secret)

    %{state | secrets: [secret | state.secrets]}
  end

  defp remove_secret(state, secret) do
    %{state | secrets: Enum.reject(state.secrets, &(&1.name == secret.name))}
  end

  defp build_secret(state, %{name: name, value: value} = attrs) do
    {:ok, decrypted_value} = Teams.decrypt(value, state.derived_key)

    %Secrets.Secret{
      name: name,
      value: decrypted_value,
      hub_id: state.hub.id,
      deployment_group_id: Map.get(attrs, :deployment_group_id)
    }
  end

  defp put_file_system(state, file_system) do
    state = remove_file_system(state, file_system)

    %{state | file_systems: [file_system | state.file_systems]}
  end

  defp remove_file_system(state, file_system) do
    %{
      state
      | file_systems:
          Enum.reject(state.file_systems, &(&1.external_id == file_system.external_id))
    }
  end

  defp build_file_system(state, file_system) do
    {:ok, decrypted_value} = Teams.decrypt(file_system.value, state.derived_key)

    dumped_data =
      decrypted_value
      |> JSON.decode!()
      |> Map.put("external_id", file_system.id)

    FileSystems.load(file_system.type, dumped_data)
  end

  defp put_deployment_group(state, deployment_group) do
    state = remove_deployment_group(state, deployment_group)
    %{state | deployment_groups: [deployment_group | state.deployment_groups]}
  end

  defp remove_deployment_group(state, deployment_group) do
    %{
      state
      | deployment_groups: Enum.reject(state.deployment_groups, &(&1.id == deployment_group.id))
    }
  end

  defp put_app_deployment(state, app_deployment) do
    state = remove_app_deployment(state, app_deployment)
    app_deployments = [app_deployment | state.app_deployments]

    %{state | app_deployments: Enum.sort_by(app_deployments, & &1.slug)}
  end

  defp remove_app_deployment(state, app_deployment) do
    %{
      state
      | app_deployments: Enum.reject(state.app_deployments, &(&1.id == app_deployment.id))
    }
  end

  defp build_agent_key(agent_key) do
    %Teams.AgentKey{
      id: agent_key.id,
      key: agent_key.key,
      deployment_group_id: agent_key.deployment_group_id
    }
  end

  defp build_deployment_group(state, %LivebookProto.DeploymentGroup{} = deployment_group) do
    secrets = Enum.map(deployment_group.secrets, &build_secret(state, &1))
    agent_keys = Enum.map(deployment_group.agent_keys, &build_agent_key/1)
    environment_variables = build_environment_variables(state, deployment_group)

    %Teams.DeploymentGroup{
      id: deployment_group.id,
      name: deployment_group.name,
      mode: atomize(deployment_group.mode),
      hub_id: state.hub.id,
      secrets: secrets,
      agent_keys: agent_keys,
      environment_variables: environment_variables,
      clustering: nullify(deployment_group.clustering),
      url: nullify(deployment_group.url),
      teams_auth: deployment_group.teams_auth
    }
  end

  defp build_deployment_group(state, %{mode: _} = deployment_group_created) do
    agent_keys = Enum.map(deployment_group_created.agent_keys, &build_agent_key/1)

    %Teams.DeploymentGroup{
      id: deployment_group_created.id,
      name: deployment_group_created.name,
      mode: atomize(deployment_group_created.mode),
      hub_id: state.hub.id,
      secrets: [],
      agent_keys: agent_keys,
      environment_variables: [],
      clustering: nullify(deployment_group_created.clustering),
      url: nullify(deployment_group_created.url),
      teams_auth: deployment_group_created.teams_auth
    }
  end

  defp build_deployment_group(state, deployment_group_updated) do
    secrets = Enum.map(deployment_group_updated.secrets, &build_secret(state, &1))
    agent_keys = Enum.map(deployment_group_updated.agent_keys, &build_agent_key/1)
    environment_variables = build_environment_variables(state, deployment_group_updated)

    {:ok, deployment_group} = fetch_deployment_group(deployment_group_updated.id, state)

    %{
      deployment_group
      | name: deployment_group_updated.name,
        secrets: secrets,
        agent_keys: agent_keys,
        environment_variables: environment_variables,
        clustering: atomize(deployment_group_updated.clustering),
        url: nullify(deployment_group_updated.url),
        teams_auth: deployment_group_updated.teams_auth
    }
  end

  defp build_app_deployment(state, %LivebookProto.AppDeployment{} = app_deployment) do
    %Teams.AppDeployment{
      id: app_deployment.id,
      slug: app_deployment.slug,
      version: app_deployment.version,
      sha: app_deployment.sha,
      title: app_deployment.title,
      multi_session: app_deployment.multi_session,
      access_type: String.to_atom(app_deployment.access_type),
      hub_id: state.hub.id,
      deployment_group_id: app_deployment.deployment_group_id,
      file: nil,
      deployed_by: app_deployment.deployed_by,
      deployed_at: DateTime.from_gregorian_seconds(app_deployment.deployed_at)
    }
  end

  defp build_environment_variables(state, deployment_group_updated) do
    for environment_variable <- deployment_group_updated.environment_variables do
      %Teams.EnvironmentVariable{
        name: environment_variable.name,
        value: environment_variable.value,
        hub_id: state.hub.id,
        deployment_group_id: deployment_group_updated.id
      }
    end
  end

  defp put_agent(state, agent) do
    state = remove_agent(state, agent)

    %{state | agents: [agent | state.agents]}
  end

  defp remove_agent(state, agent) do
    %{state | agents: Enum.reject(state.agents, &(&1.id == agent.id))}
  end

  defp build_agent(state, %LivebookProto.Agent{} = agent) do
    %Livebook.Teams.Agent{
      id: agent.id,
      name: agent.name,
      hub_id: state.hub.id,
      org_id: agent.org_id,
      deployment_group_id: agent.deployment_group_id
    }
  end

  defp handle_event(:secret_created, %Secrets.Secret{} = secret, state) do
    Hubs.Broadcasts.secret_created(secret)

    put_secret(state, secret)
  end

  defp handle_event(:secret_created, secret_created, state) do
    handle_event(:secret_created, build_secret(state, secret_created), state)
  end

  defp handle_event(:secret_updated, %Secrets.Secret{} = secret, state) do
    Hubs.Broadcasts.secret_updated(secret)

    put_secret(state, secret)
  end

  defp handle_event(:secret_updated, secret_updated, state) do
    handle_event(:secret_updated, build_secret(state, secret_updated), state)
  end

  defp handle_event(:secret_deleted, %Secrets.Secret{} = secret, state) do
    Hubs.Broadcasts.secret_deleted(secret)
    remove_secret(state, secret)
  end

  defp handle_event(:secret_deleted, %{name: name}, state) do
    with {:ok, secret} <- fetch_secret(name, state) do
      handle_event(:secret_deleted, secret, state)
    end
  end

  defp handle_event(:file_system_created, %{external_id: _} = file_system, state) do
    Hubs.Broadcasts.file_system_created(file_system)

    put_file_system(state, file_system)
  end

  defp handle_event(:file_system_created, file_system_created, state) do
    handle_event(:file_system_created, build_file_system(state, file_system_created), state)
  end

  defp handle_event(:file_system_updated, %{external_id: _} = file_system, state) do
    Hubs.Broadcasts.file_system_updated(file_system)

    put_file_system(state, file_system)
  end

  defp handle_event(:file_system_updated, file_system_updated, state) do
    handle_event(:file_system_updated, build_file_system(state, file_system_updated), state)
  end

  defp handle_event(:file_system_deleted, %{external_id: _} = file_system, state) do
    Hubs.Broadcasts.file_system_deleted(file_system)
    remove_file_system(state, file_system)
  end

  defp handle_event(:file_system_deleted, %{id: external_id}, state) do
    with {:ok, file_system} <- fetch_file_system(external_id, state) do
      handle_event(:file_system_deleted, file_system, state)
    end
  end

  defp handle_event(:deployment_group_created, %Teams.DeploymentGroup{} = deployment_group, state) do
    Teams.Broadcasts.deployment_group_created(deployment_group)

    put_deployment_group(state, deployment_group)
  end

  defp handle_event(:deployment_group_created, deployment_group_created, state) do
    handle_event(
      :deployment_group_created,
      build_deployment_group(state, deployment_group_created),
      state
    )
  end

  defp handle_event(:deployment_group_updated, %Teams.DeploymentGroup{} = deployment_group, state) do
    Teams.Broadcasts.deployment_group_updated(deployment_group)
    put_deployment_group(state, deployment_group)
  end

  defp handle_event(:deployment_group_updated, deployment_group_updated, state) do
    handle_event(
      :deployment_group_updated,
      build_deployment_group(state, deployment_group_updated),
      state
    )
  end

  defp handle_event(:deployment_group_deleted, %Teams.DeploymentGroup{} = deployment_group, state) do
    Teams.Broadcasts.deployment_group_deleted(deployment_group)
    remove_deployment_group(state, deployment_group)
  end

  defp handle_event(:deployment_group_deleted, %{id: id}, state) do
    with {:ok, deployment_group} <- fetch_deployment_group(id, state) do
      handle_event(:deployment_group_deleted, deployment_group, state)
    end
  end

  defp handle_event(:user_connected, user_connected, state) do
    state
    |> update_hub(user_connected)
    |> dispatch_secrets(user_connected)
    |> dispatch_file_systems(user_connected)
    |> dispatch_deployment_groups(user_connected)
    |> dispatch_app_deployments(user_connected)
    |> dispatch_agents(user_connected)
    |> dispatch_connection()
  end

  defp handle_event(:agent_connected, agent_connected, state) do
    %{state | deployment_group_id: to_string(agent_connected.deployment_group_id)}
    |> update_hub(agent_connected)
    |> dispatch_secrets(agent_connected)
    |> dispatch_file_systems(agent_connected)
    |> dispatch_deployment_groups(agent_connected)
    |> dispatch_app_deployments(agent_connected)
    |> dispatch_agents(agent_connected)
    |> dispatch_connection()
  end

  defp handle_event(:app_deployment_started, %Teams.AppDeployment{} = app_deployment, state) do
    deployment_group_id = app_deployment.deployment_group_id

    with {:ok, deployment_group} <- fetch_deployment_group(deployment_group_id, state) do
      if deployment_group.id == state.deployment_group_id do
        manager_sync()
      end
    end

    Teams.Broadcasts.app_deployment_started(app_deployment)
    put_app_deployment(state, app_deployment)
  end

  defp handle_event(:app_deployment_started, app_deployment_started, state) do
    handle_event(
      :app_deployment_started,
      build_app_deployment(state, app_deployment_started.app_deployment),
      state
    )
  end

  defp handle_event(:app_deployment_stopped, %Teams.AppDeployment{} = app_deployment, state) do
    deployment_group_id = app_deployment.deployment_group_id

    with {:ok, deployment_group} <- fetch_deployment_group(deployment_group_id, state) do
      if deployment_group.id == state.deployment_group_id do
        manager_sync()
      end
    end

    Teams.Broadcasts.app_deployment_stopped(app_deployment)
    remove_app_deployment(state, app_deployment)
  end

  defp handle_event(:app_deployment_stopped, %{id: id}, state) do
    with {:ok, app_deployment} <- fetch_app_deployment(id, state) do
      handle_event(:app_deployment_stopped, app_deployment, state)
    end
  end

  defp handle_event(:agent_joined, %Teams.Agent{} = agent, state) do
    Teams.Broadcasts.agent_joined(agent)
    put_agent(state, agent)
  end

  defp handle_event(:agent_joined, agent_joined, state) do
    handle_event(:agent_joined, build_agent(state, agent_joined.agent), state)
  end

  defp handle_event(:agent_left, %Teams.Agent{} = agent, state) do
    Teams.Broadcasts.agent_left(agent)
    remove_agent(state, agent)
  end

  defp handle_event(:agent_left, %{id: id}, state) do
    with {:ok, agent} <- fetch_agent(id, state) do
      handle_event(:agent_left, agent, state)
    end
  end

  defp handle_event(:user_deleted, %{id: id}, state) do
    if id == to_string(state.hub.user_id) do
      send(self(), {:server_error, "you were removed from the org"})
    end

    state
  end

  defp handle_event(:org_updated, org_updated, state) do
    update_hub(state, org_updated)
  end

  defp dispatch_secrets(state, %{secrets: secrets}) do
    decrypted_secrets = Enum.map(secrets, &build_secret(state, &1))

    {created, deleted, updated} =
      diff(
        state.secrets,
        decrypted_secrets,
        &(&1.name == &2.name and &1.value == &2.value),
        &(&1.name == &2.name),
        &(&1.name == &2.name and &1.value != &2.value)
      )

    dispatch_events(state,
      secret_deleted: deleted,
      secret_created: created,
      secret_updated: updated
    )
  end

  defp dispatch_file_systems(state, %{file_systems: file_systems}) do
    decrypted_file_systems = Enum.map(file_systems, &build_file_system(state, &1))

    {created, deleted, updated} =
      diff(
        state.file_systems,
        decrypted_file_systems,
        &(&1.external_id == &2.external_id)
      )

    dispatch_events(state,
      file_system_deleted: deleted,
      file_system_created: created,
      file_system_updated: updated
    )
  end

  defp dispatch_deployment_groups(state, %{deployment_groups: deployment_groups}) do
    deployment_groups = Enum.map(deployment_groups, &build_deployment_group(state, &1))

    {created, deleted, updated} =
      diff(state.deployment_groups, deployment_groups, &(&1.id == &2.id))

    dispatch_events(state,
      deployment_group_deleted: deleted,
      deployment_group_created: created,
      deployment_group_updated: updated
    )
  end

  defp dispatch_app_deployments(state, %{app_deployments: app_deployments}) do
    app_deployments = Enum.map(app_deployments, &build_app_deployment(state, &1))
    {started, stopped, _} = diff(state.app_deployments, app_deployments, &(&1.id == &2.id))

    dispatch_events(state, app_deployment_started: started, app_deployment_stopped: stopped)
  end

  defp dispatch_agents(state, %{agents: agents}) do
    agents = Enum.map(agents, &build_agent(state, &1))
    {joined, left, _} = diff(state.agents, agents, &(&1.id == &2.id))

    dispatch_events(state, agent_joined: joined, agent_left: left)
  end

  defp dispatch_connection(%{hub: %{id: id}} = state) do
    Teams.Broadcasts.client_connected(id)
    state
  end

  defp update_hub(state, %LivebookProto.UserConnected{statuses: statuses}) do
    update_hub(state, &put_statuses(&1, statuses))
  end

  defp update_hub(state, %LivebookProto.AgentConnected{
         public_key: org_public_key,
         statuses: statuses
       }) do
    update_hub(state, &put_statuses(put_in(&1.org_public_key, org_public_key), statuses))
  end

  defp update_hub(state, %LivebookProto.OrgUpdated{statuses: statuses}) do
    update_hub(state, &put_statuses(&1, statuses))
  end

  defp update_hub(state, fun) when is_function(fun, 1) do
    hub = fun.(state.hub)

    if Hubs.hub_exists?(hub.id) do
      Hubs.save_hub(hub)
    end

    put_in(state.hub, hub)
  end

  # if there are no statuses, it means the org is active.
  defp put_statuses(hub, []) do
    %{hub | trial_ends_at: nil, cancel_at: nil}
  end

  defp put_statuses(hub, statuses) do
    Enum.reduce_while(statuses, hub, fn %LivebookProto.OrgStatus{type: type}, hub ->
      case type do
        {:trial, %LivebookProto.OrgStatusTrial{trial_ends_at: seconds}} ->
          {:halt, %{hub | trial_ends_at: DateTime.from_unix!(seconds), cancel_at: nil}}

        {:cancel, %LivebookProto.OrgStatusCancel{cancel_at: seconds}} ->
          {:halt, %{hub | trial_ends_at: nil, cancel_at: DateTime.from_unix!(seconds)}}

        _other ->
          {:cont, %{hub | trial_ends_at: nil, cancel_at: nil}}
      end
    end)
  end

  defp diff(old_list, new_list, fun, deleted_fun \\ nil, updated_fun \\ nil) do
    deleted_fun = unless deleted_fun, do: fun, else: deleted_fun
    updated_fun = unless updated_fun, do: fun, else: updated_fun

    created = Enum.reject(new_list, fn item -> Enum.find(old_list, &fun.(&1, item)) end)
    deleted = Enum.reject(old_list, fn item -> Enum.find(new_list, &deleted_fun.(&1, item)) end)
    updated = Enum.filter(new_list, fn item -> Enum.find(old_list, &updated_fun.(&1, item)) end)

    {created, deleted, updated}
  end

  defp dispatch_events(state, events_by_topic) do
    for {topic, events} <- events_by_topic,
        event <- events,
        reduce: state,
        do: (acc -> handle_event(topic, event, acc))
  end

  defp find_deployment_group(nil, _), do: nil
  defp find_deployment_group(id, groups), do: Enum.find(groups, &(&1.id == id))

  defp fetch_deployment_group(id, state),
    do: fetch_entry(state.deployment_groups, &(&1.id == id), state)

  defp fetch_secret(name, state), do: fetch_entry(state.secrets, &(&1.name == name), state)

  defp fetch_file_system(external_id, state),
    do: fetch_entry(state.file_systems, &(&1.external_id == external_id), state)

  defp fetch_agent(id, state), do: fetch_entry(state.agents, &(&1.id == id), state)

  defp fetch_app_deployment(id, state),
    do: fetch_entry(state.app_deployments, &(&1.id == id), state)

  defp fetch_entry(entries, fun, state) do
    if entry = Enum.find(entries, fun) do
      {:ok, entry}
    else
      state
    end
  end

  # We cannot use to_existing_atom because the atoms
  # may not have been loaded. Luckily, we can trust
  # on Livebook Teams as a source.
  defp atomize(value) when value in [nil, ""], do: nil
  defp atomize(value), do: String.to_atom(value)

  defp nullify(""), do: nil
  defp nullify(value), do: value

  defp manager_sync() do
    # Each node runs the teams client, but we only need to call sync once
    if Apps.Manager.local?() do
      Apps.Manager.sync_permanent_apps()
    end
  end
end
