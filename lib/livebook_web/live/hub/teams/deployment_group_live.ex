defmodule LivebookWeb.Hub.Teams.DeploymentGroupLive do
  use LivebookWeb, :live_view

  alias LivebookWeb.LayoutComponents
  alias LivebookWeb.TeamsComponents
  alias Livebook.Hubs
  alias Livebook.Teams
  alias Livebook.Hubs.Provider
  alias LivebookWeb.NotFoundError

  on_mount LivebookWeb.SidebarHook

  @impl true
  def handle_params(%{"id" => id} = params, _url, socket) do
    hub = Hubs.fetch_hub!(id)
    deployment_group_id = params["deployment_group_id"]
    secret_name = params["secret_name"]
    deployment_groups = Teams.get_deployment_groups(hub)
    default? = default_hub?(hub)

    deployment_group =
      if socket.assigns.live_action != :new_deployment_group do
        Enum.find_value(deployment_groups, &(&1.id == deployment_group_id && &1)) ||
          raise(
            NotFoundError,
            "could not find deployment group matching #{inspect(deployment_group_id)}"
          )
      end

    secrets =
      if socket.assigns.live_action != :new_deployment_group,
        do: deployment_group.secrets,
        else: []

    agent_keys =
      if socket.assigns.live_action != :new_deployment_group,
        do: deployment_group.agent_keys,
        else: []

    secret_value =
      if socket.assigns.live_action == :edit_secret do
        Enum.find_value(secrets, &(&1.name == secret_name and &1.value)) ||
          raise(NotFoundError, "could not find secret matching #{inspect(secret_name)}")
      end

    {:noreply,
     socket
     |> assign(
       hub: hub,
       deployment_groups: deployment_groups,
       deployment_group_id: deployment_group_id,
       deployment_group: deployment_group,
       hub_metadata: Provider.to_metadata(hub),
       secret_name: secret_name,
       secret_value: secret_value,
       default?: default?,
       secrets: secrets,
       agent_keys: agent_keys
     )
     |> assign_new(:config_changeset, fn ->
       Hubs.Dockerfile.config_changeset(Hubs.Dockerfile.config_new())
     end)
     |> update_dockerfile(:airgapped)
     |> update_dockerfile(:agent)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.layout
      current_page={~p"/hub/#{@hub.id}"}
      current_user={@current_user}
      saved_hubs={@saved_hubs}
    >
      <div>
        <LayoutComponents.topbar :if={Provider.connection_status(@hub)} variant={:warning}>
          <%= Provider.connection_status(@hub) %>
        </LayoutComponents.topbar>

        <div class="p-4 md:px-12 md:py-7 max-w-screen-md mx-auto">
          <div id={"#{@hub.id}-component"}>
            <div class="mb-8 flex flex-col space-y-10">
              <div class="flex flex-col space-y-2">
                <TeamsComponents.header hub={@hub} hub_metadata={@hub_metadata} default?={@default?} />
                <p class="text-sm flex flex-row space-x-6 text-gray-700">
                  <.link patch={~p"/hub/#{@hub.id}"} class="hover:text-blue-600 cursor-pointer">
                    <.remix_icon icon="arrow-left-line" /> Back to Hub
                  </.link>
                </p>
              </div>

              <div class="flex flex-col space-y-4">
                <.live_component
                  module={LivebookWeb.Hub.Teams.DeploymentGroupFormComponent}
                  id="deployment-groups"
                  hub={@hub}
                  deployment_group_id={@deployment_group_id}
                  deployment_group={@deployment_group}
                  return_to={~p"/hub/#{@hub.id}"}
                />
              </div>

              <%= if @deployment_group_id do %>
                <div class="flex flex-col space-y-4">
                  <h2 class="text-xl text-gray-800 font-medium pb-2 border-b border-gray-200">
                    Secrets
                  </h2>

                  <p class="text-gray-700">
                    Deployment group secrets overrides Hub secrets
                  </p>

                  <.live_component
                    module={LivebookWeb.Hub.SecretListComponent}
                    id="deployment-group-secrets-list"
                    hub={@hub}
                    secrets={@secrets}
                    deployment_group={@deployment_group}
                    add_path={
                      ~p"/hub/#{@hub.id}/deployment-groups/edit/#{@deployment_group.id}/secrets/new"
                    }
                    edit_path={"hub/#{@hub.id}/deployment-groups/edit/#{@deployment_group.id}/secrets/edit"}
                    return_to={~p"/hub/#{@hub.id}/deployment-groups/edit/#{@deployment_group.id}"}
                  />
                </div>

                <div :if={@deployment_group.mode == :online} class="flex flex-col space-y-4">
                  <h2 class="text-xl text-gray-800 font-medium pb-2 border-b border-gray-200">
                    Agent Keys
                  </h2>

                  <p class="text-gray-700">
                    Deployment group agent keys for online deployments
                  </p>

                  <.live_component
                    module={LivebookWeb.Hub.Teams.AgentKeyListComponent}
                    id="agent-keys-list"
                    hub={@hub}
                    agent_keys={@agent_keys}
                    deployment_group={@deployment_group}
                  />

                  <div class="flex">
                    <.button id="add-agent-key" type="button" phx-click="add_agent_key">
                      <span>Add agent key</span>
                    </.button>
                  </div>

                  <h2 class="text-xl text-gray-800 font-medium pb-2 border-b border-gray-200">
                    Agent deployment
                  </h2>

                  <p class="text-gray-700">
                    You can deploy your team notebooks directly to a self-hosted agent instance.
                    To do that, create an agent in the section above, then start an agent instance
                    using the Dockerfile below. Once the agent connects to the Livebook Teams server
                    and it will become available for app deployments.
                  </p>

                  <div class="flex flex-col gap-4">
                    <div>
                      <div class="flex items-end mb-1 gap-1">
                        <span class="text-sm text-gray-700 font-semibold">Dockerfile</span>
                        <div class="grow" />
                        <.button
                          color="gray"
                          small
                          data-tooltip="Copied to clipboard"
                          type="button"
                          aria-label="copy to clipboard"
                          phx-click={
                            JS.dispatch("lb:clipcopy", to: "#agent-dockerfile-source")
                            |> JS.add_class("", transition: {"tooltip top", "", ""}, time: 2000)
                          }
                        >
                          <.remix_icon icon="clipboard-line" />
                          <span>Copy source</span>
                        </.button>
                      </div>

                      <.code_preview
                        source_id="agent-dockerfile-source"
                        source={@agent_dockerfile}
                        language="dockerfile"
                      />
                    </div>
                  </div>
                </div>

                <div class="flex flex-col space-y-4">
                  <h2 class="text-xl text-gray-800 font-medium pb-2 border-b border-gray-200">
                    Airgapped deployment
                  </h2>

                  <p class="text-gray-700">
                    It is possible to deploy notebooks that belong to this Hub in an airgapped
                    deployment, without connecting back to Livebook Teams server. Configure the
                    deployment below and use the generated Dockerfile in a directory with notebooks
                    that belong to your Organization.
                  </p>

                  <.form :let={f} for={@config_changeset} as={:data} phx-change="validate_dockerfile">
                    <LivebookWeb.AppComponents.docker_config_form_content
                      hub={@hub}
                      form={f}
                      show_deploy_all={false}
                    />
                  </.form>

                  <LivebookWeb.AppComponents.docker_instructions
                    hub={@hub}
                    dockerfile={@dockerfile}
                    dockerfile_config={Ecto.Changeset.apply_changes(@config_changeset)}
                  />
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
      <.modal
        :if={@live_action in [:new_secret, :edit_secret]}
        id="secrets-modal"
        show
        width={:medium}
        patch={~p"/hub/#{@hub.id}/deployment-groups/edit/#{@deployment_group.id}"}
      >
        <.live_component
          module={LivebookWeb.Hub.SecretFormComponent}
          id="secrets"
          hub={@hub}
          deployment_group_id={@deployment_group.id}
          secret_name={@secret_name}
          secret_value={@secret_value}
          return_to={~p"/hub/#{@hub.id}/deployment-groups/edit/#{@deployment_group.id}"}
        />
      </.modal>
    </LayoutComponents.layout>
    """
  end

  @impl true
  def handle_event("validate_dockerfile", %{"data" => data}, socket) do
    changeset =
      data
      |> Hubs.Dockerfile.config_changeset(Hubs.Dockerfile.config_new())
      |> Map.replace!(:action, :validate)

    {:noreply,
     socket
     |> assign(config_changeset: changeset)
     |> update_dockerfile(:airgapped)}
  end

  def handle_event("add_agent_key", _, socket) do
    on_confirm = fn socket ->
      hub = Livebook.Hubs.fetch_hub!(socket.assigns.hub.id)
      deployment_group = socket.assigns.deployment_group

      case Teams.create_agent_key(hub, deployment_group) do
        :ok ->
          socket
          |> put_flash(:success, "Agent key created successfully")
          |> push_patch(to: ~p"/hub/#{hub.id}/deployment-groups/edit/#{deployment_group.id}")

        {:error, _changeset} ->
          put_flash(
            socket,
            :error,
            "Something went wrong, try again later or please file a bug if it persists"
          )

        {:transport_error, reason} ->
          put_flash(socket, :error, reason)
      end
    end

    {:noreply,
     confirm(socket, on_confirm,
       title: "Create agent key",
       description: "This will create a new agent key for this deployment group.",
       confirm_text: "Create",
       confirm_icon: "plus-6-line",
       danger: false
     )}
  end

  defp default_hub?(hub) do
    Hubs.get_default_hub().id == hub.id
  end

  defp update_dockerfile(socket, _) when socket.assigns.deployment_group == nil, do: socket

  defp update_dockerfile(socket, :airgapped) do
    config =
      socket.assigns.config_changeset
      |> Ecto.Changeset.apply_changes()
      |> Map.replace!(:deploy_all, true)

    deployment_group = socket.assigns.deployment_group

    config = %{
      config
      | clustering: deployment_group.clustering,
        zta_provider: deployment_group.zta_provider,
        zta_key: deployment_group.zta_key
    }

    %{hub: hub, secrets: deployment_group_secrets} = socket.assigns

    hub_secrets = Hubs.get_secrets(hub)
    hub_file_systems = Hubs.get_file_systems(hub, hub_only: true)

    secrets = Enum.uniq_by(deployment_group_secrets ++ hub_secrets, & &1.name)

    dockerfile =
      Hubs.Dockerfile.build_dockerfile(config, hub, secrets, hub_file_systems, nil, [], %{})

    assign(socket, :dockerfile, dockerfile)
  end

  defp update_dockerfile(%{assigns: %{hub: hub}} = socket, :agent) do
    config = Hubs.Dockerfile.config_new()
    dockerfile = Hubs.Dockerfile.build_agent_dockerfile(config, hub)

    assign(socket, :agent_dockerfile, dockerfile)
  end
end
