defmodule LivebookWeb.LayoutHelpers do
  use LivebookWeb, :html

  import LivebookWeb.UserHelpers

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

      <div class="flex flex-col justify-between h-full">
        <div class="flex flex-col">
          <div class="space-y-3">
            <div class="flex items-center mb-5">
              <.link navigate={~p"/"} class="flex items-center border-l-4 border-gray-900 group">
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
                v<%= Application.spec(:livebook, :vsn) %>
              </span>
            </div>
            <.sidebar_link title="Home" icon="home-6-line" to={~p"/"} current={@current_page} />
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
            phx-click={
              with_confirm(
                JS.push("shutdown"),
                title: "Shut Down",
                description: "Are you sure you want to shut down Livebook now?",
                confirm_text: "Shut Down",
                confirm_icon: "shut-down-line"
              )
            }
          >
            <.remix_icon icon="shut-down-line" class="text-lg leading-6 w-[56px] flex justify-center" />
            <span class="text-sm font-medium">
              Shut Down
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
    <.link {hub_connection_link_opts(@hub.provider, @to, @current)}>
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
    <div :if={Livebook.Config.feature_flag_enabled?(:hub)} id="hubs" class="flex flex-col mt-12">
      <div class="space-y-3">
        <div class="grid grid-cols-1 md:grid-cols-2 relative leading-6 mb-2">
          <small class="ml-5 font-medium text-gray-300 cursor-default">HUBS</small>
        </div>

        <%= for hub <- @hubs do %>
          <%= if Provider.connection_spec(hub.provider) do %>
            <.sidebar_hub_link_with_tooltip hub={hub} to={~p"/hub/#{hub.id}"} current={@current_page} />
          <% else %>
            <.sidebar_hub_link hub={hub} to={~p"/hub/#{hub.id}"} current={@current_page} />
          <% end %>
        <% end %>

        <.sidebar_link title="Add Hub" icon="add-line" to={~p"/hub"} current={@current_page} />
      </div>
    </div>
    """
  end

  defp sidebar_link_text_color(to, current) when to == current, do: "text-white"
  defp sidebar_link_text_color(_to, _current), do: "text-gray-400"

  defp sidebar_link_border_color(to, current) when to == current, do: "border-white"
  defp sidebar_link_border_color(_to, _current), do: "border-transparent"

  defp hub_connection_link_opts(hub, to, current) do
    text_color = sidebar_link_text_color(to, current)
    border_color = sidebar_link_border_color(to, current)

    class =
      "h-7 flex items-center hover:text-white #{text_color} border-l-4 #{border_color} hover:border-white"

    if tooltip = Provider.connection_error(hub) do
      [to: to, data_tooltip: tooltip, class: "tooltip right " <> class]
    else
      [to: to, class: class]
    end
  end

  @doc """
  Renders page title.

  ## Examples

      <.title text="Learn" />

  """
  attr :text, :string, required: true

  def title(assigns) do
    ~H"""
    <h1 class="text-2xl text-gray-800 font-medium">
      <%= @text %>
    </h1>
    """
  end
end
