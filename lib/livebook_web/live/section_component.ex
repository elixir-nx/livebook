defmodule LivebookWeb.SectionComponent do
  use LivebookWeb, :live_component

  def render(assigns) do
    ~L"""
    <div data-element="section" data-section-id="<%= @section.id %>">
      <div class="flex space-x-4 items-center" data-element="section-headline">
        <h2 class="flex-grow text-gray-800 font-semibold text-2xl px-1 -ml-1 rounded-lg border  border-transparent hover:border-blue-200 focus:border-blue-300"
          data-element="section-name"
          id="section-<%= @section.id %>-name"
          contenteditable
          spellcheck="false"
          phx-blur="set_section_name"
          phx-value-section_id="<%= @section.id %>"
          phx-hook="ContentEditable"
          data-update-attribute="phx-value-name"><%= @section.name %></h2>
          <%# ^ Note it's important there's no space between <h2> and </h2>
            because we want the content to exactly match @section.name. %>
        <div class="flex space-x-2 items-center" data-element="section-actions">
          <span class="tooltip top" aria-label="Delete">
            <button class="icon-button" phx-click="delete_section" phx-value-section_id="<%= @section.id %>" tabindex="-1">
              <%= remix_icon("delete-bin-6-line", class: "text-xl") %>
            </button>
          </span>
        </div>
      </div>
      <div class="container py-2">
        <div class="flex flex-col space-y-1">
          <%= for {cell, index} <- Enum.with_index(@section.cells) do %>
            <%= live_component @socket, LivebookWeb.InsertButtonsComponent,
                  id: "#{@section.id}:#{index}",
                  persistent: false,
                  section_id: @section.id,
                  insert_cell_index: index,
                  insert_section_index: nil %>
            <%= live_component @socket, LivebookWeb.CellComponent,
                  id: cell.id,
                  session_id: @session_id,
                  cell: cell,
                  cell_info: @cell_infos[cell.id] %>
          <% end %>
          <%= live_component @socket, LivebookWeb.InsertButtonsComponent,
                id: "#{@section.id}:last",
                persistent: @section.cells == [],
                section_id: @section.id,
                insert_cell_index: length(@section.cells),
                insert_section_index: @index + 1 %>
        </div>
      </div>
    </div>
    """
  end
end
