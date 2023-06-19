defmodule LivebookWeb.Hub.EditLive do
  use LivebookWeb, :live_view

  alias LivebookWeb.LayoutHelpers
  alias Livebook.Hubs
  alias Livebook.Hubs.Provider

  on_mount LivebookWeb.SidebarHook

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, hub: nil, type: nil, page_title: "Hub - Livebook", params: %{})}
  end

  @impl true
  def handle_params(params, _url, socket) do
    Hubs.subscribe([:secrets])
    hub = Hubs.fetch_hub!(params["id"])
    type = Provider.type(hub)

    {:noreply, assign(socket, hub: hub, type: type, params: params, counter: 0)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutHelpers.layout
      current_page={~p"/hub/#{@hub.id}"}
      current_user={@current_user}
      saved_hubs={@saved_hubs}
    >
      <div class="p-4 md:px-12 md:py-7 max-w-screen-md mx-auto">
        <.hub_component
          type={@type}
          hub={@hub}
          live_action={@live_action}
          params={@params}
          counter={@counter}
        />
      </div>
    </LayoutHelpers.layout>
    """
  end

  defp hub_component(%{type: "personal"} = assigns) do
    ~H"""
    <.live_component
      module={LivebookWeb.Hub.Edit.PersonalComponent}
      hub={@hub}
      params={@params}
      live_action={@live_action}
      counter={@counter}
      id="personal-form"
    />
    """
  end

  defp hub_component(%{type: "team"} = assigns) do
    ~H"""
    <.live_component
      module={LivebookWeb.Hub.Edit.TeamComponent}
      hub={@hub}
      live_action={@live_action}
      params={@params}
      id="team-form"
    />
    """
  end

  @impl true
  def handle_event("delete_hub", %{"id" => id}, socket) do
    on_confirm = fn socket ->
      Hubs.delete_hub(id)

      socket
      |> put_flash(:success, "Hub deleted successfully")
      |> push_navigate(to: "/")
    end

    {:noreply,
     confirm(socket, on_confirm,
       title: "Delete hub",
       description: "Are you sure you want to delete this hub?",
       confirm_text: "Delete",
       confirm_icon: "close-circle-line"
     )}
  end

  @impl true
  def handle_info({:secret_created, %{hub_id: id}}, %{assigns: %{hub: %{id: id}}} = socket) do
    {:noreply,
     socket
     |> increment_counter()
     |> put_flash(:success, "Secret created successfully")}
  end

  def handle_info({:secret_updated, %{hub_id: id}}, %{assigns: %{hub: %{id: id}}} = socket) do
    {:noreply,
     socket
     |> increment_counter()
     |> put_flash(:success, "Secret updated successfully")}
  end

  def handle_info({:secret_deleted, %{hub_id: id}}, %{assigns: %{hub: %{id: id}}} = socket) do
    {:noreply,
     socket
     |> increment_counter()
     |> put_flash(:success, "Secret deleted successfully")}
  end

  def handle_info(_message, socket) do
    {:noreply, socket}
  end

  defp increment_counter(socket), do: assign(socket, counter: socket.assigns.counter + 1)
end
