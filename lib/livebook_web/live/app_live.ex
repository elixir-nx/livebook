defmodule LivebookWeb.AppLive do
  use LivebookWeb, :live_view

  alias Livebook.Session
  alias Livebook.Notebook
  alias Livebook.Notebook.Cell

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Livebook.Apps.fetch_session_by_slug(slug) do
      {:ok, %{pid: session_pid, id: session_id}} ->
        {data, client_id} =
          if connected?(socket) do
            {data, client_id} =
              Session.register_client(session_pid, self(), socket.assigns.current_user)

            Session.subscribe(session_id)

            {data, client_id}
          else
            data = Session.get_data(session_pid)
            {data, nil}
          end

        session = Session.get_by_pid(session_pid)

        {:ok,
         socket
         |> assign(
           slug: slug,
           session: session,
           page_title: get_page_title(data.notebook.name),
           client_id: client_id,
           data_view: data_to_view(data)
         )
         |> assign_private(data: data)}

      :error ->
        {:ok, redirect(socket, to: Routes.home_path(socket, :page))}
    end
  end

  # Puts the given assigns in `socket.private`,
  # to ensure they are not used for rendering.
  defp assign_private(socket, assigns) do
    Enum.reduce(assigns, socket, fn {key, value}, socket ->
      put_in(socket.private[key], value)
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grow overflow-y-auto relative" data-el-notebook>
      <div
        class="w-full max-w-screen-lg px-4 sm:pl-8 sm:pr-16 md:pl-16 pt-4 sm:py-5 mx-auto"
        data-el-notebook-content
      >
        <div data-el-js-view-iframes phx-update="ignore" id="js-view-iframes"></div>
        <div class="flex items-center pb-4 mb-2 space-x-4 border-b border-gray-200">
          <h1 class="text-3xl font-semibold text-gray-800">
            <%= @data_view.notebook_name %>
          </h1>
        </div>
        <%= if @data_view.app_status == :booting do %>
          <div class="flex items-center space-x-2">
            <span class="relative flex h-3 w-3">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-blue-400 opacity-75">
              </span>
              <span class="relative inline-flex rounded-full h-3 w-3 bg-blue-500"></span>
            </span>
            <div class="text-gray-700 font-medium">
              Booting
            </div>
          </div>
        <% end %>
        <%= if @data_view.app_status == :error do %>
          <div class="flex items-center space-x-2">
            <span class="relative flex h-3 w-3">
              <span class="relative inline-flex rounded-full h-3 w-3 bg-red-500"></span>
            </span>
            <div class="text-gray-700 font-medium">
              Error
            </div>
          </div>
        <% end %>
        <%= if @data_view.app_status in [:running, :shutting_down] do %>
          <div class="pt-4 flex flex-col space-y-6" data-el-outputs-container id="outputs">
            <%= for output_view <- Enum.reverse(@data_view.output_views) do %>
              <div>
                <LivebookWeb.Output.outputs
                  outputs={[output_view.output]}
                  dom_id_map={%{}}
                  socket={@socket}
                  session_id={@session.id}
                  session_pid={@session.pid}
                  client_id={@client_id}
                  input_values={output_view.input_values}
                />
              </div>
            <% end %>
          </div>
          <div style="height: 80vh"></div>
        <% end %>
      </div>
    </div>
    """
  end

  defp get_page_title(notebook_name) do
    "Livebook - #{notebook_name}"
  end

  @impl true
  def handle_info({:operation, operation}, socket) do
    {:noreply, handle_operation(socket, operation)}
  end

  def handle_info({:set_input_values, values, _local = true}, socket) do
    socket =
      Enum.reduce(values, socket, fn {input_id, value}, socket ->
        operation = {:set_input_value, socket.assigns.client_id, input_id, value}
        handle_operation(socket, operation)
      end)

    {:noreply, socket}
  end

  def handle_info(:session_closed, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Session has been closed")
     |> push_redirect(to: Routes.home_path(socket, :page))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp handle_operation(socket, operation) do
    case Session.Data.apply_operation(socket.private.data, operation) do
      {:ok, data, _actions} ->
        socket
        |> assign_private(data: data)
        |> assign(
          data_view:
            update_data_view(socket.assigns.data_view, socket.private.data, data, operation)
        )

      :error ->
        socket
    end
  end

  defp update_data_view(data_view, _prev_data, data, operation) do
    case operation do
      # See LivebookWeb.SessionLive for more details
      {:add_cell_evaluation_output, _client_id, _cell_id,
       {:frame, _outputs, %{type: type, ref: ref}}}
      when type != :default ->
        for {idx, {:frame, frame_outputs, _}} <- Notebook.find_frame_outputs(data.notebook, ref) do
          send_update(LivebookWeb.Output.FrameComponent,
            id: "output-#{idx}",
            outputs: frame_outputs,
            update_type: type
          )
        end

        data_view

      _ ->
        data_to_view(data)
    end
  end

  defp data_to_view(data) do
    %{
      notebook_name: data.notebook.name,
      output_views:
        for(
          output <- visible_outputs(data.notebook),
          do: %{
            output: output,
            input_values: input_values_for_output(output, data)
          }
        ),
      app_status: data.app_data.status
    }
  end

  defp input_values_for_output(output, data) do
    input_ids = for attrs <- Cell.find_inputs_in_output(output), do: attrs.id
    Map.take(data.input_values, input_ids)
  end

  defp visible_outputs(notebook) do
    for section <- Enum.reverse(notebook.sections),
        cell <- Enum.reverse(section.cells),
        Cell.evaluable?(cell),
        output <- filter_outputs(cell.outputs),
        do: output
  end

  defp filter_outputs(outputs) do
    for output <- outputs, output = filter_output(output), do: output
  end

  defp filter_output({idx, output})
       when elem(output, 0) in [:markdown, :image, :js, :control],
       do: {idx, output}

  defp filter_output({idx, {:tabs, outputs, metadata}}) do
    outputs_with_labels =
      for {output, label} <- Enum.zip(outputs, metadata.labels),
          output = filter_output(output),
          do: {output, label}

    {outputs, labels} = Enum.unzip(outputs_with_labels)

    {idx, {:tabs, outputs, %{metadata | labels: labels}}}
  end

  defp filter_output({idx, {:grid, outputs, metadata}}) do
    outputs = filter_outputs(outputs)

    if outputs != [] do
      {idx, {:grid, outputs, metadata}}
    end
  end

  defp filter_output({idx, {:frame, outputs, metadata}}) do
    outputs = filter_outputs(outputs)
    {idx, {:frame, outputs, metadata}}
  end

  defp filter_output(_output), do: nil
end
