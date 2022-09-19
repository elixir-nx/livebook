defmodule LivebookWeb.Hub.NewLive do
  use LivebookWeb, :live_view

  alias LivebookWeb.{PageHelpers, LayoutHelpers}
  alias Phoenix.LiveView.JS

  on_mount LivebookWeb.SidebarHook

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, selected_type: nil, page_title: "Livebook - Hub")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutHelpers.layout
      socket={@socket}
      current_page={Routes.hub_path(@socket, :new)}
      current_user={@current_user}
      saved_hubs={@saved_hubs}
    >
      <div class="p-4 sm:px-8 md:px-16 sm:py-7 max-w-screen-md mx-auto space-y-8">
        <div>
          <PageHelpers.title text="Add Hub" socket={@socket} />
          <p class="mt-4 text-gray-700">
            Manage your Livebooks in the cloud with Hubs.
          </p>
        </div>

        <div class="flex flex-col space-y-4">
          <h2 class="text-xl text-gray-800 font-medium pb-2 border-b border-gray-200">
            1. Select your Hub service
          </h2>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.card_item id="fly" selected={@selected_type} title="Fly">
              <:logo>
                <%= Phoenix.HTML.raw(File.read!("static/images/fly.svg")) %>
              </:logo>
              <:headline>
                Deploy notebooks to your Fly account.
              </:headline>
            </.card_item>

            <.card_item id="enterprise" selected={@selected_type} title="Livebook Enterprise">
              <:logo>
                <img
                  src="/images/enterprise.png"
                  class="max-h-full max-w-[75%]"
                  alt="Livebook Enterprise logo"
                />
              </:logo>
              <:headline>
                Control access, manage secrets, and deploy notebooks within your team.
              </:headline>
            </.card_item>
          </div>
        </div>

        <%= if @selected_type do %>
          <div class="flex flex-col space-y-4">
            <h2 class="text-xl text-gray-800 font-medium pb-2 border-b border-gray-200">
              2. Configure your Hub
            </h2>

            <%= if @selected_type == "fly" do %>
              <.live_component module={LivebookWeb.Hub.New.FlyComponent} id="fly-form" />
            <% end %>

            <%= if @selected_type == "enterprise" do %>
              <div>
                Livebook Enterprise is currently in closed beta. If you want to learn more, <a
                  href="https://livebook.dev/#livebook-plans"
                  class="pointer-events-auto text-blue-600"
                  target="_blank"
                >click here</a>.
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </LayoutHelpers.layout>
    """
  end

  defp card_item(assigns) do
    ~H"""
    <div
      id={@id}
      class={"flex card-item flex-col " <> card_item_bg_color(@id, @selected)}
      phx-click={JS.push("select_type", value: %{value: @id})}
    >
      <div class="flex items-center justify-center card-item-logo p-6 border-2 rounded-t-2xl h-[150px]">
        <%= render_slot(@logo) %>
      </div>
      <div class="card-item-body px-6 py-4 rounded-b-2xl grow">
        <p class="text-gray-800 font-semibold cursor-pointer">
          <%= @title %>
        </p>

        <p class="mt-2 text-sm text-gray-600">
          <%= render_slot(@headline) %>
        </p>
      </div>
    </div>
    """
  end

  defp card_item_bg_color(id, selected) when id == selected, do: "selected"
  defp card_item_bg_color(_id, _selected), do: ""

  @impl true
  def handle_event("select_type", %{"value" => service}, socket) do
    {:noreply, assign(socket, selected_type: service)}
  end
end
