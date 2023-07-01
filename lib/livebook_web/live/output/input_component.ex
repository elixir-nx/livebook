defmodule LivebookWeb.Output.InputComponent do
  use LivebookWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok, assign(socket, local: false, counter: 0)}
  end

  @impl true
  def update(%{event: :change, value: value} = assigns, socket) do
    {:ok, handle_change(socket, value)}
  end

  def update(%{attrs: %{type: :datetime}} = assigns, socket) do
    value = assigns.input_values[assigns.attrs.id]

    socket =
      socket
      |> assign(assigns)
      |> assign(value: value)
      |> push_event("datetime_input_change:#{assigns.id}", %{datetime: value})

    {:ok, socket}
  end

  def update(%{attrs: %{type: :time}} = assigns, socket) do
    value = assigns.input_values[assigns.attrs.id]

    socket =
      socket
      |> assign(assigns)
      |> assign(value: value)
      |> push_event("time_input_change:#{assigns.id}", %{time: value})

    {:ok, socket}
  end

  def update(assigns, socket) do
    value = assigns.input_values[assigns.attrs.id]

    socket =
      socket
      |> assign(assigns)
      |> assign(value: value)

    {:ok, socket}
  end

  @impl true
  def render(%{attrs: %{type: :image}} = assigns) do
    ~H"""
    <div id={"#{@id}-form-#{@counter}"}>
      <.label>
        <%= @attrs.label %>
      </.label>
      <.live_component
        module={LivebookWeb.Output.ImageInputComponent}
        id={"#{@id}-input"}
        input_component_id={@id}
        value={@value}
        height={@attrs.size && elem(@attrs.size, 0)}
        width={@attrs.size && elem(@attrs.size, 1)}
        format={@attrs.format}
        fit={@attrs.fit}
      />
    </div>
    """
  end

  def render(%{attrs: %{type: :audio}} = assigns) do
    ~H"""
    <div id={"#{@id}-form-#{@counter}"}>
      <.label>
        <%= @attrs.label %>
      </.label>
      <.live_component
        module={LivebookWeb.Output.AudioInputComponent}
        id={"#{@id}-input"}
        input_component_id={@id}
        value={@value}
        format={@attrs.format}
        sampling_rate={@attrs.sampling_rate}
      />
    </div>
    """
  end

  def render(%{attrs: %{type: :file}} = assigns) do
    ~H"""
    <div id={"#{@id}-form-#{@counter}"}>
      <.label>
        <%= @attrs.label %>
      </.label>
      <.live_component
        module={LivebookWeb.Output.FileInputComponent}
        id={"#{@id}-input"}
        input_component_id={@id}
        value={@value}
        accept={@attrs.accept}
        input_id={@attrs.id}
        session_pid={@session_pid}
        client_id={@client_id}
        local={@local}
      />
    </div>
    """
  end

  def render(%{attrs: %{type: :datetime}} = assigns) do
    ~H"""
    <div id={"#{@id}-form-#{@counter}"}>
      <.label>
        <%= @attrs.label %>
      </.label>
      <input
        id={@id}
        type="datetime-local"
        data-el-input
        class="input w-auto invalid:input--error"
        name="html_value"
        data-utc-value={@value && Calendar.strftime(@value, "%Y-%m-%dT%H:%M")}
        phx-hook="UtcDateTimeInput"
        phx-debounce="blur"
        phx-target={@myself}
        min={@attrs.min && Calendar.strftime(@attrs.min, "%Y-%m-%dT%H:%M")}
        max={@attrs.max && Calendar.strftime(@attrs.max, "%Y-%m-%dT%H:%M")}
        step="60"
        autocomplete="off"
      />
    </div>
    """
  end

  def render(%{attrs: %{type: :time}} = assigns) do
    ~H"""
    <div id={"#{@id}-form-#{@counter}"}>
      <.label>
        <%= @attrs.label %>
      </.label>
      <input
        id={@id}
        type="time"
        data-el-input
        class="input w-auto invalid:input--error"
        name="html_value"
        date-utc-value={@value}
        phx-hook="UtcDateTimeInput"
        phx-update="ignore"
        phx-debounce="blur"
        phx-target={@myself}
        min={@attrs.min}
        max={@attrs.max}
        step="60"
        autocomplete="off"
      />
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <form id={"#{@id}-form-#{@counter}"} phx-change="change" phx-submit="submit" phx-target={@myself}>
      <.label>
        <%= @attrs.label %>
      </.label>
      <.input_output id={"#{@id}-input"} attrs={@attrs} value={@value} myself={@myself} />
    </form>
    """
  end

  defp input_output(%{attrs: %{type: :select}} = assigns) do
    ~H"""
    <select data-el-input class="input w-60" name="html_value">
      <option
        :for={{{key, label}, idx} <- Enum.with_index(@attrs.options)}
        value={idx}
        selected={@value == key}
      >
        <%= label %>
      </option>
    </select>
    """
  end

  defp input_output(%{attrs: %{type: :checkbox}} = assigns) do
    ~H"""
    <div class="mt-1">
      <.switch_field data-el-input name="html_value" value={@value} />
    </div>
    """
  end

  defp input_output(%{attrs: %{type: :range}} = assigns) do
    ~H"""
    <div class="flex items-center space-x-2">
      <div><%= @attrs.min %></div>
      <input
        type="range"
        data-el-input
        class="input-range"
        name="html_value"
        value={@value}
        phx-debounce="blur"
        phx-target={@myself}
        spellcheck="false"
        autocomplete="off"
        min={@attrs.min}
        max={@attrs.max}
        step={@attrs.step}
      />
      <div><%= @attrs.max %></div>
    </div>
    """
  end

  defp input_output(%{attrs: %{type: :textarea}} = assigns) do
    ~H"""
    <textarea
      id={@id}
      data-el-input
      class={["input min-h-[38px] max-h-[300px] tiny-scrollbar", @attrs[:monospace] && "font-mono"]}
      name="html_value"
      phx-hook="TextareaAutosize"
      phx-debounce="blur"
      phx-target={@myself}
      spellcheck="false"
    ><%= [?\n, @value] %></textarea>
    """
  end

  defp input_output(%{attrs: %{type: :password}} = assigns) do
    ~H"""
    <.with_password_toggle id={"#{@id}-password-toggle"}>
      <input
        type="password"
        data-el-input
        class="input w-auto bg-gray-50"
        name="html_value"
        value={@value}
        phx-debounce="blur"
        phx-target={@myself}
        spellcheck="false"
        autocomplete="off"
      />
    </.with_password_toggle>
    """
  end

  defp input_output(%{attrs: %{type: :date}} = assigns) do
    ~H"""
    <input
      type="date"
      data-el-input
      class="input w-auto invalid:input--error"
      name="html_value"
      value={@value}
      phx-debounce="blur"
      phx-target={@myself}
      min={@attrs.min}
      max={@attrs.max}
      step={@attrs.step}
      autocomplete="off"
    />
    """
  end

  defp input_output(%{attrs: %{type: type}} = assigns)
       when type in [:number, :color, :url, :text] do
    ~H"""
    <input
      type={html_input_type(@attrs.type)}
      data-el-input
      class="input w-auto invalid:input--error"
      name="html_value"
      value={to_string(@value)}
      phx-debounce="blur"
      phx-target={@myself}
      spellcheck="false"
      autocomplete="off"
    />
    """
  end

  defp input_output(assigns) do
    ~H"""
    <div class="text-red-600">
      Unknown input type <%= @attrs.type %>
    </div>
    """
  end

  defp html_input_type(:number), do: "number"
  defp html_input_type(:color), do: "color"
  defp html_input_type(:url), do: "url"
  defp html_input_type(:text), do: "text"

  @impl true
  def handle_event("change", %{"html_value" => html_value}, socket) do
    case parse(html_value, socket.assigns.attrs) do
      {:ok, value} ->
        {:noreply, handle_change(socket, value)}

      :error ->
        # Force the current value
        {:noreply, update(socket, :counter, &(&1 + 1))}
    end
  end

  def handle_event("submit", %{"html_value" => html_value}, socket) do
    case parse(html_value, socket.assigns.attrs) do
      {:ok, value} ->
        socket = handle_change(socket, value)
        send(self(), {:queue_bound_cells_evaluation, socket.assigns.attrs.id})
        {:noreply, socket}

      :error ->
        {:noreply, socket}
    end
  end

  defp handle_change(socket, value) do
    prev_value = socket.assigns.value

    socket = assign(socket, value: value)

    if value != prev_value do
      report_change(socket)
    end

    socket
  end

  defp report_change(%{assigns: assigns} = socket) do
    send(self(), {:set_input_values, [{assigns.attrs.id, assigns.value}], assigns.local})

    unless assigns.local do
      report_event(socket, assigns.value)
    end
  end

  defp parse(html_value, %{type: :text}) do
    {:ok, html_value}
  end

  defp parse(html_value, %{type: :textarea}) do
    # The browser may normalize newlines to \r\n, but we prefer just \n
    value = String.replace(html_value, "\r\n", "\n")
    {:ok, value}
  end

  defp parse(html_value, %{type: :password}) do
    {:ok, html_value}
  end

  defp parse(html_value, %{type: :number}) do
    if html_value == "" do
      {:ok, nil}
    else
      case Integer.parse(html_value) do
        {number, ""} ->
          {:ok, number}

        _ ->
          {number, ""} = Float.parse(html_value)
          {:ok, number}
      end
    end
  end

  defp parse(html_value, %{type: :url}) do
    cond do
      html_value == "" -> {:ok, nil}
      Livebook.Utils.valid_url?(html_value) -> {:ok, html_value}
      true -> :error
    end
  end

  defp parse(html_value, %{type: :select, options: options}) do
    selected_idx = String.to_integer(html_value)

    options
    |> Enum.with_index()
    |> Enum.find_value(fn {{key, _label}, idx} ->
      idx == selected_idx && {:ok, key}
    end)
  end

  defp parse(html_value, %{type: :checkbox}) do
    {:ok, html_value == "true"}
  end

  defp parse(html_value, %{type: :range}) do
    {number, ""} = Float.parse(html_value)
    {:ok, number}
  end

  defp parse(html_value, %{type: :color}) do
    {:ok, html_value}
  end

  defp parse(html_value, %{type: :datetime}) do
    case NaiveDateTime.from_iso8601(html_value) do
      {:ok, datetime} -> {:ok, NaiveDateTime.truncate(datetime, :second)}
      {:error, _error} -> :error
    end
  end

  defp parse(html_value, %{type: :time}) do
    case Time.from_iso8601(html_value) do
      {:ok, time} -> {:ok, Time.truncate(time, :second)}
      {:error, _error} -> :error
    end
  end

  defp parse(html_value, %{type: :date}) do
    case Date.from_iso8601(html_value) do
      {:ok, date} -> {:ok, date}
      {:error, _error} -> :error
    end
  end

  defp report_event(socket, value) do
    topic = socket.assigns.attrs.ref
    event = %{value: value, origin: socket.assigns.client_id, type: :change}
    send(socket.assigns.attrs.destination, {:event, topic, event})
  end
end
