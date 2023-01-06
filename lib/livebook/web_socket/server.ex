defmodule Livebook.WebSocket.Server do
  @moduledoc false
  use Connection

  require Logger

  alias Livebook.WebSocket
  alias Livebook.WebSocket.Client

  @timeout 10_000
  @backoff 1_490

  defstruct [:url, :listener, :headers, :http_conn, :websocket, :ref, id: 0, reply: %{}]

  @doc """
  Starts a new WebSocket Server connection with given URL and headers.
  """
  @spec start_link(pid(), String.t(), Mint.Types.headers()) ::
          {:ok, pid()} | {:error, {:already_started, pid()}}
  def start_link(listener, url, headers \\ []) do
    Connection.start_link(__MODULE__, {listener, url, headers})
  end

  @doc """
  Sends a Request to given WebSocket Server.
  """
  @spec send_request(pid(), WebSocket.proto()) :: {atom(), term()}
  def send_request(conn, %_struct{} = data) do
    Connection.call(conn, {:request, data}, @timeout)
  end

  ## Connection callbacks

  @impl true
  def init({listener, url, headers}) do
    state = struct!(__MODULE__, listener: listener, url: url, headers: headers)
    {:connect, :init, state}
  end

  @impl true
  def connect(_, state) do
    case Client.connect(state.url, state.headers) do
      {:ok, conn, ref} ->
        {:ok, %{state | http_conn: conn, ref: ref}}

      {:error, exception} when is_exception(exception) ->
        Logger.error("Received exception: #{Exception.message(exception)}")
        send(state.listener, {:connect, :error, exception})

        {:backoff, @backoff, state}

      {:error, conn, reason} ->
        Logger.error("Received error: #{inspect(reason)}")
        send(state.listener, {:connect, :error, reason})

        {:backoff, @backoff, %{state | http_conn: conn}}
    end
  end

  @dialyzer {:nowarn_function, disconnect: 2}

  @impl true
  def disconnect(info, state) do
    case info do
      {:close, from} -> Logger.debug("Received close from: #{inspect(from)}")
      {:error, :closed} -> Logger.error("Connection closed")
      {:error, reason} -> Logger.error("Connection error: #{inspect(reason)}")
    end

    {:connect, :reconnect, state}
  end

  ## GenServer callbacks

  @impl true
  def handle_call({:request, data}, caller, state) do
    id = state.id
    frame = LivebookProto.build_request_frame(data, id)
    reply = Map.put(state.reply, id, caller)

    case Client.send(state.http_conn, state.websocket, state.ref, frame) do
      {:ok, conn, websocket} ->
        {:noreply, %{state | http_conn: conn, websocket: websocket, id: id + 1, reply: reply}}

      {:error, conn, websocket, reason} ->
        {:reply, {:error, reason}, %{state | http_conn: conn, websocket: websocket}}
    end
  end

  @loop_ping_delay 5_000

  @impl true
  def handle_info({:loop_ping, ref}, state) when ref == state.ref and is_reference(ref) do
    case Client.send(state.http_conn, state.websocket, state.ref, :ping) do
      {:ok, conn, websocket} ->
        Process.send_after(self(), {:loop_ping, state.ref}, @loop_ping_delay)
        {:noreply, %{state | http_conn: conn, websocket: websocket}}

      {:error, conn, websocket, _reason} ->
        {:noreply, %{state | http_conn: conn, websocket: websocket}}
    end
  end

  def handle_info({:loop_ping, _another_ref}, state), do: {:noreply, state}

  def handle_info(message, state) do
    case Client.receive(state.http_conn, state.ref, state.websocket, message) do
      {:ok, conn, websocket, :connected} ->
        state = send_received({:ok, :connected}, state)
        send(self(), {:loop_ping, state.ref})

        {:noreply, %{state | http_conn: conn, websocket: websocket}}

      {:error, conn, websocket, %Mint.TransportError{} = reason} ->
        state = send_received({:error, reason}, state)

        {:connect, :receive, %{state | http_conn: conn, websocket: websocket}}

      {term, conn, websocket, data} ->
        state = send_received({term, data}, state)

        {:noreply, %{state | http_conn: conn, websocket: websocket}}

      {:error, _} = error ->
        {:noreply, send_received(error, state)}
    end
  end

  # Private

  defp send_received({:ok, :connected}, state) do
    send(state.listener, {:connect, :ok, :connected})
    state
  end

  defp send_received({:ok, %Client.Response{body: [], status: nil}}, state), do: state

  defp send_received({:ok, %Client.Response{body: binaries}}, state) do
    for binary <- binaries, reduce: state do
      acc ->
        case decode_response_or_event(binary) do
          {:response, %{id: -1, type: {:error, %{details: reason}}}} ->
            reply_to_all({:error, reason}, acc)

          {:response, %{id: id, type: {:error, %{details: reason}}}} ->
            reply_to_id(id, {:error, reason}, acc)

          {:response, %{id: id, type: result}} ->
            reply_to_id(id, result, acc)

          {:event, %{type: {name, data}}} ->
            send(acc.listener, {:event, name, data})
            acc
        end
    end
  end

  defp send_received({:error, :unknown}, state), do: state

  defp send_received({:error, %Mint.TransportError{} = reason}, state) do
    send(state.listener, {:connect, :error, reason})
    state
  end

  defp send_received({:error, %Client.Response{body: binaries, status: status}}, state)
       when binaries != [] and status != nil do
    for binary <- binaries do
      with {:response, body} <- decode_response_or_event(binary),
           %{type: {:error, %{details: reason}}} <- body do
        send(state.listener, {:connect, :error, reason})
      end
    end

    state
  end

  defp send_received({:error, %Client.Response{body: [], status: status}}, state)
       when status != nil do
    reply_to_all({:error, Plug.Conn.Status.reason_phrase(status)}, state)
  end

  defp send_received({:error, %Client.Response{body: binaries, status: nil}}, state) do
    for binary <- binaries,
        {:response, body} <- decode_response_or_event(binary),
        reduce: state do
      acc ->
        case body do
          %{id: -1, type: {:error, %{details: reason}}} -> reply_to_all({:error, reason}, acc)
          %{id: id, type: {:error, %{details: reason}}} -> reply_to_id(id, {:error, reason}, acc)
        end
    end
  end

  defp reply_to_all(message, state) do
    for {_id, caller} <- state.reply do
      Connection.reply(caller, message)
    end

    state
  end

  defp reply_to_id(id, message, state) do
    {caller, reply} = Map.pop(state.reply, id)
    if caller, do: Connection.reply(caller, message)

    %{state | reply: reply}
  end

  defp decode_response_or_event(data) do
    case LivebookProto.Response.decode(data) do
      %{type: nil} -> {:event, LivebookProto.Event.decode(data)}
      response -> {:response, response}
    end
  end
end
