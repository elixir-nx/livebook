defmodule LivebookWeb.SettingsLive do
  use LivebookWeb, :live_view

  alias LivebookWeb.{LayoutHelpers, PageHelpers}

  on_mount LivebookWeb.SidebarHook

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Livebook.Settings.subscribe()
    end

    {:ok,
     assign(socket,
       file_systems: Livebook.Settings.file_systems(),
       env_vars: Livebook.Settings.fetch_env_vars(),
       env_var: nil,
       autosave_path_state: %{
         file: autosave_dir(),
         dialog_opened?: false
       },
       update_check_enabled: Livebook.UpdateCheck.enabled?(),
       page_title: "Livebook - Settings"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutHelpers.layout
      socket={@socket}
      current_page={Routes.settings_path(@socket, :page)}
      current_user={@current_user}
      saved_hubs={@saved_hubs}
    >
      <div id="settings-page" class="p-4 sm:px-8 md:px-16 sm:py-7 max-w-screen-md mx-auto space-y-16">
        <!-- System settings section -->
        <div class="flex flex-col space-y-10">
          <div>
            <PageHelpers.title text="System settings" />
            <p class="mt-4 text-gray-700">
              Here you can change global Livebook configuration. Keep in mind
              that this configuration gets persisted and will be restored on application
              launch.
            </p>
          </div>
          <!-- System details -->
          <div class="flex flex-col space-y-2">
            <h2 class="text-xl text-gray-800 font-medium">
              About
            </h2>
            <div class="flex items-center justify-between border border-gray-200 rounded-lg p-4">
              <div class="flex items-center space-x-12">
                <%= if app_name = Livebook.Config.app_service_name() do %>
                  <.labeled_text label="Application">
                    <%= if app_url = Livebook.Config.app_service_url() do %>
                      <a href={app_url} class="underline hover:no-underline" target="_blank">
                        <%= app_name %>
                      </a>
                    <% else %>
                      <%= app_name %>
                    <% end %>
                  </.labeled_text>
                <% end %>
                <.labeled_text label="Livebook">
                  v<%= Application.spec(:livebook, :vsn) %>
                </.labeled_text>
                <.labeled_text label="Elixir">
                  v<%= System.version() %>
                </.labeled_text>
              </div>

              <%= live_redirect to: Routes.live_dashboard_path(@socket, :home),
                                  class: "button-base button-outlined-gray" do %>
                <.remix_icon icon="dashboard-2-line" class="align-middle mr-1" />
                <span>Open dashboard</span>
              <% end %>
            </div>
          </div>
          <!-- Updates -->
          <div class="flex flex-col space-y-4">
            <h2 class="text-xl text-gray-800 font-medium pb-2 border-b border-gray-200">
              Updates
            </h2>
            <form class="mt-4" phx-change="save" onsubmit="return false;">
              <.switch_checkbox
                name="update_check_enabled"
                label="Show banner when a new Livebook version is available"
                checked={@update_check_enabled}
              />
            </form>
          </div>
          <!-- Autosave path configuration -->
          <div class="flex flex-col space-y-4">
            <h2 class="text-xl text-gray-800 font-medium pb-2 border-b border-gray-200">
              Autosave
            </h2>
            <p class="text-gray-700">
              The directory to keep unsaved notebooks.
            </p>
            <.autosave_path_select state={@autosave_path_state} />
          </div>
          <!-- File systems configuration -->
          <div class="flex flex-col space-y-4">
            <h2 class="text-xl text-gray-800 font-medium pb-2 border-b border-gray-200">
              File systems
            </h2>
            <p class="mt-4 text-gray-700">
              File systems are used to store notebooks. The local disk filesystem
              is visible only to the current machine, but alternative file systems
              are available, such as S3-based storages.
            </p>
            <LivebookWeb.SettingsLive.FileSystemsComponent.render
              file_systems={@file_systems}
              socket={@socket}
            />
          </div>
          <!-- Environment variables configuration -->
          <div class="flex flex-col space-y-4">
            <h2 class="text-xl text-gray-800 font-semibold pb-2 border-b border-gray-200">
              Environment variables
            </h2>
            <p class="mt-4 text-gray-700">
              Environment variables are used to store global values and secrets.
              The global environment variables can be used on the entire Livebook
              application and is accessible only to the current machine.
            </p>
            <.live_component
              module={LivebookWeb.EnvVarsComponent}
              id="env-vars"
              env_vars={@env_vars}
              return_to={Routes.settings_path(@socket, :page)}
              add_env_var_path={Routes.settings_path(@socket, :add_env_var)}
              target={@socket.view}
            />
          </div>
        </div>
        <!-- User settings section -->
        <div class="flex flex-col space-y-10">
          <div>
            <PageHelpers.title text="User settings" />
            <p class="mt-4 text-gray-700">
              The configuration in this section changes only your Livebook
              experience and is saved in your browser.
            </p>
          </div>
          <!-- Editor configuration -->
          <div class="flex flex-col space-y-4">
            <h2 class="text-xl text-gray-800 font-medium pb-2 border-b border-gray-200">
              Code editor
            </h2>
            <div
              class="flex flex-col space-y-3"
              id="editor-settings"
              phx-hook="EditorSettings"
              phx-update="ignore"
            >
              <.switch_checkbox
                name="editor_auto_completion"
                label="Show completion list while typing"
                checked={false}
              />
              <.switch_checkbox
                name="editor_auto_signature"
                label="Show function signature while typing"
                checked={false}
              />
              <.switch_checkbox name="editor_font_size" label="Increase font size" checked={false} />
              <.switch_checkbox
                name="editor_high_contrast"
                label="Use high contrast theme"
                checked={false}
              />
              <.switch_checkbox
                name="editor_markdown_word_wrap"
                label="Wrap words in Markdown"
                checked={false}
              />
            </div>
          </div>
        </div>
      </div>
    </LayoutHelpers.layout>

    <%= if @live_action == :add_file_system do %>
      <.modal
        id="add-file-system-modal"
        show
        class="w-full max-w-3xl"
        patch={Routes.settings_path(@socket, :page)}
      >
        <.live_component
          module={LivebookWeb.SettingsLive.AddFileSystemComponent}
          id="add-file-system"
          return_to={Routes.settings_path(@socket, :page)}
        />
      </.modal>
    <% end %>

    <%= if @live_action in [:add_env_var, :edit_env_var] do %>
      <.modal
        id="env-var-modal"
        show
        class="w-full max-w-3xl"
        on_close={JS.push("clear_env_var")}
        patch={Routes.settings_path(@socket, :page)}
      >
        <.live_component
          module={LivebookWeb.EnvVarComponent}
          id="env-var"
          env_var={@env_var}
          headline="Configure your application global environment variables."
          return_to={Routes.settings_path(@socket, :page)}
        />
      </.modal>
    <% end %>
    """
  end

  defp autosave_path_select(%{state: %{file: nil}} = assigns), do: ~H""

  defp autosave_path_select(%{state: %{dialog_opened?: true}} = assigns) do
    ~H"""
    <div class="w-full h-52">
      <.live_component
        module={LivebookWeb.FileSelectComponent}
        id="autosave-path-component"
        file={@state.file}
        extnames={[]}
        running_files={[]}
        submit_event={:set_autosave_path}
        file_system_select_disabled={true}
      >
        <button class="button-base button-gray" phx-click="cancel_autosave_path" tabindex="-1">
          Cancel
        </button>
        <button class="button-base button-gray" phx-click="reset_autosave_path" tabindex="-1">
          Reset
        </button>
        <button
          class="button-base button-blue"
          phx-click="set_autosave_path"
          disabled={not Livebook.FileSystem.File.dir?(@state.file)}
          tabindex="-1"
        >
          Save
        </button>
      </.live_component>
    </div>
    """
  end

  defp autosave_path_select(assigns) do
    ~H"""
    <div class="flex">
      <input class="input mr-2" readonly value={@state.file.path} />
      <button class="button-base button-gray button-small" phx-click="open_autosave_path_select">
        Change
      </button>
    </div>
    """
  end

  @impl true
  def handle_params(%{"env_var_id" => key}, _url, socket) do
    env_var = Livebook.Settings.fetch_env_var!(key)
    {:noreply, assign(socket, env_var: env_var)}
  end

  def handle_params(%{"file_system_id" => file_system_id}, _url, socket) do
    {:noreply, assign(socket, file_system_id: file_system_id)}
  end

  def handle_params(_params, _url, socket), do: {:noreply, assign(socket, env_var: nil)}

  @impl true
  def handle_event("cancel_autosave_path", %{}, socket) do
    {:noreply,
     update(
       socket,
       :autosave_path_state,
       &%{&1 | dialog_opened?: false, file: autosave_dir()}
     )}
  end

  def handle_event("set_autosave_path", %{}, socket) do
    path = socket.assigns.autosave_path_state.file.path

    Livebook.Settings.set_autosave_path(path)

    {:noreply,
     update(
       socket,
       :autosave_path_state,
       &%{&1 | dialog_opened?: false, file: autosave_dir()}
     )}
  end

  @impl true
  def handle_event("reset_autosave_path", %{}, socket) do
    {:noreply,
     update(
       socket,
       :autosave_path_state,
       &%{&1 | file: default_autosave_dir()}
     )}
  end

  def handle_event("open_autosave_path_select", %{}, socket) do
    {:noreply, update(socket, :autosave_path_state, &%{&1 | dialog_opened?: true})}
  end

  def handle_event("detach_file_system", %{"id" => file_system_id}, socket) do
    Livebook.Settings.remove_file_system(file_system_id)
    file_systems = Livebook.Settings.file_systems()
    {:noreply, assign(socket, file_systems: file_systems)}
  end

  def handle_event("save", %{"update_check_enabled" => enabled}, socket) do
    enabled = enabled == "true"
    Livebook.UpdateCheck.set_enabled(enabled)
    {:noreply, assign(socket, :update_check_enabled, enabled)}
  end

  def handle_event("save", %{"env_var" => attrs}, socket) do
    env_var = %Livebook.Settings.EnvVar{}

    case Livebook.Settings.set_env_var(socket.assigns.env_var || env_var, attrs) do
      {:ok, _} ->
        {:noreply, push_patch(socket, to: Routes.settings_path(socket, :page))}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("edit_env_var", %{"env_var" => key}, socket) do
    {:noreply, push_patch(socket, to: Routes.settings_path(socket, :edit_env_var, key))}
  end

  def handle_event("delete_env_var", %{"env_var" => key}, socket) do
    Livebook.Settings.delete_env_var(key)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:file_systems_updated, file_systems}, socket) do
    {:noreply, assign(socket, file_systems: file_systems)}
  end

  def handle_info({:set_file, file, _info}, socket) do
    {:noreply, update(socket, :autosave_path_state, &%{&1 | file: file})}
  end

  def handle_info(:set_autosave_path, socket) do
    handle_event("set_autosave_path", %{}, socket)
  end

  def handle_info({:env_vars_changed, env_vars}, socket) do
    {:noreply, assign(socket, env_vars: env_vars, env_var: nil)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp autosave_dir() do
    if path = Livebook.Settings.autosave_path() do
      path
      |> Livebook.FileSystem.Utils.ensure_dir_path()
      |> Livebook.FileSystem.File.local()
    end
  end

  defp default_autosave_dir() do
    Livebook.Settings.default_autosave_path()
    |> Livebook.FileSystem.Utils.ensure_dir_path()
    |> Livebook.FileSystem.File.local()
  end
end
