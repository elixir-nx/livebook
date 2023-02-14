defmodule LivebookWeb.Hub.Edit.PersonalComponent do
  use LivebookWeb, :live_component

  alias Livebook.Hubs.Personal

  @impl true
  def update(assigns, socket) do
    changeset = Personal.change_hub(assigns.hub)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(changeset: changeset)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"#{@id}-component"}>
      <div class="flex flex-col space-y-10">
        <div class="flex flex-col space-y-2">
          <h2 class="text-xl text-gray-800 font-medium pb-2 border-b border-gray-200">
            General
          </h2>

          <.form
            :let={f}
            id={@id}
            class="flex flex-col mt-4 space-y-4"
            for={@changeset}
            phx-submit="save"
            phx-change="validate"
            phx-target={@myself}
            phx-debounce="blur"
          >
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <.input_wrapper form={f} field={:hub_name} class="flex flex-col space-y-1">
                <div class="input-label">Name</div>
                <%= text_input(f, :hub_name, class: "input") %>
              </.input_wrapper>

              <.input_wrapper form={f} field={:hub_emoji} class="flex flex-col space-y-1">
                <div class="input-label">Emoji</div>
                <.emoji_input id="personal-emoji-input" form={f} field={:hub_emoji} />
              </.input_wrapper>
            </div>

            <%= submit("Update Hub",
              class: "button-base button-blue",
              phx_disable_with: "Updating...",
              disabled: not @changeset.valid?
            ) %>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("save", %{"personal" => params}, socket) do
    case Personal.update_hub(socket.assigns.hub, params) do
      {:ok, hub} ->
        {:noreply,
         socket
         |> put_flash(:success, "Hub updated successfully")
         |> push_redirect(to: Routes.hub_path(socket, :edit, hub.id))}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  def handle_event("validate", %{"personal" => attrs}, socket) do
    {:noreply, assign(socket, changeset: Personal.change_hub(socket.assigns.hub, attrs))}
  end
end
