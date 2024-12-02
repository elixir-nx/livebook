defmodule LivebookWeb.LayoutComponents do
  use LivebookWeb, :html

  import LivebookWeb.UserComponents

  alias Livebook.Hubs.Provider

  @doc """
  The layout used in the non-session pages.
  """
  attr :current_page, :string, required: true
  attr :current_user, Livebook.Users.User, required: true
  attr :saved_hubs, :list, required: true

  slot :inner_block, required: true
  slot :topbar_action

  def layout(assigns) do
    ~H"""
    <div class="flex grow h-full">
      <div class="absolute md:static h-full z-[600]">
        <.live_region role="alert" />
        <.sidebar current_page={@current_page} current_user={@current_user} saved_hubs={@saved_hubs} />
      </div>
      <div class="grow overflow-y-auto">
        <div class="md:hidden sticky flex items-center justify-between h-14 px-4 top-0 left-0 z-[500] bg-white border-b border-gray-200">
          <div class="pt-1 text-xl text-gray-400 hover:text-gray-600 focus:text-gray-600">
            <button
              data-el-toggle-sidebar
              aria-label="show sidebar"
              phx-click={
                JS.remove_class("hidden", to: "[data-el-sidebar]")
                |> JS.toggle(to: "[data-el-toggle-sidebar]")
              }
            >
              <.remix_icon icon="menu-unfold-line" />
            </button>
          </div>

          <div>
            <%= if @topbar_action do %>
              <%= render_slot(@topbar_action) %>
            <% else %>
              <div class="text-gray-400 hover:text-gray-600 focus:text-gray-600">
                <.link navigate={~p"/"} class="flex items-center" aria-label="go to home">
                  <.remix_icon icon="home-6-line" />
                  <span class="pl-2">Home</span>
                </.link>
              </div>
            <% end %>
          </div>
        </div>
        <%= render_slot(@inner_block) %>
      </div>
    </div>

    <.current_user_modal current_user={@current_user} />
    """
  end

  defp sidebar(assigns) do
    ~H"""
    <nav
      class="hidden md:flex w-[17rem] h-full py-2 md:py-5 bg-gray-900"
      aria-label="sidebar"
      data-el-sidebar
    >
      <button
        class="hidden text-xl text-gray-300 hover:text-white focus:text-white absolute top-4 right-3"
        aria-label="hide sidebar"
        data-el-toggle-sidebar
        phx-click={
          JS.add_class("hidden", to: "[data-el-sidebar]")
          |> JS.toggle(to: "[data-el-toggle-sidebar]")
        }
      >
        <.remix_icon icon="menu-fold-line" />
      </button>

      <div class="flex flex-col justify-between h-full w-full">
        <div class="flex flex-col">
          <div class="space-y-3">
            <div class="flex items-center mb-5">
              <.link navigate={~p"/"} class="flex items-center ml-1 group">
                <img
                  src={~p"/images/logo.png"}
                  class="mx-2"
                  height="40"
                  width="40"
                  alt="logo livebook"
                />
                <span class="text-gray-300 text-2xl font-logo ml-[-1px] group-hover:text-white pt-1">
                  Livebook
                </span>
              </.link>
              <span class="text-gray-300 text-xs font-normal font-sans mx-2.5 pt-3 cursor-default">
                v<%= Livebook.Config.app_version() %>
              </span>
            </div>
            <.sidebar_link title="Home" icon="home-6-line" to={~p"/"} current={@current_page} />
            <.sidebar_link
              title="Local apps"
              icon="rocket-line"
              to={~p"/apps-dashboard"}
              current={@current_page}
            />
            <.sidebar_link title="Learn" icon="article-line" to={~p"/learn"} current={@current_page} />
            <.sidebar_link
              title="Settings"
              icon="settings-3-line"
              to={~p"/settings"}
              current={@current_page}
            />
          </div>
          <.hub_section hubs={@saved_hubs} current_page={@current_page} />
        </div>
        <div class="flex flex-col">
          <button
            :if={Livebook.Config.shutdown_callback()}
            class="h-7 flex items-center text-gray-400 hover:text-white border-l-4 border-transparent hover:border-white"
            aria-label="shutdown"
            phx-click="shutdown"
          >
            <.remix_icon icon="shut-down-line" class="text-lg leading-6 w-[56px] flex justify-center" />
            <span class="text-sm font-medium">
              Shut Down
            </span>
          </button>
          <button
            :if={@current_user.email}
            class="h-7 flex items-center text-gray-400 hover:text-white border-l-4 border-transparent hover:border-white"
            aria-label="logout"
            phx-click="logout"
          >
            <.remix_icon
              icon="logout-box-line"
              class="text-lg leading-6 w-[56px] flex justify-center"
            />
            <span class="text-sm font-medium">
              Logout
            </span>
          </button>
          <button
            class="mt-6 flex items-center group border-l-4 border-transparent"
            aria_label="user profile"
            phx-click={show_current_user_modal()}
          >
            <div class="w-[56px] flex justify-center">
              <.user_avatar
                user={@current_user}
                class="w-8 h-8 group-hover:ring-white group-hover:ring-2"
                text_class="text-xs"
              />
            </div>
            <span class="text-sm text-gray-400 font-medium group-hover:text-white">
              <%= @current_user.name %>
            </span>
          </button>
        </div>
      </div>
    </nav>
    """
  end

  defp sidebar_link(assigns) do
    ~H"""
    <.link
      navigate={@to}
      class={[
        "h-7 flex items-center hover:text-white border-l-4 hover:border-white",
        sidebar_link_text_color(@to, @current),
        sidebar_link_border_color(@to, @current)
      ]}
    >
      <.remix_icon icon={@icon} class="text-lg leading-6 w-[56px] flex justify-center" />
      <span class="text-sm font-medium">
        <%= @title %>
      </span>
    </.link>
    """
  end

  defp sidebar_hub_link(assigns) do
    ~H"""
    <.link
      id={"hub-#{@hub.id}"}
      navigate={@to}
      class={[
        "h-7 flex items-center hover:text-white border-l-4 hover:border-white",
        sidebar_link_text_color(@to, @current),
        sidebar_link_border_color(@to, @current)
      ]}
    >
      <div class="text-lg leading-6 w-[56px] flex justify-center">
        <span class="relative">
          <%= @hub.emoji %>
        </span>
      </div>
      <span class="text-sm font-medium">
        <%= @hub.name %>
      </span>
    </.link>
    """
  end

  defp sidebar_hub_link_with_tooltip(assigns) do
    ~H"""
    <.link {hub_connection_link_opts(@hub, @to, @current)}>
      <div class="text-lg leading-6 w-[56px] flex justify-center">
        <span class="relative">
          <%= @hub.emoji %>

          <div class={[
            "absolute w-[10px] h-[10px] border-gray-900 border-2 rounded-full right-0 bottom-0",
            if(@hub.connected?, do: "bg-green-400", else: "bg-red-400")
          ]} />
        </span>
      </div>
      <span class="text-sm font-medium">
        <%= @hub.name %>
      </span>
    </.link>
    """
  end

  defp hub_section(assigns) do
    ~H"""
    <div id="hubs" class="flex flex-col mt-12">
      <div class="space-y-3">
        <div class="grid grid-cols-1 md:grid-cols-2 relative leading-6 mb-2">
          <small class="ml-5 font-medium text-gray-300 cursor-default">WORKSPACES</small>
        </div>

        <%= for hub <- @hubs do %>
          <%= if Provider.connection_spec(hub.provider) do %>
            <.sidebar_hub_link_with_tooltip hub={hub} to={~p"/hub/#{hub.id}"} current={@current_page} />
          <% else %>
            <.sidebar_hub_link hub={hub} to={~p"/hub/#{hub.id}"} current={@current_page} />
          <% end %>
        <% end %>

        <.sidebar_link title="Add Organization" icon="add-line" to={~p"/hub"} current={@current_page} />
      </div>
    </div>
    """
  end

  defp sidebar_link_text_color(to, current) when to == current, do: "text-white"
  defp sidebar_link_text_color(_to, _current), do: "text-gray-400"

  defp sidebar_link_border_color(to, current) when to == current, do: "border-white"
  defp sidebar_link_border_color(_to, _current), do: "border-transparent"

  defp hub_connection_link_opts(%{provider: hub}, to, current) do
    text_color = sidebar_link_text_color(to, current)
    border_color = sidebar_link_border_color(to, current)

    class =
      "h-7 flex items-center hover:text-white #{text_color} border-l-4 #{border_color} hover:border-white"

    if message = Provider.connection_status(hub) do
      [
        id: "hub-#{hub.id}",
        navigate: to,
        "data-tooltip": message,
        class: "tooltip right " <> class
      ]
    else
      [id: "hub-#{hub.id}", navigate: to, class: class]
    end
  end

  @doc """
  Renders page title.

  ## Examples

      <.title text="Learn" />

  """
  attr :text, :string, default: nil
  attr :back_navigate, :string, default: nil

  slot :inner_block

  def title(assigns) do
    if assigns.text == nil and assigns.inner_block == [] do
      raise ArgumentError, "should pass at least text attribute or an inner block"
    end

    ~H"""
    <div class="relative">
      <div
        :if={@back_navigate}
        class="hidden md:flex absolute top-0 bottom-0 left-0 transform -translate-x-full"
      >
        <.link navigate={@back_navigate}>
          <.remix_icon icon="arrow-left-line" class="align-middle mr-2 text-2xl text-gray-800" />
        </.link>
      </div>
      <h1 class="text-2xl text-gray-800 font-medium">
        <%= if @inner_block != [] do %>
          <%= render_slot(@inner_block) %>
        <% else %>
          <%= @text %>
        <% end %>
      </h1>
    </div>
    """
  end

  @doc """
  Topbar for showing pinned, page-specific messages.
  """
  attr :variant, :string, default: "info", values: ~w(warning info error)
  slot :inner_block, required: true

  def topbar(assigns) do
    ~H"""
    <div class={["px-2 py-2 text-sm text-center", topbar_class(@variant)]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  defp topbar_class("warning"), do: "bg-yellow-200 text-gray-900"
  defp topbar_class("info"), do: "bg-blue-200 text-gray-900"
  defp topbar_class("error"), do: "bg-red-200 text-gray-900"

  @doc """
  Returns an inline script to inject in dev mode.

  The main JS file is loaded asynchronously as a module, so we inline
  the live reloader listener to make sure it is already registered
  when the event is dispatched.
  """
  if Mix.env() == :dev do
    def dev_script(assigns) do
      ~H"""
      <script type="text/javascript">
        window.addEventListener(
          "phx:live_reload:attached",
          ({ detail: reloader }) => {
            // Enable server log streaming to client. Disable with reloader.disableServerLogs()
            // reloader.enableServerLogs();

            // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
            //
            //   * click with "c" key pressed to open at caller location
            //   * click with "d" key pressed to open at function component definition location
            //
            let keyDown;
            window.addEventListener("keydown", (event) => (keyDown = event.key));
            window.addEventListener("keyup", (event) => (keyDown = null));
            window.addEventListener(
              "click",
              (event) => {
                if (keyDown === "c") {
                  event.preventDefault();
                  event.stopImmediatePropagation();
                  reloader.openEditorAtCaller(event.target);
                } else if (keyDown === "d") {
                  event.preventDefault();
                  event.stopImmediatePropagation();
                  reloader.openEditorAtDef(event.target);
                }
              },
              true,
            );

            window.liveReloader = reloader;
          },
        );
      </script>
      """
    end
  else
    def dev_script(assigns), do: ~H""
  end
end
