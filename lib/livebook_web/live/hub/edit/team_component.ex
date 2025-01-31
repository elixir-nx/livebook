defmodule LivebookWeb.Hub.Edit.TeamComponent do
  use LivebookWeb, :live_component

  alias Livebook.Hubs
  alias Livebook.Hubs.Provider
  alias Livebook.Teams
  alias LivebookWeb.LayoutComponents
  alias LivebookWeb.NotFoundError

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    changeset = Teams.change_hub(assigns.hub)
    show_key = assigns.params["show-key"]
    secrets = Hubs.get_secrets(assigns.hub)
    file_systems = Hubs.get_file_systems(assigns.hub, hub_only: true)
    deployment_groups = Teams.get_deployment_groups(assigns.hub)
    app_deployments = Teams.get_app_deployments(assigns.hub)
    agents = Teams.get_agents(assigns.hub)
    environment_variables = Teams.get_environment_variables(assigns.hub)
    secret_name = assigns.params["secret_name"]
    file_system_id = assigns.params["file_system_id"]
    default? = default_hub?(assigns.hub)

    secret_value =
      if assigns.live_action == :edit_secret do
        Enum.find_value(secrets, &(&1.name == secret_name and &1.value)) ||
          raise(NotFoundError, "could not find secret matching #{inspect(secret_name)}")
      end

    file_system =
      if assigns.live_action == :edit_file_system do
        Enum.find_value(file_systems, &(&1.id == file_system_id && &1)) ||
          raise(NotFoundError, "could not find file system matching #{inspect(file_system_id)}")
      end

    {:ok,
     socket
     |> assign(
       secrets: secrets,
       file_system: file_system,
       file_system_id: file_system_id,
       file_systems: file_systems,
       deployment_groups: Enum.sort_by(deployment_groups, & &1.name),
       app_deployments: Enum.frequencies_by(app_deployments, & &1.deployment_group_id),
       agents: Enum.frequencies_by(agents, & &1.deployment_group_id),
       environment_variables:
         Enum.frequencies_by(environment_variables, & &1.deployment_group_id),
       show_key: show_key,
       secret_name: secret_name,
       secret_value: secret_value,
       hub_metadata: Provider.to_metadata(assigns.hub),
       default?: default?,
       billing_info: Hubs.Team.billing_info(assigns.hub)
     )
     |> assign_form(changeset)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <LayoutComponents.topbar :if={Provider.connection_status(@hub)} variant="warning">
        {Provider.connection_status(@hub)}
      </LayoutComponents.topbar>

      <LayoutComponents.topbar :if={@billing_info.status == :trial_until} variant="warning">
        <h2>
          Your organization has <strong>{@billing_info.trial_days_left} day(s) left</strong>
          on the free trial. Need help getting set up? <a
            class="underline"
            href="mailto:suport@livebook.dev?subject=Help%20with%20Livebook%20Teams"
          >Contact us</a>.
        </h2>
      </LayoutComponents.topbar>

      <LayoutComponents.topbar :if={@billing_info.disabled?} variant="warning">
        <h2>
          Workspace disabled: your organization doesn't have an active subscription. Please contact your <.link
            href={org_url(@hub, "/users")}
            class="underline"
          >org's admin</.link>.
        </h2>
      </LayoutComponents.topbar>

      <div class="p-4 md:px-12 md:py-7 max-w-screen-md mx-auto">
        <div id={"#{@id}-component"}>
          <div class="mb-8 flex flex-col space-y-2">
            <LayoutComponents.title>
              <div class="flex gap-2 items-center">
                <div class="flex justify-center">
                  <span class="relative">
                    {@hub.hub_emoji}
                    <div class={[
                      "absolute w-[10px] h-[10px] border-white border-2 rounded-full right-0 bottom-1",
                      if(@hub_metadata.connected?, do: "bg-green-400", else: "bg-red-400")
                    ]} />
                  </span>
                </div>
                {@hub.hub_name}
                <span class="bg-green-100 text-green-800 text-xs px-2.5 py-0.5 rounded cursor-default">
                  Livebook Teams
                </span>
                <%= if @default? do %>
                  <span class="bg-blue-100 text-blue-800 text-xs px-2.5 py-0.5 rounded cursor-default">
                    Default
                  </span>
                <% end %>
              </div>
            </LayoutComponents.title>

            <p class="text-sm flex flex-row space-x-6 text-gray-700">
              <a href={org_url(@hub, "/")} class="hover:text-blue-600">
                <.remix_icon icon="mail-line" /> Invite users
              </a>

              <a href={org_url(@hub, "/")} class="hover:text-blue-600">
                <.remix_icon icon="settings-line" /> Manage organization
              </a>

              <.link
                patch={~p"/hub/#{@hub.id}?show-key=yes"}
                class="hover:text-blue-600 cursor-pointer"
              >
                <.remix_icon icon="key-2-fill" /> Display Teams key
              </.link>
              <%= if @default? do %>
                <button
                  phx-click="remove_as_default"
                  phx-target={@myself}
                  class="hover:text-blue-600 cursor-pointer"
                >
                  <.remix_icon icon="star-fill" /> Remove as default
                </button>
              <% else %>
                <button
                  phx-click="mark_as_default"
                  phx-target={@myself}
                  class="hover:text-blue-600 cursor-pointer"
                >
                  <.remix_icon icon="star-line" /> Mark as default
                </button>
              <% end %>
            </p>
          </div>
          <div class="mb-8 flex flex-col space-y-10">
            <div class="flex flex-col space-y-4">
              <h2 class="text-xl text-gray-800 font-medium pb-2 border-b border-gray-200">
                General
              </h2>

              <.form
                id={@id}
                class="flex flex-col md:flex-row mt-4 space-y-4 md:space-x-2 md:space-y-0"
                for={@form}
                phx-submit="save"
                phx-change="validate"
                phx-target={@myself}
              >
                <div class="flex-auto">
                  <.text_field
                    field={@form[:hub_name]}
                    label="Name"
                    disabled
                    help="Name cannot be changed"
                    class="bg-gray-200/50 border-200/80 cursor-not-allowed"
                  />
                </div>

                <div class="min-w-48">
                  <.emoji_field field={@form[:hub_emoji]} label="Emoji" />
                </div>

                <div class="!mt-6">
                  <.button type="submit" phx-disable-with="Updating...">
                    Save
                  </.button>
                </div>
              </.form>
            </div>

            <div class="flex flex-col space-y-4">
              <h2 class="text-xl text-gray-800 font-medium pb-2 border-b border-gray-200">
                Secrets
              </h2>

              <p class="text-gray-700">
                Secrets are a safe way to allow notebooks to access
                credentials and tokens.
              </p>

              <.live_component
                module={LivebookWeb.Hub.SecretListComponent}
                id="hub-secrets-list"
                hub={@hub}
                secrets={@secrets}
                edit_path={"hub/#{@hub.id}/secrets/edit"}
                return_to={~p"/hub/#{@hub.id}"}
                disabled={@billing_info.disabled?}
              />

              <div>
                <.button
                  patch={~p"/hub/#{@hub.id}/secrets/new"}
                  id="add-secret"
                  disabled={@billing_info.disabled?}
                >
                  Add secret
                </.button>
              </div>
            </div>

            <div class="flex flex-col space-y-4">
              <h2 class="text-xl text-gray-800 font-medium pb-2 border-b border-gray-200">
                File storages
              </h2>

              <p class="text-gray-700">
                File storages are used to store notebooks and their files across your whole team.
              </p>

              <.live_component
                module={LivebookWeb.Hub.FileSystemListComponent}
                id="hub-file-systems-list"
                hub_id={@hub.id}
                file_systems={@file_systems}
                target={@myself}
                disabled={@billing_info.disabled?}
              />
            </div>

            <div class="flex flex-col space-y-4">
              <h2 class="text-xl text-gray-800 font-medium pb-2 border-b border-gray-200">
                Deployment groups
              </h2>

              <p class="text-gray-700">
                Deployment groups allow you to deploy Livebook apps to self-hosted machines with the click of a button.
              </p>

              <.no_entries :if={@deployment_groups == []}>
                No deployment groups here... yet!
              </.no_entries>

              <div :for={deployment_group <- @deployment_groups} class="flex flex-col space-y-4">
                <.live_component
                  module={LivebookWeb.Hub.Teams.DeploymentGroupComponent}
                  id={"hub-deployment-group-#{deployment_group.id}"}
                  hub={@hub}
                  deployment_group={deployment_group}
                  app_deployments_count={Map.get(@app_deployments, deployment_group.id, 0)}
                  environment_variables_count={
                    Map.get(@environment_variables, deployment_group.id, 0)
                  }
                  agents_count={Map.get(@agents, deployment_group.id, 0)}
                  live_action={@live_action}
                  params={@params}
                />
              </div>

              <div>
                <.button
                  patch={~p"/hub/#{@hub.id}/groups/new"}
                  id="add-deployment-group"
                  disabled={@billing_info.disabled?}
                >
                  Add deployment group
                </.button>
              </div>
            </div>

            <div class="flex flex-col space-y-4">
              <h2 class="text-xl text-gray-800 font-medium pb-2 border-b border-gray-200">
                Danger zone
              </h2>

              <div class="flex items-center justify-between gap-4 text-gray-700">
                <div class="flex flex-col">
                  <h3 class="font-semibold">
                    Delete this workspace
                  </h3>
                  <p class="text-sm">
                    This only removes the workpsace from this machine. You must rejoin to access its features once again.
                  </p>
                </div>
                <.button
                  color="red"
                  outlined
                  id="delete-hub"
                  phx-click={JS.push("delete_hub", value: %{id: @hub.id})}
                >
                  <span class="hidden sm:block">Delete workspace</span>
                  <.remix_icon icon="delete-bin-line" class="text-lg sm:hidden" />
                </.button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <.modal :if={@show_key} id="key-modal" show width="medium" patch={~p"/hub/#{@hub.id}"}>
        <.teams_key_modal
          teams_key={@hub.teams_key}
          confirm_url={if @show_key == "confirm", do: ~p"/hub/#{@hub.id}"}
        />
      </.modal>

      <.modal
        :if={@live_action in [:new_secret, :edit_secret]}
        id="secrets-modal"
        show
        width="medium"
        patch={~p"/hub/#{@hub.id}"}
      >
        <.live_component
          module={LivebookWeb.Hub.SecretFormComponent}
          id="secrets"
          hub={@hub}
          secret_name={@secret_name}
          secret_value={@secret_value}
          return_to={~p"/hub/#{@hub.id}"}
          disabled={@billing_info.disabled?}
        />
      </.modal>

      <.modal
        :if={@live_action in [:new_file_system, :edit_file_system]}
        id="file-systems-modal"
        show
        width="medium"
        patch={~p"/hub/#{@hub.id}"}
      >
        <.live_component
          module={LivebookWeb.Hub.FileSystemFormComponent}
          id="file-systems"
          hub={@hub}
          disabled={@billing_info.disabled?}
          file_system={@file_system}
          file_system_id={@file_system_id}
          return_to={~p"/hub/#{@hub.id}"}
        />
      </.modal>

      <.modal
        :if={@live_action == :new_deployment_group}
        id="deployment-group-modal"
        show
        width="big"
        patch={~p"/hub/#{@hub.id}"}
      >
        <.live_component
          module={LivebookWeb.Hub.Teams.DeploymentGroupFormComponent}
          id="deployment-group"
          hub={@hub}
          return_to={~p"/hub/#{@hub.id}"}
        />
      </.modal>
    </div>
    """
  end

  defp org_url(hub, path) do
    Livebook.Config.teams_url() <> "/orgs/#{hub.org_id}" <> path
  end

  defp teams_key_modal(assigns) do
    ~H"""
    <div class="flex flex-col space-y-5">
      <h3 class="text-2xl font-semibold text-gray-800">
        Teams key
      </h3>
      <div class="justify-center">
        This is your <strong>Teams key</strong>. This key encrypts your
        data before it is sent to Livebook Teams servers. This key is
        required for you and invited users to join this organization.
        We recommend storing it somewhere safe:
      </div>
      <div class="flex gap-2">
        <div class="grow">
          <.password_field id="teams-key" name="teams_key" value={@teams_key} readonly />
        </div>

        <span
          data-tooltip="Copied to clipboard"
          aria-label="copy to clipboard"
          phx-click={
            JS.dispatch("lb:clipcopy", to: "#teams-key")
            |> JS.transition("tooltip left", time: 2000)
          }
        >
          <.button color="gray" small type="button">
            <.remix_icon icon="clipboard-line" class="text-xl leading-none py-1" />
          </.button>
        </span>
      </div>
      <.button :if={@confirm_url} patch={@confirm_url}>
        <.remix_icon class="mr-1" icon="thumb-up-fill" /> I've saved my Teams key in a secure location
      </.button>
    </div>
    """
  end

  @impl true
  def handle_event("save", %{"team" => params}, socket) do
    case Teams.update_hub(socket.assigns.hub, params) do
      {:ok, hub} ->
        {:noreply,
         socket
         |> put_flash(:success, "Workspace updated successfully")
         |> push_patch(to: ~p"/hub/#{hub.id}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"team" => attrs}, socket) do
    changeset =
      socket.assigns.hub
      |> Teams.change_hub(attrs)
      |> Map.replace!(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("mark_as_default", _, socket) do
    Hubs.set_default_hub(socket.assigns.hub.id)
    {:noreply, assign(socket, default?: true)}
  end

  def handle_event("remove_as_default", _, socket) do
    Hubs.unset_default_hub()
    {:noreply, assign(socket, default?: false)}
  end

  defp default_hub?(hub) do
    Hubs.get_default_hub().id == hub.id
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset))
  end
end
