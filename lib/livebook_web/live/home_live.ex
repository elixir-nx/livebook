defmodule LivebookWeb.HomeLive do
  use LivebookWeb, :live_view

  import LivebookWeb.SessionHelpers
  import LivebookWeb.UserHelpers

  alias LivebookWeb.{SidebarHelpers, ExploreHelpers}
  alias Livebook.{Sessions, Session, LiveMarkdown, Notebook, FileSystem}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Livebook.PubSub, "tracker_sessions")
    end

    sessions = sort_sessions(Sessions.list_sessions(), "date")
    notebook_infos = Notebook.Explore.visible_notebook_infos() |> Enum.take(3)

    {:ok,
     assign(socket,
       file: Livebook.Config.default_dir(),
       file_info: %{exists: true, access: :read_write},
       sessions: sessions,
       notebook_infos: notebook_infos,
       order_by: "date"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-grow h-full">
      <SidebarHelpers.sidebar>
        <SidebarHelpers.break_item />
        <SidebarHelpers.link_item
          icon="settings-3-fill"
          label="Settings"
          path={Routes.settings_path(@socket, :page)}
          active={false} />
        <SidebarHelpers.user_item current_user={@current_user} path={Routes.home_path(@socket, :user)} />
      </SidebarHelpers.sidebar>
      <div class="flex-grow px-6 py-8 overflow-y-auto">
        <div class="max-w-screen-lg w-full mx-auto px-4 pb-8 space-y-4">
          <div class="flex flex-col space-y-2 items-center pb-4 border-b border-gray-200
                      sm:flex-row sm:space-y-0 sm:justify-between">
            <div class="text-2xl text-gray-800 font-semibold">
              <img src="/images/logo-with-text.png" class="h-[50px]" alt="Livebook" />
            </div>
            <div class="flex space-x-2 pt-2">
              <%= live_patch "Import",
                    to: Routes.home_path(@socket, :import, "url"),
                    class: "button button-outlined-gray whitespace-nowrap" %>
              <button class="button button-blue" phx-click="new">
                New notebook
              </button>
            </div>
          </div>

          <div class="h-80">
            <.live_component module={LivebookWeb.FileSelectComponent}
                id="home-file-select"
                file={@file}
                extnames={[LiveMarkdown.extension()]}
                running_files={files(@sessions)}>
              <div class="flex justify-end space-x-2">
                <button class="button button-outlined-gray whitespace-nowrap"
                  phx-click="fork"
                  disabled={not path_forkable?(@file, @file_info)}>
                  <.remix_icon icon="git-branch-line" class="align-middle mr-1" />
                  <span>Fork</span>
                </button>
                <%= if file_running?(@file, @sessions) do %>
                  <%= live_redirect "Join session",
                        to: Routes.session_path(@socket, :page, session_id_by_file(@file, @sessions)),
                        class: "button button-blue" %>
                <% else %>
                  <span {open_button_tooltip_attrs(@file, @file_info)}>
                    <button class="button button-blue"
                      phx-click="open"
                      disabled={not path_openable?(@file, @file_info, @sessions)}>
                      Open
                    </button>
                  </span>
                <% end %>
              </div>
            </.live_component>
          </div>

          <div class="py-12">
            <div class="mb-4 flex justify-between items-center">
              <h2 class="uppercase font-semibold text-gray-500">
                Explore
              </h2>
              <%= live_redirect to: Routes.explore_path(@socket, :page),
                    class: "flex items-center text-blue-600" do %>
                <span class="font-semibold">See all</span>
                <.remix_icon icon="arrow-right-line" class="align-middle ml-1" />
              <% end %>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <%# Note: it's fine to use stateless components in this comprehension,
                  because @notebook_infos never change %>
              <%= for info <- @notebook_infos do %>
                <ExploreHelpers.notebook_card notebook_info={info} socket={@socket} />
              <% end %>
            </div>
          </div>

          <div class="py-12">
            <div class="flex items-center justify-between">
              <h2 class="mb-4 uppercase font-semibold text-gray-500">
                Running sessions (<%= length(@sessions) %>)
              </h2>
              <div class="relative" id={"sessions-order-menu"} phx-hook="Menu" data-element="menu">
                <button class="button button-outlined-gray py-1" data-toggle>
                  <span><%= order_by_label(@order_by) %></span>
                  <.remix_icon icon="arrow-down-s-line" class="align-middle ml-1" />
                </button>
                <div class="menu" data-content>
                  <%= for order_by <- ["date", "title"] do %>
                    <button class={"menu__item #{if order_by == @order_by, do: "text-gray-900", else: "text-gray-500"}"}
                      phx-click={JS.push("set_order", value: %{order_by: order_by})}>
                      <.remix_icon icon={order_by_icon(order_by)} />
                      <span class="font-medium"><%= order_by_label(order_by) %></span>
                    </button>
                  <% end %>
                </div>
              </div>
            </div>
            <.sessions_list sessions={@sessions} socket={@socket} />
          </div>
        </div>
      </div>
    </div>

    <%= if @live_action == :user do %>
      <.current_user_modal
        return_to={Routes.home_path(@socket, :page)}
        current_user={@current_user} />
    <% end %>

    <%= if @live_action == :close_session do %>
      <.modal class="w-full max-w-xl" return_to={Routes.home_path(@socket, :page)}>
        <.live_component module={LivebookWeb.HomeLive.CloseSessionComponent}
          id="close-session"
          return_to={Routes.home_path(@socket, :page)}
          session={@session} />
      </.modal>
    <% end %>

    <%= if @live_action == :import do %>
      <.modal class="w-full max-w-xl" return_to={Routes.home_path(@socket, :page)}>
        <.live_component module={LivebookWeb.HomeLive.ImportComponent}
          id="import"
          tab={@tab}
          import_opts={@import_opts} />
      </.modal>
    <% end %>
    """
  end

  defp open_button_tooltip_attrs(file, file_info) do
    if regular?(file, file_info) and not writable?(file_info) do
      [class: "tooltip top", data_tooltip: "This file is write-protected, please fork instead"]
    else
      []
    end
  end

  defp sessions_list(%{sessions: []} = assigns) do
    ~H"""
    <div class="p-5 flex space-x-4 items-center border border-gray-200 rounded-lg">
      <div>
        <.remix_icon icon="windy-line" class="text-gray-400 text-xl" />
      </div>
      <div class="text-gray-600">
        You do not have any running sessions.
        <br>
        Please create a new one by clicking <span class="font-semibold">“New notebook”</span>
      </div>
    </div>
    """
  end

  defp sessions_list(assigns) do
    ~H"""
    <div class="flex flex-col">
      <%= for session <- @sessions do %>
        <div class="py-4 flex items-center border-b border-gray-300"
          data-test-session-id={session.id}>
          <div class="flex-grow flex flex-col">
            <%= live_redirect session.notebook_name,
                  to: Routes.session_path(@socket, :page, session.id),
                  class: "font-semibold text-gray-800 hover:text-gray-900" %>
            <div class="text-gray-600 text-sm">
              <%= if session.file, do: session.file.path, else: "No file" %>
            </div>
            <div class="mt-2 text-gray-600 text-sm">
              Created
              <span class="text-gray-800 font-medium">
                <%= format_creation_date(session.created_at) %>
              </span>
            </div>
          </div>
          <div class="relative" id={"session-#{session.id}-menu"} phx-hook="Menu" data-element="menu">
            <button class="icon-button" data-toggle>
              <.remix_icon icon="more-2-fill" class="text-xl" />
            </button>
            <div class="menu" data-content>
              <button class="menu__item text-gray-500"
                phx-click="fork_session"
                phx-value-id={session.id}>
                <.remix_icon icon="git-branch-line" />
                <span class="font-medium">Fork</span>
              </button>
              <a class="menu__item text-gray-500"
                href={live_dashboard_process_path(@socket, session.pid)}
                target="_blank">
                <.remix_icon icon="dashboard-2-line" />
                <span class="font-medium">See on Dashboard</span>
              </a>
              <%= live_patch to: Routes.home_path(@socket, :close_session, session.id),
                    class: "menu__item text-red-600" do %>
                <.remix_icon icon="close-circle-line" />
                <span class="font-medium">Close</span>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_params(%{"session_id" => session_id}, _url, socket) do
    session = Enum.find(socket.assigns.sessions, &(&1.id == session_id))
    {:noreply, assign(socket, session: session)}
  end

  def handle_params(%{"tab" => tab} = params, _url, %{assigns: %{live_action: :import}} = socket) do
    import_opts = [url: params["url"]]
    {:noreply, assign(socket, tab: tab, import_opts: import_opts)}
  end

  def handle_params(%{"url" => url}, _url, %{assigns: %{live_action: :public_import}} = socket) do
    url
    |> Livebook.ContentLoader.rewrite_url()
    |> Livebook.ContentLoader.fetch_content()
    |> case do
      {:ok, content} ->
        socket = import_content(socket, content, origin: {:url, url})
        {:noreply, socket}

      {:error, _message} ->
        {:noreply, push_patch(socket, to: Routes.home_path(socket, :import, "url", url: url))}
    end
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("new", %{}, socket) do
    {:noreply, create_session(socket)}
  end

  def handle_event("fork", %{}, socket) do
    file = socket.assigns.file

    socket =
      case import_notebook(file) do
        {:ok, {notebook, messages}} ->
          notebook = Notebook.forked(notebook)
          images_dir = Session.images_dir_for_notebook(file)

          socket
          |> put_import_warnings(messages)
          |> create_session(
            notebook: notebook,
            copy_images_from: images_dir,
            origin: {:file, file}
          )

        {:error, error} ->
          put_flash(socket, :error, Livebook.Utils.upcase_first(error))
      end

    {:noreply, socket}
  end

  def handle_event("open", %{}, socket) do
    file = socket.assigns.file

    socket =
      case import_notebook(file) do
        {:ok, {notebook, messages}} ->
          socket
          |> put_import_warnings(messages)
          |> create_session(notebook: notebook, file: file, origin: {:file, file})

        {:error, error} ->
          put_flash(socket, :error, Livebook.Utils.upcase_first(error))
      end

    {:noreply, socket}
  end

  def handle_event("set_order", %{"order_by" => order_by}, socket) do
    sessions = sort_sessions(socket.assigns.sessions, order_by)
    {:noreply, assign(socket, sessions: sessions, order_by: order_by)}
  end

  def handle_event("fork_session", %{"id" => session_id}, socket) do
    session = Enum.find(socket.assigns.sessions, &(&1.id == session_id))
    %{images_dir: images_dir} = session
    data = Session.get_data(session.pid)
    notebook = Notebook.forked(data.notebook)

    origin =
      if data.file do
        {:file, data.file}
      else
        data.origin
      end

    {:noreply,
     create_session(socket,
       notebook: notebook,
       copy_images_from: images_dir,
       origin: origin
     )}
  end

  @impl true
  def handle_info({:set_file, file, info}, socket) do
    file_info = %{
      exists: info.exists,
      access:
        case FileSystem.File.access(file) do
          {:ok, access} -> access
          {:error, _} -> :none
        end
    }

    {:noreply, assign(socket, file: file, file_info: file_info)}
  end

  def handle_info({:session_created, session}, socket) do
    if session in socket.assigns.sessions do
      {:noreply, socket}
    else
      sessions = sort_sessions([session | socket.assigns.sessions], socket.assigns.order_by)
      {:noreply, assign(socket, sessions: sessions)}
    end
  end

  def handle_info({:session_updated, session}, socket) do
    sessions =
      Enum.map(socket.assigns.sessions, fn other ->
        if other.id == session.id, do: session, else: other
      end)

    {:noreply, assign(socket, sessions: sessions)}
  end

  def handle_info({:session_closed, session}, socket) do
    sessions = Enum.reject(socket.assigns.sessions, &(&1.id == session.id))
    {:noreply, assign(socket, sessions: sessions)}
  end

  def handle_info({:import_content, content, session_opts}, socket) do
    socket = import_content(socket, content, session_opts)
    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp order_by_label("date"), do: "Date"
  defp order_by_label("title"), do: "Title"

  defp order_by_icon("date"), do: "calendar-2-line"
  defp order_by_icon("title"), do: "text"

  defp sort_sessions(sessions, "date") do
    Enum.sort_by(sessions, & &1.created_at, {:desc, DateTime})
  end

  defp sort_sessions(sessions, "title") do
    Enum.sort_by(sessions, fn session ->
      {session.notebook_name, -DateTime.to_unix(session.created_at)}
    end)
  end

  defp files(sessions) do
    Enum.map(sessions, & &1.file)
  end

  defp path_forkable?(file, file_info) do
    regular?(file, file_info)
  end

  defp path_openable?(file, file_info, sessions) do
    regular?(file, file_info) and not file_running?(file, sessions) and
      writable?(file_info)
  end

  defp regular?(file, file_info) do
    file_info.exists and not FileSystem.File.dir?(file)
  end

  defp writable?(file_info) do
    file_info.access in [:read_write, :write]
  end

  defp file_running?(file, sessions) do
    running_files = files(sessions)
    file in running_files
  end

  defp import_notebook(file) do
    with {:ok, content} <- FileSystem.File.read(file) do
      {:ok, LiveMarkdown.Import.notebook_from_markdown(content)}
    end
  end

  defp session_id_by_file(file, sessions) do
    session = Enum.find(sessions, &(&1.file == file))
    session.id
  end

  def format_creation_date(created_at) do
    time_words = created_at |> DateTime.to_naive() |> Livebook.Utils.Time.time_ago_in_words()
    time_words <> " ago"
  end

  defp import_content(socket, content, session_opts) do
    {notebook, messages} = Livebook.LiveMarkdown.Import.notebook_from_markdown(content)

    socket =
      socket
      |> put_import_warnings(messages)
      |> put_flash(
        :info,
        "You have imported a notebook, no code has been executed so far. You should read and evaluate code as needed."
      )

    session_opts = Keyword.merge(session_opts, notebook: notebook)
    create_session(socket, session_opts)
  end
end
