defmodule Livebook.Evaluator.ObjectTracker do
  @moduledoc false

  # This module is an abstraction for tracking objects,
  # references to them and garbage collection.
  #
  # Every object is identified by an arbitrary unique term.
  # Processes can add pointers to those objects. A pointer
  # is a pair of `{pid(), term()}`, where pid is the pointing
  # process and term can be used as an additional scope.
  #
  # Each pointer can be released either manually by calling
  # `remove_pointer/2` or automatically when the pointing
  # process terminates.
  #
  # When all pointers for the given object are removed,
  # all messages scheduled with `monitor/3` are sent.

  use GenServer

  @type state :: %{
          object_ids: %{
            object_id() => %{
              pointers: list(pointer),
              monitors: list(monitor)
            }
          }
        }

  @typedoc """
  Arbitrary term identifying an object.
  """
  @type object_id :: term()

  @typedoc """
  Reference to an object, where `parent` is the pointing
  process and `reference` is an additional scope.
  """
  @type pointer :: {parent :: pid(), reference :: term()}

  @typedoc """
  Scheduled message to be sent when an object is released.
  """
  @type monitor :: {Process.dest(), payload :: term()}

  @doc """
  Starts a new object tracker.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Adds a pointer to the given object.
  """
  @spec add_pointer(pid(), object_id(), pointer()) :: :ok
  def add_pointer(object_tracker, object_id, pointer) do
    GenServer.cast(object_tracker, {:add_pointer, object_id, pointer})
  end

  @doc """
  Removes the given pointer from all objects it is attached to.
  """
  @spec remove_pointer(pid(), pointer()) :: :ok
  def remove_pointer(object_tracker, pointer) do
    GenServer.cast(object_tracker, {:remove_pointer, pointer})
  end

  @doc """
  Schedules `payload` to be send to `destination` when the object
  is released.
  """
  @spec monitor(pid(), object_id(), Process.dest(), term()) :: :ok
  def monitor(object_tracker, object_id, destination, payload) do
    GenServer.cast(object_tracker, {:monitor, object_id, destination, payload})
  end

  @impl true
  def init(_opts) do
    {:ok, %{object_ids: %{}}}
  end

  @impl true
  def handle_cast({:add_pointer, object_id, pointer}, state) do
    {parent, _reference} = pointer
    Process.monitor(parent)

    state =
      if state.object_ids[object_id] do
        update_in(state.object_ids[object_id].pointers, fn pointers ->
          if pointer in pointers, do: pointers, else: [pointer | pointers]
        end)
      else
        put_in(state.object_ids[object_id], %{pointers: [pointer], monitors: []})
      end

    {:noreply, state}
  end

  def handle_cast({:remove_pointer, pointer}, state) do
    state = update_pointers(state, fn pointers -> List.delete(pointers, pointer) end)

    {:noreply, garbage_collect(state)}
  end

  def handle_cast({:monitor, object_id, destination, payload}, state) do
    monitor = {destination, payload}

    state =
      if state.object_ids[object_id] do
        update_in(state.object_ids[object_id].monitors, fn monitors ->
          if monitor in monitors, do: monitors, else: [monitor | monitors]
        end)
      else
        state
      end

    {:noreply, garbage_collect(state)}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state =
      update_pointers(state, fn pointers ->
        Enum.reject(pointers, &match?({^pid, _}, &1))
      end)

    {:noreply, garbage_collect(state)}
  end

  # Updates pointers for every object with the given function
  defp update_pointers(state, fun) do
    update_in(state.object_ids, fn object_ids ->
      for {object_id, %{pointers: pointers} = info} <- object_ids, into: %{} do
        {object_id, %{info | pointers: fun.(pointers)}}
      end
    end)
  end

  defp garbage_collect(state) do
    {to_release, object_ids} =
      Enum.split_with(state.object_ids, &match?({_, %{pointers: []}}, &1))

    for {_, %{monitors: monitors}} <- to_release, {dest, payload} <- monitors do
      send(dest, payload)
    end

    %{state | object_ids: Map.new(object_ids)}
  end
end
