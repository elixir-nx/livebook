defmodule LivebookWeb.Output.TerminalTextComponent do
  use LivebookWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(modifiers: [], last_line: nil, last_html_line: nil, initialized: false)
     |> stream(:html_lines, [])}
  end

  @impl true
  def update(%{event: {:append, output}}, socket) do
    {:ok, append_text(socket, output.text)}
  end

  def update(assigns, socket) do
    {output, assigns} = Map.pop(assigns, :output)
    socket = assign(socket, assigns)

    if socket.assigns.initialized do
      # After initialization, output text may be pruned and updates
      # are sent as events instead
      {:ok, socket}
    else
      {:ok,
       socket
       |> append_text(output.text)
       |> assign(:initialized, true)}
    end
  end

  defp append_text(socket, text) do
    text = (socket.assigns.last_line || "") <> text

    text = Livebook.Notebook.normalize_terminal_text(text)

    last_line =
      case Livebook.Utils.split_at_last_occurrence(text, "\n") do
        :error -> text
        {:ok, _, last_line} -> last_line
      end

    {html_lines, modifiers} =
      LivebookWeb.ANSIHelpers.ansi_string_to_html_lines_step(text, socket.assigns.modifiers)

    {html_lines, [last_html_line]} = Enum.split(html_lines, -1)

    stream_items =
      for html_line <- html_lines, do: %{id: Livebook.Utils.random_long_id(), html: html_line}

    socket = stream(socket, :html_lines, stream_items)

    assign(socket,
      last_html_line: last_html_line,
      last_line: last_line,
      modifiers: modifiers
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="relative group/root"
      phx-hook="VirtualizedLines"
      data-p-max-height={hook_prop(300)}
      data-p-max-height-amplified={hook_prop(600)}
      data-p-follow={hook_prop(true)}
      data-p-max-lines={hook_prop(Livebook.Notebook.max_terminal_lines())}
      data-p-ignore-trailing-empty-line={hook_prop(true)}
    >
      <%!--
      Note 1: We add a newline to each element, so that multiple lines can be copied properly as element.textContent
      Note 2: We glue the tags together to avoid inserting unintended whitespace
      --%>
      <div data-template class="hidden" id={"#{@id}-template"} phx-no-format><div
        id={"#{@id}-template-append"}
        phx-update="stream"
      ><div :for={{dom_id, html_line} <- @streams.html_lines} id={dom_id} data-line>{[
        html_line.html,
        "\n"
      ]}</div></div><div data-line>{@last_html_line}</div></div>
      <div
        data-content
        class="overflow-auto whitespace-pre font-editor text-gray-500 tiny-scrollbar"
        id={"#{@id}-content"}
        phx-update="ignore"
      >
      </div>
      <div class="absolute right-2 top-0 z-10 invisible group-hover/root:visible">
        <.icon_button phx-click={JS.dispatch("lb:clipcopy", to: "##{@id}-template")}>
          <.remix_icon icon="clipboard-line" />
        </.icon_button>
      </div>
    </div>
    """
  end
end
