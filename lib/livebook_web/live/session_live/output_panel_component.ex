defmodule LivebookWeb.SessionLive.OutputPanelComponent do
  use LivebookWeb, :live_component

  alias Livebook.Session

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(
        session: assigns.session,
        client_id: assigns.client_id,
        output_view: assigns.output_view
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="output-panel"
      class="grid grid-cols-12"
      phx-hook="OutputPanel"
      data-phx-target={@myself}
      data-el-output-panel-content
    >
      <.dropzone row={0} />
      <%= for {output_row, row_index} <- Enum.with_index(@output_view.rows) do %>
        <div
          :for={item <- output_row.items}
          class="relative group grid col-span-12"
          data-row-index={row_index}
          data-cell-id={item.cell_id}
          data-el-output-panel-item
        >
          <.output_options cell_id={item.cell_id} myself={@myself} />
          <LivebookWeb.Output.outputs
            outputs={item.outputs}
            dom_id_map={%{}}
            session_id={@session.id}
            session_pid={@session.pid}
            client_id={@client_id}
            cell_id={item.cell_id}
            input_views={item.input_views}
          />
        </div>
        <.dropzone row={row_index + 1} />
      <% end %>
    </div>
    """
  end

  defp dropzone(assigns) do
    ~H"""
    <div
      class="col-span-12 h-4 bg-white rounded-lg border-2 border-dashed border-gray-400"
      data-el-output-panel-row-drop-area
      data-drop-area-row-index={@row}
      id={"dropzone-row-#{@row}"}
      phx-hook="Dropzone"
    />
    """
  end

  defp output_options(assigns) do
    ~H"""
    <div class="absolute top-0 right-0 opacity-0 group-hover:opacity-100 transition-opacity duration-400">
      <div class="justify-center items-center shadow-lg border rounded border-gray-300 bg-white px-2">
        <ul class="flex space-x-4">
          <li class="cursor-move" draggable="true">
            <.remix_icon icon="draggable" />
          </li>
          <li class="cursor-pointer">
            <span class="tooltip top" data-tooltip="Remove output from Output Panel">
              <button
                class="icon-button"
                aria-label="remove output from output panel"
                phx-click="remove_output_from_output_panel"
                phx-value-cell_id={@cell_id}
                phx-target={@myself}
              >
                <.remix_icon icon="delete-bin-line" />
              </button>
            </span>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event(
        "handle_move_item_to_new_row",
        %{"cell_id" => cell_id, "row_num" => row_num},
        socket
      ) do
    Session.move_output_to_new_row(socket.assigns.session.pid, cell_id, row_num)
    {:noreply, socket}
  end

  def handle_event("remove_output_from_output_panel", %{"cell_id" => cell_id}, socket) do
    Session.remove_output_from_output_panel(socket.assigns.session.pid, cell_id)
    {:noreply, socket}
  end
end
