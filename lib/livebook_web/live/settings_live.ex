defmodule LivebookWeb.SettingsLive do
  use LivebookWeb, :live_view

  import LivebookWeb.UserHelpers

  alias LivebookWeb.{SidebarHelpers, PageHelpers}

  @impl true
  def mount(_params, _session, socket) do
    file_systems = Livebook.Settings.file_systems()

    {:ok,
     socket
     |> SidebarHelpers.shared_home_handlers()
     |> assign(
       file_systems: file_systems,
       page_title: "Livebook - Settings"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex grow h-full">
      <SidebarHelpers.sidebar>
        <SidebarHelpers.logo_item socket={@socket} />
        <SidebarHelpers.shared_home_footer socket={@socket} current_user={@current_user} />
      </SidebarHelpers.sidebar>
      <div class="grow px-6 py-8 overflow-y-auto">
        <div class="max-w-screen-md w-full mx-auto px-4 pb-8 space-y-16">
          <!-- System settings section -->
          <div class="flex flex-col space-y-8">
            <div>
              <PageHelpers.title text="System settings" socket={@socket} />
              <p class="mt-4 text-gray-700">
                Here you can change global Livebook configuration. Keep in mind
                that this configuration is not persisted and gets discarded as
                soon as you stop the application.
              </p>
            </div>

          <!-- System details -->
          <div class="flex flex-col space-y-4">
            <h1 class="text-xl text-gray-800 font-semibold">
              About
            </h1>
            <div class="flex items-center justify-between border border-gray-200 rounded-lg p-4">
              <div class="flex items-center space-x-12">
                <.labeled_text label="Livebook" text={"v#{Application.spec(:livebook, :vsn)}"} />
                <.labeled_text label="Elixir" text={"v#{System.version()}"} />
              </div>

              <%= live_redirect to: Routes.live_dashboard_path(@socket, :home),
                                class: "button-base button-outlined-gray" do %>
                <.remix_icon icon="dashboard-2-line" class="align-middle mr-1" />
                <span>Open dashboard</span>
              <% end %>
            </div>
          </div>
          <!-- File systems configuration -->
          <div class="flex flex-col space-y-4">
            <div class="flex justify-between items-center">
              <h2 class="text-xl text-gray-800 font-semibold">
                File systems
              </h2>
            </div>
              <LivebookWeb.SettingsLive.FileSystemsComponent.render
                file_systems={@file_systems}
                socket={@socket} />
            </div>
          </div>
          <!-- User settings section -->
          <div class="flex flex-col space-y-8">
            <div>
              <h1 class="text-3xl text-gray-800 font-semibold">
                User settings
              </h1>
              <p class="mt-4 text-gray-700">
                The configuration in this section changes only your Livebook
                experience and is saved in your browser.
              </p>
            </div>
            <!-- Editor configuration -->
            <div class="flex flex-col space-y-4">
              <h2 class="text-xl text-gray-800 font-semibold">
                Code editor
              </h2>
              <div class="flex flex-col space-y-3"
                id="editor-settings"
                phx-hook="EditorSettings"
                phx-update="ignore">
                <.switch_checkbox
                  name="editor_auto_completion"
                  label="Show completion list while typing"
                  checked={false} />
                <.switch_checkbox
                  name="editor_auto_signature"
                  label="Show function signature while typing"
                  checked={false} />
                <.switch_checkbox
                  name="editor_font_size"
                  label="Increase font size"
                  checked={false} />
                <.switch_checkbox
                  name="editor_high_contrast"
                  label="Use high contrast theme"
                  checked={false} />
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <.current_user_modal current_user={@current_user} />

    <%= if @live_action == :add_file_system do %>
      <.modal id="add-file-system-modal" show class="w-full max-w-3xl" patch={Routes.settings_path(@socket, :page)}>
        <.live_component module={LivebookWeb.SettingsLive.AddFileSystemComponent}
          id="add-file-system"
          return_to={Routes.settings_path(@socket, :page)} />
      </.modal>
    <% end %>
    """
  end

  @impl true
  def handle_params(%{"file_system_id" => file_system_id}, _url, socket) do
    {:noreply, assign(socket, file_system_id: file_system_id)}
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("detach_file_system", %{"id" => file_system_id}, socket) do
    Livebook.Settings.remove_file_system(file_system_id)
    file_systems = Livebook.Settings.file_systems()
    {:noreply, assign(socket, file_systems: file_systems)}
  end

  @impl true
  def handle_info({:file_systems_updated, file_systems}, socket) do
    {:noreply, assign(socket, file_systems: file_systems)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
