defmodule Livebook.Session do
  @moduledoc false

  # Server corresponding to a single notebook session.
  #
  # The process keeps the current notebook state and serves
  # as a source of truth that multiple clients talk to.
  # Receives update requests from the clients and notifies
  # them of any changes applied to the notebook.
  #
  # ## Collaborative state
  #
  # The core concept is the `Livebook.Session.Data` structure
  # to which we can apply reproducible operations.
  # See `Livebook.Session.Data` for more information.
  #
  # ## Evaluation
  #
  # All regular sections are evaluated in the same process
  # (the :main_flow evaluation container). On the other hand,
  # each branching section is evaluated in its own process
  # and thus runs concurrently.
  #
  # ### Implementation considerations
  #
  # In practice, every evaluation container is a `Livebook.Runtime.Evaluator`
  # process, so we have one such process for the main flow and one
  # for each branching section. Since a branching section inherits
  # the evaluation context from the parent section, the last context
  # needs to be copied from the main flow evaluator to the branching
  # section evaluator. The latter synchronously asks the former for
  # that context using `Livebook.Runtime.Evaluator.get_evaluation_context/3`.
  # Consequently, in order to evaluate the first cell in a branching
  # section, the main flow needs to be free of work, otherwise we wait.
  # This assumptions are mirrored in by `Livebook.Session.Data` when
  # determining cells for evaluation.
  #
  # Note: the context could be copied asynchronously if evaluator
  # kept the contexts in its process dictionary, however the other
  # evaluator could only read the whole process dictionary, thus
  # allocating a lot of memory unnecessarily, which would be unacceptable
  # for large data. By making a synchronous request to the evaluator
  # for a single specific evaluation context we make sure to copy
  # as little memory as necessary.

  # The struct holds the basic session information that we track
  # and pass around. The notebook and evaluation state is kept
  # within the process state.
  defstruct [
    :id,
    :pid,
    :origin,
    :notebook_name,
    :file,
    :mode,
    :images_dir,
    :created_at,
    :memory_usage,
    :app_info
  ]

  use GenServer, restart: :temporary

  import Livebook.Notebook.Cell, only: [is_file_input_value: 1]

  alias Livebook.NotebookManager
  alias Livebook.Session.{Data, FileGuard}
  alias Livebook.{Utils, Notebook, Delta, Runtime, LiveMarkdown, FileSystem}
  alias Livebook.Users.User
  alias Livebook.Notebook.{Cell, Section}

  @timeout :infinity
  @main_container_ref :main_flow
  @client_id "__server__"
  @anonymous_client_id "__anonymous__"

  @type t :: %__MODULE__{
          id: id(),
          pid: pid(),
          origin: Notebook.ContentLoader.location() | nil,
          notebook_name: String.t(),
          file: FileSystem.File.t() | nil,
          mode: Data.session_mode(),
          images_dir: FileSystem.File.t(),
          created_at: DateTime.t(),
          memory_usage: memory_usage(),
          app_info: app_info() | nil
        }

  @type state :: %{
          session_id: id(),
          data: Data.t(),
          client_pids_with_id: %{pid() => Data.client_id()},
          created_at: DateTime.t(),
          runtime_monitor_ref: reference() | nil,
          autosave_timer_ref: reference() | nil,
          autosave_path: String.t(),
          save_task_pid: pid() | nil,
          saved_default_file: FileSystem.File.t() | nil,
          memory_usage: memory_usage(),
          worker_pid: pid(),
          registered_file_deletion_delay: pos_integer(),
          registered_files: %{
            String.t() => %{file_ref: Runtime.file_ref(), linked_client_id: Data.client_id()}
          },
          client_id_with_assets: %{Data.client_id() => map()}
        }

  @type memory_usage ::
          %{
            runtime: Livebook.Runtime.runtime_memory() | nil,
            system: Livebook.SystemResources.memory()
          }

  @type app_info :: %{
          slug: String.t(),
          status: Data.app_status(),
          registered: boolean(),
          public?: boolean()
        }

  @typedoc """
  An id assigned to every running session process.
  """
  @type id :: Utils.id()

  ## API

  @doc """
  Starts a session server process.

  ## Options

    * `:id` (**required**) - a unique session identifier

    * `:notebook` - the initial `Notebook` structure (e.g. imported from a file)

    * `:origin` - location from where the notebook was obtained, can be either
      `{:file, file}`, a remote `{:url, url}`, or `nil`

    * `:file` - the file to which the notebook should be saved

    * `:copy_images_from` - a directory file to copy notebook images from

    * `:images` - a map from image name to its binary content, an alternative
      to `:copy_images_from` when the images are in memory

    * `:autosave_path` - a local directory to save notebooks without a file into.
      Defaults to `Livebook.Settings.autosave_path/0`

    * `:registered_file_deletion_delay` - the time to wait before
      deleting a registered file that is no longer in use. Defaults
      to `15_000`

    * `:mode` - the mode in which the session operates, either `:default`
      or `:app`. Defaults to `:default`

  """
  @spec start_link(keyword()) :: {:ok, pid} | {:error, any()}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Fetches session information from the session server.
  """
  @spec get_by_pid(pid()) :: Session.t()
  def get_by_pid(pid) do
    GenServer.call(pid, :describe_self, @timeout)
  end

  @doc """
  Registers a session client, so that the session is aware of it.

  The client process is automatically unregistered when it terminates.

  Returns the current session data, which the client can than
  keep in sync with the server by subscribing to the `sessions:id`
  topic and receiving operations to apply.

  Also returns a unique client identifier representing the registered
  client.
  """
  @spec register_client(pid(), pid(), User.t()) :: {Data.t(), Data.client_id()}
  def register_client(pid, client_pid, user) do
    GenServer.call(pid, {:register_client, client_pid, user}, @timeout)
  end

  @doc """
  Returns data of the given session.
  """
  @spec get_data(pid()) :: Data.t()
  def get_data(pid) do
    GenServer.call(pid, :get_data, @timeout)
  end

  @doc """
  Returns the current notebook structure.
  """
  @spec get_notebook(pid()) :: Notebook.t()
  def get_notebook(pid) do
    GenServer.call(pid, :get_notebook, @timeout)
  end

  @doc """
  Returns the current app settings.
  """
  @spec get_app_settings(pid()) :: Notebook.AppSettings.t()
  def get_app_settings(pid) do
    GenServer.call(pid, :get_app_settings, @timeout)
  end

  @doc """
  Subscribes to session messages.

  ## Messages

    * `:session_closed`
    * `{:session_updated, session}`
    * `{:hydrate_bin_entries, entries}`
    * `{:operation, operation}`
    * `{:error, error}`

  """
  @spec subscribe(id()) :: :ok | {:error, term()}
  def subscribe(session_id) do
    Phoenix.PubSub.subscribe(Livebook.PubSub, "sessions:#{session_id}")
  end

  @doc """
  Subscribes to app session messages.

  ## Messages

    * `{:app_status_changed, session_id, status}`
    * `{:app_registration_changed, session_id, registered}`
    * `{:app_terminated, session_id}`

  """
  @spec app_subscribe(id()) :: :ok | {:error, term()}
  def app_subscribe(session_id) do
    Phoenix.PubSub.subscribe(Livebook.PubSub, "apps:#{session_id}")
  end

  @doc """
  Computes the file name for download.

  Note that the name doesn't have any extension.

  If the notebook has an associated file, the same name is used,
  otherwise it is computed from the notebook title.
  """
  @spec file_name_for_download(t()) :: String.t()
  def file_name_for_download(session)

  def file_name_for_download(%{file: nil} = session) do
    notebook_name_to_file_name(session.notebook_name)
  end

  def file_name_for_download(session) do
    session.file
    |> FileSystem.File.name()
    |> Path.rootname()
  end

  @doc """
  Fetches assets matching the given hash.

  The assets are cached locally and fetched from the runtime
  only once.

  See `local_asset_path/2` for locating a specific asset.
  """
  @spec fetch_assets(pid(), String.t()) :: :ok | {:error, String.t()}
  def fetch_assets(pid, hash) do
    local_assets_path = local_assets_path(hash)

    if non_empty_dir?(local_assets_path) do
      :ok
    else
      with {:ok, runtime, archive_path} <-
             GenServer.call(pid, {:get_runtime_and_archive_path, hash}, @timeout) do
        fun = fn ->
          # Make sure the file hasn't been fetched by this point
          unless non_empty_dir?(local_assets_path) do
            {:ok, archive_binary} = Runtime.read_file(runtime, archive_path)
            extract_archive!(archive_binary, local_assets_path)
          end
        end

        # Fetch assets in a separate process and avoid several
        # simultaneous fetches of the same assets
        case Livebook.Utils.UniqueTask.run(hash, fun) do
          :ok -> :ok
          :error -> {:error, "failed to fetch assets"}
        end
      end
    end
  end

  defp non_empty_dir?(path) do
    match?({:ok, [_ | _]}, File.ls(path))
  end

  @doc """
  Sends notebook attributes update to the server.
  """
  @spec set_notebook_attributes(pid(), map()) :: :ok
  def set_notebook_attributes(pid, attrs) do
    GenServer.cast(pid, {:set_notebook_attributes, self(), attrs})
  end

  @doc """
  Sends section insertion request to the server.
  """
  @spec insert_section(pid(), non_neg_integer()) :: :ok
  def insert_section(pid, index) do
    GenServer.cast(pid, {:insert_section, self(), index})
  end

  @doc """
  Sends section insertion request to the server.
  """
  @spec insert_section_into(pid(), Section.id(), non_neg_integer()) :: :ok
  def insert_section_into(pid, section_id, index) do
    GenServer.cast(pid, {:insert_section_into, self(), section_id, index})
  end

  @doc """
  Sends parent update request to the server.
  """
  @spec set_section_parent(pid(), Section.id(), Section.id()) :: :ok
  def set_section_parent(pid, section_id, parent_id) do
    GenServer.cast(pid, {:set_section_parent, self(), section_id, parent_id})
  end

  @doc """
  Sends parent update request to the server.
  """
  @spec unset_section_parent(pid(), Section.id()) :: :ok
  def unset_section_parent(pid, section_id) do
    GenServer.cast(pid, {:unset_section_parent, self(), section_id})
  end

  @doc """
  Sends cell insertion request to the server.
  """
  @spec insert_cell(pid(), Section.id(), non_neg_integer(), Cell.type(), map()) :: :ok
  def insert_cell(pid, section_id, index, type, attrs \\ %{}) do
    GenServer.cast(pid, {:insert_cell, self(), section_id, index, type, attrs})
  end

  @doc """
  Sends section deletion request to the server.
  """
  @spec delete_section(pid(), Section.id(), boolean()) :: :ok
  def delete_section(pid, section_id, delete_cells) do
    GenServer.cast(pid, {:delete_section, self(), section_id, delete_cells})
  end

  @doc """
  Sends cell deletion request to the server.
  """
  @spec delete_cell(pid(), Cell.id()) :: :ok
  def delete_cell(pid, cell_id) do
    GenServer.cast(pid, {:delete_cell, self(), cell_id})
  end

  @doc """
  Sends cell restoration request to the server.
  """
  @spec restore_cell(pid(), Cell.id()) :: :ok
  def restore_cell(pid, cell_id) do
    GenServer.cast(pid, {:restore_cell, self(), cell_id})
  end

  @doc """
  Sends cell move request to the server.
  """
  @spec move_cell(pid(), Cell.id(), integer()) :: :ok
  def move_cell(pid, cell_id, offset) do
    GenServer.cast(pid, {:move_cell, self(), cell_id, offset})
  end

  @doc """
  Sends section move request to the server.
  """
  @spec move_section(pid(), Section.id(), integer()) :: :ok
  def move_section(pid, section_id, offset) do
    GenServer.cast(pid, {:move_section, self(), section_id, offset})
  end

  @doc """
  Sends cell recover request to the server.
  """
  @spec recover_smart_cell(pid(), Cell.id()) :: :ok
  def recover_smart_cell(pid, cell_id) do
    GenServer.cast(pid, {:recover_smart_cell, self(), cell_id})
  end

  @doc """
  Sends cell conversion request to the server.
  """
  @spec convert_smart_cell(pid(), Cell.id()) :: :ok
  def convert_smart_cell(pid, cell_id) do
    GenServer.cast(pid, {:convert_smart_cell, self(), cell_id})
  end

  @doc """
  Sends dependencies addition request to the server.
  """
  @spec add_dependencies(pid(), list(Runtime.dependency())) :: :ok
  def add_dependencies(pid, dependencies) do
    GenServer.cast(pid, {:add_dependencies, dependencies})
  end

  @doc """
  Sends disable dependencies cache request to the server.
  """
  @spec disable_dependencies_cache(pid()) :: :ok
  def disable_dependencies_cache(pid) do
    GenServer.cast(pid, :disable_dependencies_cache)
  end

  @doc """
  Sends cell evaluation request to the server.
  """
  @spec queue_cell_evaluation(pid(), Cell.id()) :: :ok
  def queue_cell_evaluation(pid, cell_id) do
    GenServer.cast(pid, {:queue_cell_evaluation, self(), cell_id})
  end

  @doc """
  Sends section evaluation request to the server.
  """
  @spec queue_section_evaluation(pid(), Section.id()) :: :ok
  def queue_section_evaluation(pid, section_id) do
    GenServer.cast(pid, {:queue_section_evaluation, self(), section_id})
  end

  @doc """
  Sends input bound cells evaluation request to the server.
  """
  @spec queue_bound_cells_evaluation(pid(), Data.input_id()) :: :ok
  def queue_bound_cells_evaluation(pid, input_id) do
    GenServer.cast(pid, {:queue_bound_cells_evaluation, self(), input_id})
  end

  @doc """
  Sends full evaluation request to the server.

  All outdated (new/stale/changed) cells, as well as cells given
  as `forced_cell_ids` are scheduled for evaluation.
  """
  @spec queue_full_evaluation(pid(), list(Cell.id())) :: :ok
  def queue_full_evaluation(pid, forced_cell_ids) do
    GenServer.cast(pid, {:queue_full_evaluation, self(), forced_cell_ids})
  end

  @doc """
  Sends reevaluation request to the server.

  Schedules evaluation of all cells that have been evaluated
  previously, until the first fresh cell.
  """
  @spec queue_cells_reevaluation(pid()) :: :ok
  def queue_cells_reevaluation(pid) do
    GenServer.cast(pid, {:queue_cells_reevaluation, self()})
  end

  @doc """
  Sends cell evaluation cancellation request to the server.
  """
  @spec cancel_cell_evaluation(pid(), Cell.id()) :: :ok
  def cancel_cell_evaluation(pid, cell_id) do
    GenServer.cast(pid, {:cancel_cell_evaluation, self(), cell_id})
  end

  @doc """
  Sends erase outputs request to the server.
  """
  @spec erase_outputs(pid()) :: :ok
  def erase_outputs(pid) do
    GenServer.cast(pid, {:erase_outputs, self()})
  end

  @doc """
  Sends notebook name update request to the server.
  """
  @spec set_notebook_name(pid(), String.t()) :: :ok
  def set_notebook_name(pid, name) do
    GenServer.cast(pid, {:set_notebook_name, self(), name})
  end

  @doc """
  Sends section name update request to the server.
  """
  @spec set_section_name(pid(), Section.id(), String.t()) :: :ok
  def set_section_name(pid, section_id, name) do
    GenServer.cast(pid, {:set_section_name, self(), section_id, name})
  end

  @doc """
  Sends a cell delta to apply to the server.
  """
  @spec apply_cell_delta(
          pid(),
          Cell.id(),
          Data.cell_source_tag(),
          Delta.t(),
          Data.cell_revision()
        ) :: :ok
  def apply_cell_delta(pid, cell_id, tag, delta, revision) do
    GenServer.cast(pid, {:apply_cell_delta, self(), cell_id, tag, delta, revision})
  end

  @doc """
  Informs at what revision the given client is.

  This helps to remove old deltas that are no longer necessary.
  """
  @spec report_cell_revision(
          pid(),
          Cell.id(),
          Data.cell_source_tag(),
          Data.cell_revision()
        ) :: :ok
  def report_cell_revision(pid, cell_id, tag, revision) do
    GenServer.cast(pid, {:report_cell_revision, self(), cell_id, tag, revision})
  end

  @doc """
  Sends a cell attributes update to the server.
  """
  @spec set_cell_attributes(pid(), Cell.id(), map()) :: :ok
  def set_cell_attributes(pid, cell_id, attrs) do
    GenServer.cast(pid, {:set_cell_attributes, self(), cell_id, attrs})
  end

  @doc """
  Sends a input value update to the server.
  """
  @spec set_input_value(pid(), Data.input_id(), term()) :: :ok
  def set_input_value(pid, input_id, value) do
    GenServer.cast(pid, {:set_input_value, self(), input_id, value})
  end

  @doc """
  Sends runtime update to the server.

  If the runtime is connected, the session takes the ownership.
  """
  @spec set_runtime(pid(), Runtime.t()) :: :ok
  def set_runtime(pid, runtime) do
    GenServer.cast(pid, {:set_runtime, self(), runtime})
  end

  @doc """
  Sends file location update request to the server.
  """
  @spec set_file(pid(), FileSystem.File.t() | nil) :: :ok
  def set_file(pid, file) do
    GenServer.cast(pid, {:set_file, self(), file})
  end

  @doc """
  Sends a secret addition request to the server.
  """
  @spec set_secret(pid(), map()) :: :ok
  def set_secret(pid, secret) do
    GenServer.cast(pid, {:set_secret, self(), secret})
  end

  @doc """
  Sends a secret deletion request to the server.
  """
  @spec unset_secret(pid(), map()) :: :ok
  def unset_secret(pid, secret_name) do
    GenServer.cast(pid, {:unset_secret, self(), secret_name})
  end

  @doc """
  Sends a hub selection to the server.
  """
  @spec set_notebook_hub(pid(), String.t()) :: :ok
  def set_notebook_hub(pid, id) do
    GenServer.cast(pid, {:set_notebook_hub, self(), id})
  end

  @doc """
  Sends save request to the server.

  If there's a file set and the notebook changed since the last save,
  it will be persisted to said file.

  Note that notebooks are automatically persisted every @autosave_interval
  milliseconds.
  """
  @spec save(pid()) :: :ok
  def save(pid) do
    GenServer.cast(pid, :save)
  end

  @doc """
  Synchronous version of `save/1`.
  """
  @spec save_sync(pid()) :: :ok
  def save_sync(pid) do
    GenServer.call(pid, :save_sync, @timeout)
  end

  @doc """
  Copies the given file into a session-owned location.

  Only the most recent file for the given `key` is kept, old files
  are marked for deletion and removed after a short time.

  ## Options

    * `:linked_client_id` - id of the session client to link the file
      to. When the client leaves the session, all of their linked files
      are marked for deletion

  """
  @spec register_file(pid(), String.t(), String.t(), keyword()) ::
          {:ok, Runtime.file_ref()} | :error
  def register_file(pid, source_path, key, opts \\ []) do
    opts = Keyword.validate!(opts, [:linked_client_id])

    %{file_ref: file_ref, path: path} = GenServer.call(pid, :register_file_init)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.cp(source_path, path) do
      GenServer.cast(pid, {:register_file_finish, file_ref, key, opts[:linked_client_id]})
      {:ok, file_ref}
    else
      _ -> :error
    end
  end

  @doc """
  Closes one or more sessions.

  This results in saving the file and broadcasting
  a :closed message to the session topic.
  """
  @spec close(pid() | [pid()]) :: :ok
  def close(pid) do
    _ = call_many(List.wrap(pid), :close)
    Livebook.SystemResources.update()
    :ok
  end

  @doc """
  Disconnects one or more sessions from the current runtime.

  Note that this results in clearing the evaluation state.
  """
  @spec disconnect_runtime(pid() | [pid()]) :: :ok
  def disconnect_runtime(pid) do
    _ = call_many(List.wrap(pid), {:disconnect_runtime, self()})
    Livebook.SystemResources.update()
    :ok
  end

  defp call_many(list, request) do
    list
    |> Enum.map(&:gen_server.send_request(&1, request))
    |> Enum.map(&:gen_server.wait_response(&1, :infinity))
  end

  @doc """
  Sends a app settings update request to the server.
  """
  @spec set_app_settings(pid(), Notebook.AppSettings.t()) :: :ok
  def set_app_settings(pid, app_settings) do
    GenServer.cast(pid, {:set_app_settings, self(), app_settings})
  end

  @doc """
  Sends a app deployment request to the server.
  """
  @spec deploy_app(pid()) :: :ok
  def deploy_app(pid) do
    GenServer.cast(pid, {:deploy_app, self()})
  end

  @doc """
  Sends a app build request to the server.
  """
  @spec app_build(pid()) :: :ok
  def app_build(pid) do
    GenServer.cast(pid, {:app_build, self()})
  end

  @doc """
  Sends a app shutdown request to the server.

  The shutdown is graceful, so the app only terminates once all of the
  currently connected clients leave.
  """
  @spec app_unregistered(pid()) :: :ok
  def app_unregistered(pid) do
    GenServer.cast(pid, {:app_unregistered, self()})
  end

  @doc """
  Sends a app stop request to the server.

  This results in the app being unregistered under the given slug,
  however it is still running.
  """
  @spec app_stop(pid()) :: :ok
  def app_stop(pid) do
    GenServer.cast(pid, {:app_stop, self()})
  end

  ## Callbacks

  @impl true
  def init(opts) do
    Livebook.Settings.subscribe()
    Livebook.Hubs.subscribe([:secrets])
    id = Keyword.fetch!(opts, :id)

    {:ok, worker_pid} = Livebook.Session.Worker.start_link(id)

    with {:ok, state} <- init_state(id, worker_pid, opts),
         :ok <-
           if(copy_images_from = opts[:copy_images_from],
             do: copy_images(state, copy_images_from),
             else: :ok
           ),
         :ok <-
           if(images = opts[:images],
             do: dump_images(state, images),
             else: :ok
           ) do
      state = schedule_autosave(state)

      if file = state.data.file do
        Livebook.NotebookManager.add_recent_notebook(file, state.data.notebook.name)
      end

      {:ok, state}
    else
      {:error, error} ->
        {:stop, error}
    end
  end

  defp init_state(id, worker_pid, opts) do
    with {:ok, data} <- init_data(opts) do
      state = %{
        session_id: id,
        data: data,
        client_pids_with_id: %{},
        created_at: DateTime.utc_now(),
        runtime_monitor_ref: nil,
        autosave_timer_ref: nil,
        autosave_path: opts[:autosave_path],
        save_task_pid: nil,
        saved_default_file: nil,
        memory_usage: %{runtime: nil, system: Livebook.SystemResources.memory()},
        worker_pid: worker_pid,
        registered_file_deletion_delay: opts[:registered_file_deletion_delay] || 15_000,
        registered_files: %{},
        client_id_with_assets: %{}
      }

      {:ok, state}
    end
  end

  defp init_data(opts) do
    notebook = Keyword.get_lazy(opts, :notebook, &default_notebook/0)
    file = opts[:file]
    origin = opts[:origin]
    mode = opts[:mode] || :default

    data = Data.new(notebook: notebook, origin: origin, mode: mode)

    if file do
      case FileGuard.lock(file, self()) do
        :ok ->
          {:ok, %{data | file: file}}

        {:error, :already_in_use} ->
          {:error, "the given file is already in use"}
      end
    else
      {:ok, data}
    end
  end

  @doc """
  Returns the default notebook for a new session.
  """
  @spec default_notebook() :: Notebook.t()
  def default_notebook() do
    %{Notebook.new() | sections: [%{Section.new() | cells: [Cell.new(:code)]}]}
  end

  defp schedule_autosave(state) do
    if interval_s = state.data.notebook.autosave_interval_s do
      ref = Process.send_after(self(), :autosave, interval_s * 1000)
      %{state | autosave_timer_ref: ref}
    else
      %{state | autosave_timer_ref: nil}
    end
  end

  defp unschedule_autosave(%{autosave_timer_ref: nil} = state), do: state

  defp unschedule_autosave(state) do
    if Process.cancel_timer(state.autosave_timer_ref) == false do
      receive do
        :autosave -> :ok
      end
    end

    %{state | autosave_timer_ref: nil}
  end

  @impl true
  def handle_call(:describe_self, _from, state) do
    {:reply, self_from_state(state), state}
  end

  def handle_call({:register_client, client_pid, user}, _from, state) do
    {state, client_id} =
      if client_id = state.client_pids_with_id[client_pid] do
        {state, client_id}
      else
        Process.monitor(client_pid)
        client_id = Utils.random_id()
        state = handle_operation(state, {:client_join, client_id, user})
        state = put_in(state.client_pids_with_id[client_pid], client_id)
        {state, client_id}
      end

    {:reply, {state.data, client_id}, state}
  end

  def handle_call(:get_data, _from, state) do
    {:reply, state.data, state}
  end

  def handle_call({:get_runtime_and_archive_path, hash}, _from, state) do
    # Lookup assets in the notebook and possibly client-specific outputs
    assets_info =
      Notebook.find_asset_info(state.data.notebook, hash) ||
        Enum.find_value(state.client_id_with_assets, fn {_client_id, assets} -> assets[hash] end)

    runtime = state.data.runtime

    reply =
      cond do
        assets_info == nil ->
          {:error, "unknown hash"}

        not Runtime.connected?(runtime) ->
          {:error, "runtime not started"}

        true ->
          {:ok, runtime, assets_info.archive_path}
      end

    {:reply, reply, state}
  end

  def handle_call(:get_notebook, _from, state) do
    {:reply, state.data.notebook, state}
  end

  def handle_call(:get_app_settings, _from, state) do
    {:reply, state.data.notebook.app_settings, state}
  end

  def handle_call(:save_sync, _from, state) do
    {:reply, :ok, maybe_save_notebook_sync(state)}
  end

  def handle_call(:register_file_init, _from, state) do
    file_id = Utils.random_id()
    file_ref = {:file, file_id}
    path = registered_file_path(state.session_id, file_ref)
    reply = %{file_ref: file_ref, path: path}
    {:reply, reply, state}
  end

  def handle_call(:close, _from, state) do
    before_close(state)

    {:stop, :shutdown, :ok, state}
  end

  def handle_call({:disconnect_runtime, client_pid}, _from, state) do
    client_id = client_id(state, client_pid)

    state =
      if Runtime.connected?(state.data.runtime) do
        {:ok, runtime} = Runtime.disconnect(state.data.runtime)

        %{state | runtime_monitor_ref: nil}
        |> handle_operation({:set_runtime, client_id, runtime})
      else
        state
      end

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:set_notebook_attributes, client_pid, attrs}, state) do
    client_id = client_id(state, client_pid)
    operation = {:set_notebook_attributes, client_id, attrs}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:insert_section, client_pid, index}, state) do
    client_id = client_id(state, client_pid)
    # Include new id in the operation, so it's reproducible
    operation = {:insert_section, client_id, index, Utils.random_id()}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:insert_section_into, client_pid, section_id, index}, state) do
    client_id = client_id(state, client_pid)
    # Include new id in the operation, so it's reproducible
    operation = {:insert_section_into, client_id, section_id, index, Utils.random_id()}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:set_section_parent, client_pid, section_id, parent_id}, state) do
    client_id = client_id(state, client_pid)
    # Include new id in the operation, so it's reproducible
    operation = {:set_section_parent, client_id, section_id, parent_id}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:unset_section_parent, client_pid, section_id}, state) do
    client_id = client_id(state, client_pid)
    # Include new id in the operation, so it's reproducible
    operation = {:unset_section_parent, client_id, section_id}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:insert_cell, client_pid, section_id, index, type, attrs}, state) do
    client_id = client_id(state, client_pid)
    # Include new id in the operation, so it's reproducible
    operation = {:insert_cell, client_id, section_id, index, type, Utils.random_id(), attrs}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:delete_section, client_pid, section_id, delete_cells}, state) do
    client_id = client_id(state, client_pid)
    operation = {:delete_section, client_id, section_id, delete_cells}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:delete_cell, client_pid, cell_id}, state) do
    client_id = client_id(state, client_pid)
    operation = {:delete_cell, client_id, cell_id}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:restore_cell, client_pid, cell_id}, state) do
    client_id = client_id(state, client_pid)
    operation = {:restore_cell, client_id, cell_id}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:move_cell, client_pid, cell_id, offset}, state) do
    client_id = client_id(state, client_pid)
    operation = {:move_cell, client_id, cell_id, offset}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:move_section, client_pid, section_id, offset}, state) do
    client_id = client_id(state, client_pid)
    operation = {:move_section, client_id, section_id, offset}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:recover_smart_cell, client_pid, cell_id}, state) do
    client_id = client_id(state, client_pid)
    operation = {:recover_smart_cell, client_id, cell_id}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:convert_smart_cell, client_pid, cell_id}, state) do
    client_id = client_id(state, client_pid)

    state =
      with {:ok, %Cell.Smart{} = cell, section} <-
             Notebook.fetch_cell_and_section(state.data.notebook, cell_id) do
        index = Enum.find_index(section.cells, &(&1 == cell))
        chunks = cell.chunks || [{0, byte_size(cell.source)}]
        chunk_count = length(chunks)

        state =
          for {{offset, size}, chunk_idx} <- Enum.with_index(chunks), reduce: state do
            state ->
              outputs = if(chunk_idx == chunk_count - 1, do: cell.outputs, else: [])
              source = binary_part(cell.source, offset, size)
              attrs = %{source: source, outputs: outputs}
              cell_idx = index + chunk_idx
              cell_id = Utils.random_id()

              handle_operation(
                state,
                {:insert_cell, client_id, section.id, cell_idx, :code, cell_id, attrs}
              )
          end

        handle_operation(state, {:delete_cell, client_id, cell.id})
      else
        _ -> state
      end

    {:noreply, state}
  end

  def handle_cast({:add_dependencies, dependencies}, state) do
    {:noreply, do_add_dependencies(state, dependencies)}
  end

  def handle_cast(:disable_dependencies_cache, state) do
    if Runtime.connected?(state.data.runtime) do
      Runtime.disable_dependencies_cache(state.data.runtime)
    end

    {:noreply, state}
  end

  def handle_cast({:queue_cell_evaluation, client_pid, cell_id}, state) do
    client_id = client_id(state, client_pid)
    operation = {:queue_cells_evaluation, client_id, [cell_id]}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:queue_section_evaluation, client_pid, section_id}, state) do
    client_id = client_id(state, client_pid)

    case Notebook.fetch_section(state.data.notebook, section_id) do
      {:ok, section} ->
        cell_ids = for cell <- section.cells, Cell.evaluable?(cell), do: cell.id
        operation = {:queue_cells_evaluation, client_id, cell_ids}
        {:noreply, handle_operation(state, operation)}

      :error ->
        {:noreply, state}
    end
  end

  def handle_cast({:queue_bound_cells_evaluation, client_pid, input_id}, state) do
    client_id = client_id(state, client_pid)

    cell_ids =
      for {bound_cell, _} <- Data.bound_cells_with_section(state.data, input_id),
          do: bound_cell.id

    operation = {:queue_cells_evaluation, client_id, cell_ids}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:queue_full_evaluation, client_pid, forced_cell_ids}, state) do
    client_id = client_id(state, client_pid)

    cell_ids = Data.cell_ids_for_full_evaluation(state.data, forced_cell_ids)

    operation = {:queue_cells_evaluation, client_id, cell_ids}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:queue_cells_reevaluation, client_pid}, state) do
    client_id = client_id(state, client_pid)

    cell_ids = Data.cell_ids_for_reevaluation(state.data)

    operation = {:queue_cells_evaluation, client_id, cell_ids}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:cancel_cell_evaluation, client_pid, cell_id}, state) do
    client_id = client_id(state, client_pid)
    operation = {:cancel_cell_evaluation, client_id, cell_id}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:erase_outputs, client_pid}, state) do
    client_id = client_id(state, client_pid)
    operation = {:erase_outputs, client_id}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:set_notebook_name, client_pid, name}, state) do
    client_id = client_id(state, client_pid)
    operation = {:set_notebook_name, client_id, name}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:set_section_name, client_pid, section_id, name}, state) do
    client_id = client_id(state, client_pid)
    operation = {:set_section_name, client_id, section_id, name}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:apply_cell_delta, client_pid, cell_id, tag, delta, revision}, state) do
    client_id = client_id(state, client_pid)
    operation = {:apply_cell_delta, client_id, cell_id, tag, delta, revision}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:report_cell_revision, client_pid, cell_id, tag, revision}, state) do
    client_id = client_id(state, client_pid)
    operation = {:report_cell_revision, client_id, cell_id, tag, revision}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:set_cell_attributes, client_pid, cell_id, attrs}, state) do
    client_id = client_id(state, client_pid)
    operation = {:set_cell_attributes, client_id, cell_id, attrs}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:set_input_value, client_pid, input_id, value}, state) do
    client_id = client_id(state, client_pid)
    operation = {:set_input_value, client_id, input_id, value}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:set_runtime, client_pid, runtime}, state) do
    client_id = client_id(state, client_pid)

    if Runtime.connected?(state.data.runtime) do
      {:ok, _} = Runtime.disconnect(state.data.runtime)
    end

    state =
      if Runtime.connected?(runtime) do
        own_runtime(runtime, state)
      else
        state
      end

    {:noreply, handle_operation(state, {:set_runtime, client_id, runtime})}
  end

  def handle_cast({:set_file, client_pid, file}, state) do
    client_id = client_id(state, client_pid)

    if file do
      FileGuard.lock(file, self())
    else
      :ok
    end
    |> case do
      :ok ->
        if state.data.file do
          FileGuard.unlock(state.data.file)
        end

        {:noreply, handle_operation(state, {:set_file, client_id, file})}

      {:error, :already_in_use} ->
        broadcast_error(state.session_id, "failed to set new file because it is already in use")
        {:noreply, state}
    end
  end

  def handle_cast({:set_secret, client_pid, secret}, state) do
    client_id = client_id(state, client_pid)
    operation = {:set_secret, client_id, secret}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:unset_secret, client_pid, secret_name}, state) do
    client_id = client_id(state, client_pid)
    operation = {:unset_secret, client_id, secret_name}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast(:save, state) do
    {:noreply, maybe_save_notebook_async(state)}
  end

  def handle_cast({:register_file_finish, file_ref, key, linked_client_id}, state) do
    {current_info, state} = pop_in(state.registered_files[key])

    if current_info do
      schedule_file_deletion(state, current_info.file_ref)
    end

    state =
      if linked_client_id == nil or Map.has_key?(state.data.clients_map, linked_client_id) do
        put_in(state.registered_files[key], %{
          file_ref: file_ref,
          linked_client_id: linked_client_id
        })
      else
        schedule_file_deletion(state, file_ref)
        state
      end

    {:noreply, state}
  end

  def handle_cast({:set_app_settings, client_pid, app_settings}, state) do
    client_id = client_id(state, client_pid)
    operation = {:set_app_settings, client_id, app_settings}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:deploy_app, _client_pid}, state) do
    # In the initial state app settings are empty, hence not valid,
    # so we double-check that we can actually deploy
    state =
      if Notebook.AppSettings.valid?(state.data.notebook.app_settings) do
        opts = [notebook: state.data.notebook, mode: :app]

        case Livebook.Sessions.create_session(opts) do
          {:ok, session} ->
            app_subscribe(session.id)
            app_build(session.pid)
            operation = {:add_app, @client_id, session.id, session.pid}
            handle_operation(state, operation)

          {:error, reason} ->
            broadcast_error(
              state.session_id,
              "failed to create app session - #{Exception.format_exit(reason)}"
            )

            state
        end
      else
        state
      end

    {:noreply, state}
  end

  def handle_cast({:app_build, _client_pid}, state) do
    cell_ids = Data.cell_ids_for_full_evaluation(state.data, [])
    operation = {:queue_cells_evaluation, @client_id, cell_ids}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:app_unregistered, _client_pid}, state) do
    operation = {:app_unregistered, @client_id}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:app_stop, _client_pid}, state) do
    operation = {:app_stop, @client_id}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_cast({:set_notebook_hub, client_pid, id}, state) do
    client_id = client_id(state, client_pid)
    operation = {:set_notebook_hub, client_id, id}
    {:noreply, handle_operation(state, operation)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, reason}, %{runtime_monitor_ref: ref} = state) do
    broadcast_error(
      state.session_id,
      "runtime node terminated unexpectedly - #{Exception.format_exit(reason)}"
    )

    {:noreply,
     %{state | runtime_monitor_ref: nil}
     |> handle_operation(
       {:set_runtime, @client_id, Livebook.Runtime.duplicate(state.data.runtime)}
     )}
  end

  def handle_info({:DOWN, _, :process, pid, _}, state) do
    state =
      if client_id = state.client_pids_with_id[pid] do
        handle_operation(state, {:client_leave, client_id})
      else
        state
      end

    {:noreply, state}
  end

  def handle_info({:runtime_evaluation_output, cell_id, output}, state) do
    operation = {:add_cell_evaluation_output, @client_id, cell_id, output}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_info({:runtime_evaluation_output_to, client_id, cell_id, output}, state) do
    client_pid =
      Enum.find_value(state.client_pids_with_id, fn {pid, id} ->
        id == client_id && pid
      end)

    state =
      if client_pid do
        operation = {:add_cell_evaluation_output, @client_id, cell_id, output}
        send(client_pid, {:operation, operation})

        # Keep track of assets infos, so we can look them up when fetching
        for assets_info <- Cell.find_assets_in_output(output), reduce: state do
          state -> put_in(state.client_id_with_assets[client_id][assets_info.hash], assets_info)
        end
      else
        state
      end

    {:noreply, state}
  end

  def handle_info({:runtime_evaluation_response, cell_id, response, metadata}, state) do
    {memory_usage, metadata} = Map.pop(metadata, :memory_usage)
    operation = {:add_cell_evaluation_response, @client_id, cell_id, response, metadata}

    {:noreply,
     state
     |> put_memory_usage(memory_usage)
     |> handle_operation(operation)
     |> notify_update()}
  end

  def handle_info({:runtime_evaluation_input, cell_id, reply_to, input_id}, state) do
    {reply, state} =
      with {:ok, cell, _section} <- Notebook.fetch_cell_and_section(state.data.notebook, cell_id),
           {:ok, value} <- Data.fetch_input_value_for_cell(state.data, input_id, cell_id) do
        state = handle_operation(state, {:bind_input, @client_id, cell.id, input_id})
        {{:ok, value}, state}
      else
        _ -> {:error, state}
      end

    send(reply_to, {:runtime_evaluation_input_reply, reply})

    {:noreply, state}
  end

  def handle_info({:runtime_file_lookup, reply_to, file_ref}, state) do
    path = registered_file_path(state.session_id, file_ref)

    if File.exists?(path) do
      {:file, file_id} = file_ref

      Runtime.transfer_file(state.data.runtime, path, file_id, fn path ->
        send(reply_to, {:runtime_file_lookup_reply, {:ok, path}})
      end)
    else
      send(reply_to, {:runtime_file_lookup_reply, :error})
    end

    {:noreply, state}
  end

  def handle_info({:runtime_container_down, container_ref, message}, state) do
    broadcast_error(state.session_id, "evaluation process terminated - #{message}")

    operation =
      case container_ref do
        @main_container_ref -> {:reflect_main_evaluation_failure, @client_id}
        section_id -> {:reflect_evaluation_failure, @client_id, section_id}
      end

    {:noreply, handle_operation(state, operation)}
  end

  def handle_info(:autosave, state) do
    {:noreply, state |> maybe_save_notebook_async() |> schedule_autosave()}
  end

  def handle_info({:user_change, user}, state) do
    operation = {:update_user, @client_id, user}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_info({:save_finished, pid, result, file, default?}, %{save_task_pid: pid} = state) do
    state = %{state | save_task_pid: nil}
    {:noreply, handle_save_finished(state, result, file, default?)}
  end

  def handle_info({:runtime_memory_usage, runtime_memory}, state) do
    {:noreply, state |> put_memory_usage(runtime_memory) |> notify_update()}
  end

  def handle_info({:runtime_smart_cell_definitions, definitions}, state) do
    operation = {:set_smart_cell_definitions, @client_id, definitions}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_info({:runtime_smart_cell_started, id, info}, state) do
    info =
      if info.editor do
        normalize_newlines = &String.replace(&1, "\r\n", "\n")
        info = update_in(info.source, normalize_newlines)
        update_in(info.editor.source, normalize_newlines)
      else
        info
      end

    case Notebook.fetch_cell_and_section(state.data.notebook, id) do
      {:ok, cell, _section} ->
        chunks = info[:chunks]
        delta = Livebook.JSInterop.diff(cell.source, info.source)

        operation =
          {:smart_cell_started, @client_id, id, delta, chunks, info.js_view, info.editor}

        {:noreply, handle_operation(state, operation)}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:runtime_smart_cell_down, id}, state) do
    operation = {:smart_cell_down, @client_id, id}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_info({:runtime_smart_cell_update, id, attrs, source, info}, state) do
    case Notebook.fetch_cell_and_section(state.data.notebook, id) do
      {:ok, cell, _section} ->
        chunks = info[:chunks]
        delta = Livebook.JSInterop.diff(cell.source, source)
        operation = {:update_smart_cell, @client_id, id, attrs, delta, chunks, info.reevaluate}
        {:noreply, handle_operation(state, operation)}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:pong, {:smart_cell_evaluation, cell_id}, _info}, state) do
    state =
      with {:ok, cell, section} <- Notebook.fetch_cell_and_section(state.data.notebook, cell_id),
           :evaluating <- state.data.cell_infos[cell.id].eval.status do
        start_evaluation(state, cell, section)
      else
        _ -> state
      end

    {:noreply, state}
  end

  def handle_info({:env_var_set, env_var}, state) do
    if Runtime.connected?(state.data.runtime) do
      Runtime.put_system_envs(state.data.runtime, [{env_var.name, env_var.value}])
    end

    {:noreply, state}
  end

  def handle_info({:env_var_unset, env_var}, state) do
    if Runtime.connected?(state.data.runtime) do
      Runtime.delete_system_envs(state.data.runtime, [env_var.name])
    end

    {:noreply, state}
  end

  def handle_info({:delete_registered_file, file_ref}, state) do
    path = registered_file_path(state.session_id, file_ref)

    case File.rm_rf(path) do
      {:ok, _} ->
        if Runtime.connected?(state.data.runtime) do
          {:file, file_id} = file_ref
          Runtime.revoke_file(state.data.runtime, file_id)
        end

      {:error, _, _} ->
        # Deletion may fail if the file is still open, so we retry later
        schedule_file_deletion(state, file_ref)
    end

    {:noreply, state}
  end

  def handle_info({:app_status_changed, session_id, status}, state) do
    operation = {:set_app_status, @client_id, session_id, status}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_info({:app_registration_changed, session_id, registered}, state) do
    operation = {:set_app_registered, @client_id, session_id, registered}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_info({:app_terminated, session_id}, state) do
    operation = {:delete_app, @client_id, session_id}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_info(:close, state) do
    before_close(state)
    {:stop, :shutdown, state}
  end

  def handle_info({event, secret}, state)
      when event in [:secret_created, :secret_updated, :secret_deleted] and
             secret.hub_id == state.data.notebook.hub_id do
    operation = {:sync_hub_secrets, @client_id}
    {:noreply, handle_operation(state, operation)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    cleanup_tmp_dir(state.session_id)
    :ok
  end

  # ---

  defp client_id(state, client_pid) do
    state.client_pids_with_id[client_pid] || @anonymous_client_id
  end

  defp self_from_state(state) do
    %__MODULE__{
      id: state.session_id,
      pid: self(),
      origin: state.data.origin,
      notebook_name: state.data.notebook.name,
      file: state.data.file,
      mode: state.data.mode,
      images_dir: images_dir_from_state(state),
      created_at: state.created_at,
      memory_usage: state.memory_usage,
      app_info:
        if state.data.mode == :app do
          %{
            slug: state.data.notebook.app_settings.slug,
            status: state.data.app_data.status,
            registered: state.data.app_data.registered,
            public?: state.data.notebook.app_settings.access_type == :public
          }
        end
    }
  end

  defp images_dir_from_state(%{data: %{file: nil}, session_id: id}) do
    tmp_dir = session_tmp_dir(id)
    FileSystem.File.resolve(tmp_dir, "images/")
  end

  defp images_dir_from_state(%{data: %{file: file}}) do
    images_dir_for_notebook(file)
  end

  @doc """
  Returns images directory corresponding to the given notebook file.
  """
  @spec images_dir_for_notebook(FileSystem.File.t()) :: FileSystem.File.t()
  def images_dir_for_notebook(file) do
    file
    |> FileSystem.File.containing_dir()
    |> FileSystem.File.resolve("images/")
  end

  defp session_tmp_dir(session_id) do
    livebook_tmp_path()
    |> Path.join("sessions/#{session_id}")
    |> FileSystem.Utils.ensure_dir_path()
    |> FileSystem.File.local()
  end

  defp cleanup_tmp_dir(session_id) do
    tmp_dir = session_tmp_dir(session_id)
    FileSystem.File.remove(tmp_dir)
  end

  @doc """
  Returns a local path to the directory for all assets for hash.
  """
  @spec local_assets_path(String.t()) :: String.t()
  def local_assets_path(hash) do
    Path.join([livebook_tmp_path(), "assets", encode_path_component(hash)])
  end

  @doc """
  Returns a local path to asset matching the given
  hash and path.

  The file is not guaranteed to exist. See `fetch_assets/2`
  for fetching assets through a particular session.

  The path is expected to be a simple relative path
  within the assets directory, otherwise an error is
  returned.
  """
  @spec local_asset_path(String.t(), String.t()) :: {:ok, String.t()} | :error
  def local_asset_path(hash, asset_path) do
    assets_path = local_assets_path(hash)
    local_asset_path = Path.expand(asset_path, assets_path)

    if String.starts_with?(local_asset_path, assets_path <> "/") do
      {:ok, local_asset_path}
    else
      :error
    end
  end

  defp encode_path_component(component) do
    String.replace(component, [".", "/", "\\", ":"], "_")
  end

  defp livebook_tmp_path() do
    tmp_dir = System.tmp_dir!() |> Path.expand()
    Path.join(tmp_dir, "livebook")
  end

  defp copy_images(state, source) do
    images_dir = images_dir_from_state(state)

    with {:ok, source_exists?} <- FileSystem.File.exists?(source) do
      if source_exists? do
        FileSystem.File.copy(source, images_dir)
      else
        :ok
      end
    end
  end

  defp move_images(state, source) do
    images_dir = images_dir_from_state(state)

    with {:ok, source_exists?} <- FileSystem.File.exists?(source) do
      if source_exists? do
        with {:ok, destination_exists?} <- FileSystem.File.exists?(images_dir) do
          if destination_exists? do
            # If the directory exists, we use copy to place
            # the images there
            with :ok <- FileSystem.File.copy(source, images_dir) do
              FileSystem.File.remove(source)
            end
          else
            # If the directory doesn't exist, we can just change
            # the directory name, which is more efficient if
            # available in the given file system
            FileSystem.File.rename(source, images_dir)
          end
        end
      else
        :ok
      end
    end
  end

  defp dump_images(state, images) do
    images_dir = images_dir_from_state(state)

    Enum.reduce(images, :ok, fn {filename, content}, result ->
      with :ok <- result do
        file = FileSystem.File.resolve(images_dir, filename)
        FileSystem.File.write(file, content)
      end
    end)
  end

  defp own_runtime(runtime, state) do
    runtime_monitor_ref = Runtime.take_ownership(runtime, runtime_broadcast_to: state.worker_pid)
    %{state | runtime_monitor_ref: runtime_monitor_ref}
  end

  defp do_add_dependencies(state, dependencies) do
    {:ok, cell, _} = Notebook.fetch_cell_and_section(state.data.notebook, Cell.setup_cell_id())
    source = cell.source

    case Runtime.add_dependencies(state.data.runtime, source, dependencies) do
      {:ok, ^source} ->
        state

      {:ok, new_source} ->
        delta = Livebook.JSInterop.diff(cell.source, new_source)
        revision = state.data.cell_infos[cell.id].sources.primary.revision + 1

        handle_operation(
          state,
          {:apply_cell_delta, @client_id, cell.id, :primary, delta, revision}
        )

      {:error, message} ->
        broadcast_error(
          state.session_id,
          "failed to add dependencies to the setup cell, reason:\n\n#{message}"
        )

        state
    end
  end

  # Given any operation on `Livebook.Session.Data`, the process
  # does the following:
  #
  #   * broadcasts the operation to all clients immediately,
  #     so that they can update their local `Livebook.Session.Data`
  #
  #   * applies the operation to own local `Livebook.Session.Data`
  #
  #   * if necessary, performs the relevant actions (e.g. starts cell evaluation),
  #     to reflect the new `Livebook.Session.Data`
  #
  defp handle_operation(state, operation) do
    broadcast_operation(state.session_id, operation)

    case Data.apply_operation(state.data, operation) do
      {:ok, new_data, actions} ->
        %{state | data: new_data}
        |> after_operation(state, operation)
        |> handle_actions(actions)

      :error ->
        state
    end
  end

  defp after_operation(state, _prev_state, {:set_notebook_name, _client_id, _name}) do
    if file = state.data.file do
      NotebookManager.update_notebook_name(file, state.data.notebook.name)
    end

    notify_update(state)
  end

  defp after_operation(state, _prev_state, {:set_runtime, _client_id, runtime}) do
    if Runtime.connected?(runtime) do
      set_runtime_secrets(state, state.data.secrets)
      set_runtime_env_vars(state)

      state
    else
      state
      |> put_memory_usage(nil)
      |> notify_update()
    end
  end

  defp after_operation(state, prev_state, {:set_file, _client_id, _file}) do
    prev_images_dir = images_dir_from_state(prev_state)

    if prev_state.data.file do
      copy_images(state, prev_images_dir)
    else
      move_images(state, prev_images_dir)
    end
    |> case do
      :ok ->
        :ok

      {:error, message} ->
        broadcast_error(state.session_id, "failed to copy images - #{message}")
    end

    if file = state.data.file do
      Livebook.NotebookManager.add_recent_notebook(file, state.data.notebook.name)
    end

    notify_update(state)
  end

  defp after_operation(
         state,
         _prev_state,
         {:set_notebook_attributes, _client_id, %{autosave_interval_s: _}}
       ) do
    state
    |> unschedule_autosave()
    |> schedule_autosave()
  end

  defp after_operation(state, prev_state, {:client_join, client_id, user}) do
    unless Map.has_key?(prev_state.data.users_map, user.id) do
      Livebook.Users.subscribe(user.id)
    end

    state = put_in(state.client_id_with_assets[client_id], %{})

    state
  end

  defp after_operation(state, prev_state, {:client_leave, client_id}) do
    user_id = prev_state.data.clients_map[client_id]

    unless Map.has_key?(state.data.users_map, user_id) do
      Livebook.Users.unsubscribe(user_id)
    end

    state = delete_client_files(state, client_id)
    {_, state} = pop_in(state.client_id_with_assets[client_id])

    state
  end

  defp after_operation(state, _prev_state, {:delete_cell, _client_id, cell_id}) do
    entry = Enum.find(state.data.bin_entries, fn entry -> entry.cell.id == cell_id end)
    # The session LV drops cell's source, so we send them
    # the complete bin entry to override
    broadcast_message(state.session_id, {:hydrate_bin_entries, [entry]})

    state
  end

  defp after_operation(state, prev_state, {:delete_section, _client_id, section_id, true}) do
    {:ok, section} = Notebook.fetch_section(prev_state.data.notebook, section_id)
    cell_ids = Enum.map(section.cells, & &1.id)
    entries = Enum.filter(state.data.bin_entries, fn entry -> entry.cell.id in cell_ids end)
    broadcast_message(state.session_id, {:hydrate_bin_entries, entries})

    state
  end

  defp after_operation(
         state,
         _prev_state,
         {:apply_cell_delta, _client_id, cell_id, tag, _delta, _revision}
       ) do
    with :secondary <- tag,
         {:ok, %Cell.Smart{} = cell, _section} <-
           Notebook.fetch_cell_and_section(state.data.notebook, cell_id) do
      send(cell.js_view.pid, {:editor_source, cell.editor.source})
    end

    state
  end

  defp after_operation(state, _prev_state, {:set_secret, _client_id, secret}) do
    if Runtime.connected?(state.data.runtime), do: set_runtime_secret(state, secret)
    state
  end

  defp after_operation(state, _prev_state, {:unset_secret, _client_id, secret_name}) do
    if Runtime.connected?(state.data.runtime), do: delete_runtime_secrets(state, [secret_name])
    state
  end

  defp after_operation(state, _prev_state, {:app_unregistered, _client_id}) do
    broadcast_app_message(state.session_id, {:app_registration_changed, state.session_id, false})

    notify_update(state)
  end

  defp after_operation(state, _prev_state, {:set_notebook_hub, _client_id, _id}) do
    notify_update(state)
  end

  defp after_operation(state, _prev_state, _operation), do: state

  defp handle_actions(state, actions) do
    Enum.reduce(actions, state, &handle_action(&2, &1))
  end

  defp handle_action(state, :connect_runtime) do
    case Runtime.connect(state.data.runtime) do
      {:ok, runtime} ->
        state = own_runtime(runtime, state)
        handle_operation(state, {:set_runtime, @client_id, runtime})

      {:error, error} ->
        broadcast_error(state.session_id, "failed to connect runtime - #{error}")
        handle_operation(state, {:set_runtime, @client_id, state.data.runtime})
    end
  end

  defp handle_action(state, {:start_evaluation, cell, section}) do
    info = state.data.cell_infos[cell.id]

    if is_struct(cell, Cell.Smart) and info.status == :started do
      # We do a ping and start evaluation only once we get a reply,
      # this way we make sure we received all relevant source changes
      send(
        cell.js_view.pid,
        {:ping, self(), {:smart_cell_evaluation, cell.id}, %{ref: cell.js_view.ref}}
      )

      state
    else
      start_evaluation(state, cell, section)
    end
  end

  defp handle_action(state, {:stop_evaluation, section}) do
    if Runtime.connected?(state.data.runtime) do
      Runtime.drop_container(state.data.runtime, container_ref_for_section(section))
    end

    state
  end

  defp handle_action(state, {:forget_evaluation, cell, section}) do
    if Runtime.connected?(state.data.runtime) do
      Runtime.forget_evaluation(state.data.runtime, {container_ref_for_section(section), cell.id})
    end

    state
  end

  defp handle_action(state, {:start_smart_cell, cell, _section}) do
    if Runtime.connected?(state.data.runtime) do
      parent_locators = parent_locators_for_cell(state.data, cell)

      Runtime.start_smart_cell(
        state.data.runtime,
        cell.kind,
        cell.id,
        cell.attrs,
        parent_locators
      )
    end

    state
  end

  defp handle_action(state, {:set_smart_cell_parents, cell, _section, parents}) do
    if Runtime.connected?(state.data.runtime) do
      parent_locators = evaluation_parents_to_locators(parents)
      Runtime.set_smart_cell_parent_locators(state.data.runtime, cell.id, parent_locators)
    end

    state
  end

  defp handle_action(state, {:stop_smart_cell, cell}) do
    if Runtime.connected?(state.data.runtime) do
      Runtime.stop_smart_cell(state.data.runtime, cell.id)
    end

    state
  end

  defp handle_action(state, {:clean_up_input_values, input_values}) do
    for {_input_id, value} <- input_values do
      case value do
        value when is_file_input_value(value) ->
          schedule_file_deletion(state, value.file_ref)

        _ ->
          :ok
      end
    end

    state
  end

  defp handle_action(state, :app_broadcast_status) do
    status = state.data.app_data.status
    broadcast_app_message(state.session_id, {:app_status_changed, state.session_id, status})

    notify_update(state)
  end

  defp handle_action(state, :app_register) do
    Livebook.Apps.register(self(), state.data.notebook.app_settings.slug)
    broadcast_app_message(state.session_id, {:app_registration_changed, state.session_id, true})

    notify_update(state)
  end

  defp handle_action(state, :app_unregister) do
    Livebook.Apps.unregister(self(), state.data.notebook.app_settings.slug)
    broadcast_app_message(state.session_id, {:app_registration_changed, state.session_id, false})

    notify_update(state)
  end

  defp handle_action(state, :app_recover) do
    if Runtime.connected?(state.data.runtime) do
      {:ok, _} = Runtime.disconnect(state.data.runtime)
    end

    new_runtime = Livebook.Runtime.duplicate(state.data.runtime)
    cell_ids = Data.cell_ids_for_full_evaluation(state.data, [])

    state
    |> handle_operation({:erase_outputs, @client_id})
    |> handle_operation({:set_runtime, @client_id, new_runtime})
    |> handle_operation({:queue_cells_evaluation, @client_id, cell_ids})
  end

  defp handle_action(state, :app_terminate) do
    send(self(), :close)

    state
  end

  defp handle_action(state, _action), do: state

  defp start_evaluation(state, cell, section) do
    path =
      case state.data.file do
        nil -> ""
        file -> file.path
      end

    file = path <> "#cell:#{cell.id}"

    smart_cell_ref =
      case cell do
        %Cell.Smart{} -> cell.id
        _ -> nil
      end

    opts = [file: file, smart_cell_ref: smart_cell_ref]

    locator = {container_ref_for_section(section), cell.id}
    parent_locators = parent_locators_for_cell(state.data, cell)
    Runtime.evaluate_code(state.data.runtime, cell.source, locator, parent_locators, opts)

    evaluation_digest = :erlang.md5(cell.source)
    handle_operation(state, {:evaluation_started, @client_id, cell.id, evaluation_digest})
  end

  defp broadcast_operation(session_id, operation) do
    broadcast_message(session_id, {:operation, operation})
  end

  defp broadcast_error(session_id, error) do
    broadcast_message(session_id, {:error, error})
  end

  defp broadcast_message(session_id, message) do
    Phoenix.PubSub.broadcast(Livebook.PubSub, "sessions:#{session_id}", message)
  end

  defp broadcast_app_message(session_id, message) do
    Phoenix.PubSub.broadcast(Livebook.PubSub, "apps:#{session_id}", message)
  end

  defp put_memory_usage(state, runtime) do
    put_in(state.memory_usage, %{runtime: runtime, system: Livebook.SystemResources.memory()})
  end

  defp set_runtime_secret(state, secret) do
    secret = {"LB_#{secret.name}", secret.value}
    Runtime.put_system_envs(state.data.runtime, [secret])
  end

  defp set_runtime_secrets(state, secrets) do
    envs_vars = Enum.map(secrets, fn {_name, secret} -> {"LB_#{secret.name}", secret.value} end)
    Runtime.put_system_envs(state.data.runtime, envs_vars)
  end

  defp delete_runtime_secrets(state, secret_names) do
    env_var_names = Enum.map(secret_names, &"LB_#{&1}")
    Runtime.delete_system_envs(state.data.runtime, env_var_names)
  end

  defp set_runtime_env_vars(state) do
    env_vars = Enum.map(Livebook.Settings.fetch_env_vars(), &{&1.name, &1.value})
    Runtime.put_system_envs(state.data.runtime, env_vars)
  end

  defp notify_update(state) do
    session = self_from_state(state)
    Livebook.Sessions.update_session(session)
    broadcast_message(state.session_id, {:session_updated, session})
    state
  end

  defp maybe_save_notebook_async(state) when state.data.mode == :default do
    {file, default?} = notebook_autosave_file(state)

    if file && should_save_notebook?(state) do
      pid = self()
      notebook = state.data.notebook

      {:ok, pid} =
        Task.Supervisor.start_child(Livebook.TaskSupervisor, fn ->
          content = LiveMarkdown.notebook_to_livemd(notebook)
          result = FileSystem.File.write(file, content)
          send(pid, {:save_finished, self(), result, file, default?})
        end)

      %{state | save_task_pid: pid}
    else
      state
    end
  end

  defp maybe_save_notebook_async(state), do: state

  defp maybe_save_notebook_sync(state) when state.data.mode == :default do
    {file, default?} = notebook_autosave_file(state)

    if file && should_save_notebook?(state) do
      content = LiveMarkdown.notebook_to_livemd(state.data.notebook)
      result = FileSystem.File.write(file, content)
      handle_save_finished(state, result, file, default?)
    else
      state
    end
  end

  defp maybe_save_notebook_sync(state), do: state

  defp should_save_notebook?(state) do
    state.data.dirty and state.save_task_pid == nil
  end

  defp notebook_autosave_file(state) do
    file = state.data.file || default_notebook_file(state)
    default? = state.data.file == nil
    {file, default?}
  end

  defp default_notebook_file(state) do
    if path = state.autosave_path || Livebook.Settings.autosave_path() do
      dir = path |> FileSystem.Utils.ensure_dir_path() |> FileSystem.File.local()
      notebook_rel_path = default_notebook_path(state)
      FileSystem.File.resolve(dir, notebook_rel_path)
    end
  end

  defp default_notebook_path(state) do
    title_str = notebook_name_to_file_name(state.data.notebook.name)

    # We want a random, but deterministic part, so we
    # use a few trailing characters from the session id,
    # which are random already
    random_str = String.slice(state.session_id, -4..-1)

    [date_str, time_str, _] =
      state.created_at
      |> DateTime.to_iso8601()
      |> String.replace(["-", ":"], "_")
      |> String.split(["T", "."])

    "#{date_str}/#{time_str}_#{title_str}_#{random_str}.livemd"
  end

  defp notebook_name_to_file_name(notebook_name) do
    notebook_name
    |> String.downcase()
    |> String.replace(~r/[^\s\w]/u, "")
    |> String.trim()
    |> String.replace(~r/\s+/u, "_")
    |> case do
      "" -> "untitled_notebook"
      name -> name
    end
  end

  defp handle_save_finished(state, result, file, default?) do
    state =
      if default? do
        if state.saved_default_file && state.saved_default_file != file do
          FileSystem.File.remove(state.saved_default_file)
        end

        %{state | saved_default_file: file}
      else
        state
      end

    case result do
      :ok ->
        handle_operation(state, {:mark_as_not_dirty, @client_id})

      {:error, message} ->
        broadcast_error(state.session_id, "failed to save notebook - #{message}")
        state
    end
  end

  defp extract_archive!(binary, path) do
    case :erl_tar.extract({:binary, binary}, [:compressed, {:cwd, String.to_charlist(path)}]) do
      :ok ->
        :ok

      {:error, reason} ->
        File.rm_rf!(path)
        raise "failed to extract archive to #{path}, reason: #{inspect(reason)}"
    end
  end

  defp registered_file_path(session_id, {:file, file_id}) do
    %{path: session_dir} = session_tmp_dir(session_id)
    Path.join([session_dir, "registered_files", file_id])
  end

  defp schedule_file_deletion(state, file_ref) do
    Process.send_after(
      self(),
      {:delete_registered_file, file_ref},
      state.registered_file_deletion_delay
    )
  end

  defp delete_client_files(state, client_id) do
    {client_files, other_files} =
      Enum.split_with(state.registered_files, fn {_key, info} ->
        info.linked_client_id == client_id
      end)

    for {_key, info} <- client_files do
      schedule_file_deletion(state, info.file_ref)
    end

    %{state | registered_files: Map.new(other_files)}
  end

  defp before_close(state) do
    maybe_save_notebook_sync(state)
    broadcast_message(state.session_id, :session_closed)

    if state.data.mode == :app do
      broadcast_app_message(state.session_id, {:app_terminated, state.session_id})
    end
  end

  @doc """
  Subscribes the caller to runtime messages under the given topic.

  Broadcasted events are encoded using `encoder`, if successful,
  the message is sent directly to `receiver_pid`, otherwise an
  `{:encoding_error, error, message}` is sent to the caller.
  """
  @spec subscribe_to_runtime_events(
          id(),
          String.t(),
          String.t(),
          (term() -> {:ok, term()} | {:error, term()}),
          pid()
        ) :: :ok | {:error, term()}
  def subscribe_to_runtime_events(session_id, topic, subtopic, encoder, receiver_pid) do
    full_topic = runtime_messages_topic(session_id, topic, subtopic)
    Phoenix.PubSub.subscribe(Livebook.PubSub, full_topic, metadata: {encoder, receiver_pid})
  end

  @doc """
  Unsubscribes the caller from runtime messages subscribed earlier
  with `subscribe_to_runtime_events/5`.
  """
  @spec unsubscribe_from_runtime_events(id(), String.t(), String.t()) :: :ok | {:error, term()}
  def unsubscribe_from_runtime_events(session_id, topic, subtopic) do
    full_topic = runtime_messages_topic(session_id, topic, subtopic)
    Phoenix.PubSub.unsubscribe(Livebook.PubSub, full_topic)
  end

  @doc false
  def broadcast_runtime_event(session_id, topic, subtopic, message) do
    full_topic = runtime_messages_topic(session_id, topic, subtopic)
    Phoenix.PubSub.broadcast(Livebook.PubSub, full_topic, message, __MODULE__)
  end

  defp runtime_messages_topic(session_id, topic, subtopic) do
    "sessions:#{session_id}:runtime_messages:#{topic}:#{subtopic}"
  end

  @doc false
  # Custom dispatcher for broadcasting runtime events
  def dispatch(subscribers, from, message) do
    Enum.reduce(subscribers, %{}, fn
      {pid, _}, cache when pid == from ->
        cache

      {pid, {encoder, receiver_pid}}, cache ->
        case cache do
          %{^encoder => encoded_message} ->
            send(receiver_pid, encoded_message)
            cache

          %{} ->
            case encoder.(message) do
              {:ok, encoded_message} ->
                send(receiver_pid, encoded_message)
                Map.put(cache, encoder, encoded_message)

              {:error, error} ->
                send(pid, {:encoding_error, error, message})
                cache
            end
        end

      {pid, _}, cache ->
        send(pid, message)
        cache
    end)
  end

  @doc """
  Returns locators of evaluation parents for the given cell.

  Considers only cells that have already been evaluated.
  """
  @spec parent_locators_for_cell(Data.t(), Cell.t()) :: Runtime.parent_locators()
  def parent_locators_for_cell(data, cell) do
    data
    |> Data.cell_evaluation_parents(cell)
    |> evaluation_parents_to_locators()
  end

  defp evaluation_parents_to_locators(parents) do
    for {cell, section} <- parents do
      {container_ref_for_section(section), cell.id}
    end
  end

  defp container_ref_for_section(%{parent_id: nil}), do: @main_container_ref
  defp container_ref_for_section(section), do: section.id
end
