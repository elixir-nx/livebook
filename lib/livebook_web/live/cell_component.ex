defmodule LivebookWeb.CellComponent do
  use LivebookWeb, :live_component

  def render(assigns) do
    ~L"""
    <div class="flex flex-col relative"
      data-element="cell"
      id="cell-<%= @cell.id %>"
      phx-hook="Cell"
      data-cell-id="<%= @cell.id %>"
      data-type="<%= @cell.type %>">
      <%= render_cell_content(assigns) %>
    </div>
    """
  end

  def render_cell_content(%{cell: %{type: :markdown}} = assigns) do
    ~L"""
    <div class="mb-1 flex items-center justify-end">
      <div class="relative z-10 flex items-center justify-end space-x-2" data-element="actions">
        <span class="tooltip top" aria-label="Edit content">
          <button class="icon-button" data-element="enable-insert-mode-button">
            <%= remix_icon("pencil-line", class: "text-xl") %>
          </button>
        </span>
        <span class="tooltip top" aria-label="Move up">
          <button class="icon-button"
            phx-click="move_cell"
            phx-value-cell_id="<%= @cell.id %>"
            phx-value-offset="-1">
            <%= remix_icon("arrow-up-s-line", class: "text-xl") %>
          </button>
        </span>
        <span class="tooltip top" aria-label="Move down">
          <button class="icon-button"
            phx-click="move_cell"
            phx-value-cell_id="<%= @cell.id %>"
            phx-value-offset="1">
            <%= remix_icon("arrow-down-s-line", class: "text-xl") %>
          </button>
        </span>
        <span class="tooltip top" aria-label="Delete">
          <button class="icon-button"
            phx-click="delete_cell"
            phx-value-cell_id="<%= @cell.id %>">
            <%= remix_icon("delete-bin-6-line", class: "text-xl") %>
          </button>
        </span>
      </div>
    </div>

    <div class="flex">
      <div class="w-1 rounded-lg relative -left-3" data-element="cell-focus-indicator">
      </div>
      <div class="w-full">
        <div class="pb-4" data-element="editor-box">
          <%= render_editor(assigns) %>
        </div>

        <div class="markdown" data-element="markdown-container" id="markdown-container-<%= @cell.id %>" phx-update="ignore">
          <%= render_markdown_content_placeholder(@cell.source) %>
        </div>
      </div>
    </div>
    """
  end

  def render_cell_content(%{cell: %{type: :elixir}} = assigns) do
    ~L"""
    <div class="mb-1 flex justify-between">
      <div class="relative z-10 flex items-center justify-end space-x-2" data-element="actions" data-primary>
        <%= if @cell_info.evaluation_status == :ready do %>
          <button class="text-gray-600 hover:text-gray-800 focus:text-gray-800 flex space-x-1 items-center"
            phx-click="queue_cell_evaluation"
            phx-value-cell_id="<%= @cell.id %>">
            <%= remix_icon("play-circle-fill", class: "text-xl") %>
            <span class="text-sm font-medium">
              <%= if(@cell_info.validity_status == :evaluated, do: "Reevaluate", else: "Evaluate") %>
            </span>
          </button>
        <% else %>
          <button class="text-gray-600 hover:text-gray-800 focus:text-gray-800 flex space-x-1 items-center"
            phx-click="cancel_cell_evaluation"
            phx-value-cell_id="<%= @cell.id %>">
            <%= remix_icon("stop-circle-fill", class: "text-xl") %>
            <span class="text-sm font-medium">
              Stop
            </span>
          </button>
        <% end %>
      </div>
      <div class="relative z-10 flex items-center justify-end space-x-2" data-element="actions">
        <span class="tooltip top" aria-label="Cell settings">
          <%= live_patch to: Routes.session_path(@socket, :cell_settings, @session_id, @cell.id), class: "icon-button" do %>
            <%= remix_icon("list-settings-line", class: "text-xl") %>
          <% end %>
        </span>
        <span class="tooltip top" aria-label="Move up">
          <button class="icon-button"
            phx-click="move_cell"
            phx-value-cell_id="<%= @cell.id %>"
            phx-value-offset="-1">
            <%= remix_icon("arrow-up-s-line", class: "text-xl") %>
          </button>
        </span>
        <span class="tooltip top" aria-label="Move down">
          <button class="icon-button"
            phx-click="move_cell"
            phx-value-cell_id="<%= @cell.id %>"
            phx-value-offset="1">
            <%= remix_icon("arrow-down-s-line", class: "text-xl") %>
          </button>
        </span>
        <span class="tooltip top" aria-label="Delete">
          <button class="icon-button"
            phx-click="delete_cell"
            phx-value-cell_id="<%= @cell.id %>">
            <%= remix_icon("delete-bin-6-line", class: "text-xl") %>
          </button>
        </span>
      </div>
    </div>

    <div class="flex">
      <div class="w-1 rounded-lg relative -left-3" data-element="cell-focus-indicator">
      </div>
      <div class="w-full">
        <%= render_editor(assigns) %>

        <%= if @cell.outputs != [] do %>
          <div class="mt-2">
            <%= render_outputs(assigns) %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_editor(assigns) do
    ~L"""
    <div class="py-3 rounded-lg overflow-hidden bg-editor relative">
      <div
        id="editor-container-<%= @cell.id %>"
        data-element="editor-container"
        phx-update="ignore">
        <%= render_editor_content_placeholder(@cell.source) %>
      </div>

      <%= if @cell.type == :elixir do %>
        <div class="absolute bottom-2 right-2">
          <%= live_component @socket, LivebookWeb.CellStatusComponent,
                id: @cell.id,
                evaluation_status: @cell_info.evaluation_status,
                validity_status: @cell_info.validity_status,
                changed: @cell_info.digest != @cell_info.evaluation_digest %>
        </div>
      <% end %>
    </div>
    """
  end

  # The whole page has to load and then hooks are mounded.
  # There may be a tiny delay before the markdown is rendered
  # or and editors are mounted, so show neat placeholders immediately.

  defp render_markdown_content_placeholder("" = _content) do
    assigns = %{}

    ~L"""
    <div class="h-4"></div>
    """
  end

  defp render_markdown_content_placeholder(_content) do
    assigns = %{}

    ~L"""
    <div class="max-w-2xl w-full animate-pulse">
      <div class="flex-1 space-y-4">
        <div class="h-4 bg-gray-200 rounded-lg w-3/4"></div>
        <div class="h-4 bg-gray-200 rounded-lg"></div>
        <div class="h-4 bg-gray-200 rounded-lg w-5/6"></div>
      </div>
    </div>
    """
  end

  defp render_editor_content_placeholder("" = _content) do
    assigns = %{}

    ~L"""
    <div class="h-4"></div>
    """
  end

  defp render_editor_content_placeholder(_content) do
    assigns = %{}

    ~L"""
    <div class="px-8 max-w-2xl w-full animate-pulse">
      <div class="flex-1 space-y-4 py-1">
        <div class="h-4 bg-gray-500 rounded-lg w-3/4"></div>
        <div class="h-4 bg-gray-500 rounded-lg"></div>
        <div class="h-4 bg-gray-500 rounded-lg w-5/6"></div>
      </div>
    </div>
    """
  end

  defp render_outputs(assigns) do
    ~L"""
    <div class="flex flex-col rounded-lg border border-gray-200 divide-y divide-gray-200 font-editor">
      <%= for {output, index} <- @cell.outputs |> Enum.reverse() |> Enum.with_index(), output != :ignored do %>
        <div class="p-4">
          <%= render_output(output, "#{@cell.id}-output#{index}") %>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_output(output, id) when is_binary(output) do
    # Captured output usually has a trailing newline that we can ignore,
    # because each line is itself a block anyway.
    output = String.replace_suffix(output, "\n", "")
    lines = ansi_to_html_lines(output)
    assigns = %{lines: lines, id: id}

    ~L"""
    <div id="<%= @id %>" phx-hook="VirtualizedLines" data-max-height="300" data-follow="true">
      <div data-template class="hidden"><%= for line <- @lines do %><div><%= raw line %></div><% end %></div>
      <div data-content phx-update="ignore" class="overflow-auto whitespace-pre text-gray-500 tiny-scrollbar"></div>
    </div>
    """
  end

  defp render_output({:inspect, inspected}, id) do
    lines = ansi_to_html_lines(inspected)
    assigns = %{lines: lines, id: id}

    ~L"""
    <div id="<%= @id %>" phx-hook="VirtualizedLines" data-max-height="300" data-follow="false">
      <div data-template class="hidden"><%= for line <- @lines do %><div><%= raw line %></div><% end %></div>
      <div data-content phx-update="ignore" class="overflow-auto whitespace-pre text-gray-500 tiny-scrollbar"></div>
    </div>
    """
  end

  defp render_output({:error, formatted}, _id) do
    assigns = %{formatted: formatted}

    ~L"""
    <div class="overflow-auto whitespace-pre text-red-600 tiny-scrollbar"><%= @formatted %></div>
    """
  end

  defp ansi_to_html_lines(string) do
    string
    |> ansi_string_to_html(
      # Make sure every line is styled separately,
      # so tht later we can safely split the whole HTML
      # into valid HTML lines.
      renderer: fn style, content ->
        content
        |> IO.iodata_to_binary()
        |> String.split("\n")
        |> Enum.map(&[~s{<span style="#{style}">}, &1, ~s{</span>}])
        |> Enum.intersperse("\n")
      end
    )
    |> Phoenix.HTML.safe_to_string()
    |> String.split("\n")
  end
end
