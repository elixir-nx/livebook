defmodule LiveBookWeb.Section do
  use LiveBookWeb, :live_component

  def render(assigns) do
    ~L"""
    <div class="<%= if not @selected, do: "hidden" %>">
      <div class="flex justify-between items-center">
        <div class="flex space-x-2 items-center text-gray-600">
          <%= Icons.svg(:chevron_right, class: "h-8") %>
          <h2 class="text-3xl" contenteditable spellcheck="false"><%= @section.name %></h2>
        </div>
        <div class="flex space-x-2 items-center">
          <button phx-click="delete_section" phx-value-section_id="<%= @section.id %>" class="text-gray-600 hover:text-current">
            <%= Icons.svg(:trash, class: "h-6") %>
          </button>
        </div>
      </div>
      <div class="container py-4">
        <div class="flex flex-col space-y-2">
          <%= live_component @socket, LiveBookWeb.InsertCellActions, section_id: @section.id, index: 0, id: "insert-#{@section.id}-0" %>
          <%= for {cell, index} <- Enum.with_index(@section.cells) do %>
            <%= live_component @socket, LiveBookWeb.Cell, cell: cell, id: "cell-#{cell.id}", focused: cell.id == @focused_cell_id %>
            <%= live_component @socket, LiveBookWeb.InsertCellActions, section_id: @section.id, index: index + 1, id: "insert-#{@section.id}-#{index + 1}" %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
