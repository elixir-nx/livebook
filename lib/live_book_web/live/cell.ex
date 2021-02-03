defmodule LiveBookWeb.Cell do
  use LiveBookWeb, :live_component

  alias LiveBookWeb.Utils

  def render(assigns) do
    ~L"""
    <div id="cell-<%= @cell.id %>"
         phx-hook="Cell"
         data-cell-id="<%= @cell.id %>"
         data-type="<%= @cell.type %>"
         data-focused="<%= @focused %>"
         data-expanded="<%= @expanded %>"
         class="flex flex-col relative mr-10 border-l-4 pl-4 -ml-4 border-blue-100 border-opacity-0 hover:border-opacity-100 <%= if @focused, do: "border-blue-300 border-opacity-100"%>">
      <%= render_cell_content(assigns) %>
    </div>
    """
  end

  def render_cell_content(%{cell: %{type: :markdown}} = assigns) do
    ~L"""
    <%= if @focused do %>
      <div class="flex flex-col items-center space-y-2 absolute right-0 top-0 -mr-10">
        <button phx-click="delete_cell" phx-value-cell_id="<%= @cell.id %>" class="text-gray-500 hover:text-current">
          <%= Icons.svg(:trash, class: "h-6") %>
        </button>
      </div>
    <% end %>

    <div class="<%= if @expanded, do: "mb-4", else: "hidden" %>">
      <%= render_editor(@cell, @cell_info) %>
    </div>

    <div class="markdown" data-markdown-container id="markdown-container-<%= @cell.id %>" phx-update="ignore">
      <%= render_markdown_content_placeholder(@cell.source) %>
    </div>
    """
  end

  def render_cell_content(%{cell: %{type: :elixir}} = assigns) do
    ~L"""
    <%= if @focused do %>
      <div class="flex flex-col items-center space-y-2 absolute right-0 top-0 -mr-10">
        <button phx-click="queue_cell_evaluation" phx-value-cell_id="<%= @cell.id %>" class="text-gray-500 hover:text-current">
          <%= Icons.svg(:play, class: "h-6") %>
        </button>
        <button phx-click="delete_cell" phx-value-cell_id="<%= @cell.id %>" class="text-gray-500 hover:text-current">
          <%= Icons.svg(:trash, class: "h-6") %>
        </button>
      </div>
    <% end %>

    <%= render_editor(@cell, @cell_info, show_status: true) %>

    <%= if @cell.outputs != [] do %>
      <div class="mt-2">
        <%= render_outputs(@cell.outputs) %>
      </div>
    <% end %>
    """
  end

  defp render_editor(cell, cell_info, opts \\ []) do
    show_status = Keyword.get(opts, :show_status, false)
    assigns = %{cell: cell, cell_info: cell_info, show_status: show_status}

    ~L"""
    <div class="py-3 rounded-md overflow-hidden bg-editor relative">
      <div id="editor-container-<%= @cell.id %>"
           data-editor-container
           phx-update="ignore">
        <%= render_editor_content_placeholder(@cell.source) %>
      </div>

      <%= if @show_status do %>
        <div class="absolute bottom-2 right-2 z-50">
          <%= render_cell_status(@cell_info) %>
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
        <div class="h-4 bg-gray-200 rounded w-3/4"></div>
        <div class="h-4 bg-gray-200 rounded"></div>
        <div class="h-4 bg-gray-200 rounded w-5/6"></div>
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
        <div class="h-4 bg-gray-500 rounded w-3/4"></div>
        <div class="h-4 bg-gray-500 rounded"></div>
        <div class="h-4 bg-gray-500 rounded w-5/6"></div>
      </div>
    </div>
    """
  end

  defp render_outputs(outputs) do
    assigns = %{outputs: outputs}

    ~L"""
    <div class="flex flex-col rounded-md border border-gray-200 divide-y divide-gray-200 text-sm">
      <%= for output <- Enum.reverse(@outputs) do %>
        <div class="p-4">
          <div class="max-h-80 overflow-auto tiny-scrollbar">
            <%= render_output(output) %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_output(output) when is_binary(output) do
    assigns = %{output: output}

    ~L"""
    <div class="whitespace-pre text-gray-500"><%= @output %></div>
    """
  end

  defp render_output({:ok, value}) do
    inspected = Utils.inspect_as_html(value, pretty: true, width: 140)

    assigns = %{inspected: inspected}

    ~L"""
    <div class="whitespace-pre text-gray-500 elixir-inspect"><%= @inspected %></div>
    """
  end

  defp render_output({:error, kind, error, stacktrace}) do
    formatted = Exception.format(kind, error, stacktrace)
    assigns = %{formatted: formatted}

    ~L"""
    <div class="whitespace-pre text-red-600"><%= @formatted %></div>
    """
  end

  defp render_cell_status(%{evaluation_status: :evaluating}) do
    assigns = %{}

    ~L"""
    <div class="flex items-center space-x-2">
      <div class="text-xs text-gray-400">Evaluating</div>
      <span class="flex relative h-3 w-3">
        <span class="animate-ping absolute inline-flex h-3 w-3 rounded-full bg-blue-300 opacity-75"></span>
        <span class="relative inline-flex rounded-full h-3 w-3 bg-blue-400"></span>
      </span>
    </div>
    """
  end

  defp render_cell_status(%{evaluation_status: :queued}) do
    assigns = %{}

    ~L"""
    <div class="flex items-center space-x-2">
      <div class="text-xs text-gray-400">Queued</div>
      <span class="flex relative h-3 w-3">
        <span class="animate-ping absolute inline-flex h-3 w-3 rounded-full bg-gray-400 opacity-75"></span>
        <span class="relative inline-flex rounded-full h-3 w-3 bg-gray-500"></span>
      </span>
    </div>
    """
  end

  defp render_cell_status(%{validity_status: :evaluated}) do
    assigns = %{}

    ~L"""
    <div class="flex items-center space-x-2">
      <div class="text-xs text-gray-400">Evaluated</div>
      <div class="h-3 w-3 rounded-full bg-green-400"></div>
    </div>
    """
  end

  defp render_cell_status(%{validity_status: :stale}) do
    assigns = %{}

    ~L"""
    <div class="flex items-center space-x-2">
      <div class="text-xs text-gray-400">Stale</div>
      <div class="h-3 w-3 rounded-full bg-yellow-200"></div>
    </div>
    """
  end

  defp render_cell_status(_), do: nil
end
