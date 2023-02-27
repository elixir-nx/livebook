defmodule LivebookWeb.SessionLive.AppInfoComponent do
  use LivebookWeb, :live_component

  use LivebookWeb, :verified_routes

  alias Livebook.Notebook.AppSettings

  @impl true
  def mount(socket) do
    {:ok, assign(socket, deploy_confirmation: false)}
  end

  @impl true
  def update(assigns, socket) do
    changeset =
      case socket.assigns do
        %{changeset: changeset} when changeset.data == assigns.settings -> changeset
        _ -> AppSettings.change(assigns.settings)
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(changeset: changeset)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col">
      <div class="flex items-center justify-between">
        <h3 class="uppercase text-sm font-semibold text-gray-500">
          App settings
        </h3>
        <.app_info_icon />
      </div>
      <div class="flex flex-col mt-2 space-y-4">
        <div class="w-full flex flex-col">
          <%= if @deploy_confirmation do %>
            <div class="mt-5">
              <div class="text-gray-700  flex items-center">
                <span class="text-sm">
                  Another app is already running under this slug, do you want to replace it?
                </span>
              </div>
              <div class="mt-5 flex space-x-2">
                <button
                  class="button-base button-red"
                  phx-click="deploy_confirmation_confirm"
                  phx-target={@myself}
                >
                  Replace
                </button>
                <button
                  class="button-base button-outlined-gray bg-transparent"
                  phx-click="deploy_confirmation_cancel"
                  phx-target={@myself}
                >
                  Cancel
                </button>
              </div>
            </div>
          <% else %>
            <.form
              :let={f}
              for={@changeset}
              phx-submit="deploy"
              phx-change="validate"
              phx-target={@myself}
              autocomplete="off"
            >
              <div class="flex flex-col space-y-4">
                <.text_field field={f[:slug]} label="Slug" spellcheck="false" phx-debounce="blur" />
                <div class="flex flex-col space-y-1">
                  <.checkbox_field
                    field={f[:access_type]}
                    label="Password-protected"
                    checked_value="protected"
                    unchecked_value="public"
                  />
                  <%= if Ecto.Changeset.get_field(@changeset, :access_type) == :protected do %>
                    <.password_field field={f[:password]} spellcheck="false" phx-debounce="blur" />
                  <% end %>
                </div>
                <.checkbox_field field={f[:show_source]} label="Show source" />
              </div>
              <div class="mt-6 flex space-x-2">
                <button class="button-base button-blue" type="submit" disabled={not @changeset.valid?}>
                  Deploy
                </button>
                <button
                  class="button-base button-outlined-gray bg-transparent"
                  type="reset"
                  name="reset"
                >
                  Reset
                </button>
              </div>
            </.form>
          <% end %>
        </div>
      </div>
      <%= if @apps != [] do %>
        <h3 class="mt-16 uppercase text-sm font-semibold text-gray-500">
          Deployments
        </h3>
        <div class="mt-2 flex flex-col space-y-4">
          <div :for={app <- @apps} class="border border-gray-200 pb-0 rounded-lg">
            <div class="p-4 flex flex-col space-y-3">
              <.labeled_text label="Status">
                <.status status={app.status} />
              </.labeled_text>
              <.labeled_text label="URL" one_line>
                <%= if app.registered do %>
                  <a href={url(~p"/apps/#{app.settings.slug}")} target="_blank">
                    <%= url(~p"/apps/#{app.settings.slug}") %>
                  </a>
                <% else %>
                  -
                <% end %>
              </.labeled_text>
            </div>
            <div class="border-t border-gray-200 px-3 py-2 flex space-x-2 justify-between">
              <span class="tooltip top" data-tooltip="Debug">
                <a
                  class="icon-button"
                  aria-label="debug app"
                  href={~p"/sessions/#{app.session_id}"}
                  target="_blank"
                >
                  <.remix_icon icon="terminal-line" class="text-lg" />
                </a>
              </span>
              <span class="tooltip top" data-tooltip="Shutdown">
                <button
                  class="icon-button"
                  aria-label="shutdown app"
                  phx-click={
                    JS.push("shutdown_app", value: %{session_id: app.session_id}, target: @myself)
                  }
                >
                  <.remix_icon icon="delete-bin-6-line" class="text-lg" />
                </button>
              </span>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp app_info_icon(assigns) do
    ~H"""
    <span
      class="icon-button cursor-pointer tooltip bottom-left"
      data-tooltip={
        ~S'''
        App deployment is a way to share your
        notebook for people to interact with. Use
        inputs and controls to build interactive
        UIs, perfect for demos and tasks.
        '''
      }
    >
      <.remix_icon icon="question-line" class="text-xl leading-none" />
    </span>
    """
  end

  defp status(%{status: :booting} = assigns) do
    ~H"""
    <.status_indicator text="Booting" circle_class="bg-blue-500" animated_circle_class="bg-blue-400" />
    """
  end

  defp status(%{status: :running} = assigns) do
    ~H"""
    <.status_indicator text="Running" circle_class="bg-green-bright-400" />
    """
  end

  defp status(%{status: :error} = assigns) do
    ~H"""
    <.status_indicator text="Error" circle_class="bg-red-400" />
    """
  end

  defp status(%{status: :shutting_down} = assigns) do
    ~H"""
    <.status_indicator text="Shutting down" circle_class="bg-gray-500" />
    """
  end

  defp status_indicator(assigns) do
    assigns =
      assigns
      |> assign_new(:animated_circle_class, fn -> nil end)

    ~H"""
    <div class="flex items-center space-x-2">
      <div><%= @text %></div>
      <span class="relative flex h-3 w-3">
        <span
          :if={@animated_circle_class}
          class={[
            @animated_circle_class,
            "animate-ping absolute inline-flex h-full w-full rounded-full opacity-75"
          ]}
        >
        </span>
        <span class={[@circle_class, "relative inline-flex rounded-full h-3 w-3 bg-blue-500"]}></span>
      </span>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"_target" => ["reset"]}, socket) do
    settings = AppSettings.new()
    Livebook.Session.set_app_settings(socket.assigns.session.pid, settings)
    {:noreply, assign(socket, changeset: AppSettings.change(settings))}
  end

  def handle_event("validate", %{"app_settings" => params}, socket) do
    changeset =
      socket.assigns.settings
      |> AppSettings.change(params)
      |> Map.put(:action, :validate)

    with {:ok, settings} <- AppSettings.update(socket.assigns.settings, params) do
      Livebook.Session.set_app_settings(socket.assigns.session.pid, settings)
    end

    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event("deploy", %{"app_settings" => params}, socket) do
    case AppSettings.update(socket.assigns.settings, params) do
      {:ok, settings} ->
        Livebook.Session.set_app_settings(socket.assigns.session.pid, settings)

        if slug_taken?(settings.slug, socket.assigns.apps) do
          {:noreply, assign(socket, deploy_confirmation: true)}
        else
          Livebook.Session.deploy_app(socket.assigns.session.pid)
          {:noreply, socket}
        end

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("deploy_confirmation_confirm", %{}, socket) do
    Livebook.Session.deploy_app(socket.assigns.session.pid)
    {:noreply, assign(socket, deploy_confirmation: false)}
  end

  def handle_event("deploy_confirmation_cancel", %{}, socket) do
    {:noreply, assign(socket, deploy_confirmation: false)}
  end

  def handle_event("shutdown_app", %{"session_id" => session_id}, socket) do
    app = Enum.find(socket.assigns.apps, &(&1.session_id == session_id))
    Livebook.Session.close(app.session_pid)
    {:noreply, socket}
  end

  defp slug_taken?(slug, apps) do
    own? =
      Enum.any?(apps, fn app ->
        app.registered and app.settings.slug == slug
      end)

    not own? and Livebook.Apps.exists?(slug)
  end
end
