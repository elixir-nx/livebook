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
  Checks if the given WebSocket Server is connected.
  """
  @spec connected?(pid()) :: boolean()
  def connected?(conn) do
    Connection.call(conn, :connected?, @timeout)
  end

  @doc """
  Closes the given WebSocket Server connection.
  """
  @spec close(pid()) :: :ok
  def close(conn) do
    Connection.call(conn, :close, @timeout)
  end

  @doc """
  Sends a Request to given WebSocket Server.
  """
  @spec send_request(pid(), WebSocket.proto()) :: {:ok, non_neg_integer()}
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
        send(state.listener, {:connect, :ok, :waiting_upgrade})
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
  def disconnect({:close, caller}, state) do
    Connection.reply(caller, :ok)

    case Client.disconnect(state.http_conn, state.websocket, state.ref) do
      {:ok, conn, websocket} ->
        send(state.listener, {:disconnect, :ok, :disconnected})
        {:noconnect, %{state | http_conn: conn, websocket: websocket}}

      {:error, conn, websocket, reason} ->
        send(state.listener, {:disconnect, :error, reason})
        {:noconnect, %{state | http_conn: conn, websocket: websocket}}
    end
  end

  def disconnect(info, state) do
    case info do
      {:error, :closed} -> Logger.error("Connection closed")
      {:error, reason} -> Logger.error("Connection error: #{inspect(reason)}")
    end

    case Client.disconnect(state.http_conn, state.websocket, state.ref) do
      {:ok, conn, websocket} ->
        send(state.listener, {:disconnect, :ok, :disconnected})

        {:connect, :reconnect, %{state | http_conn: conn, websocket: websocket}}

      {:error, conn, websocket, reason} ->
        Logger.error("Received error: #{inspect(reason)}")
        send(state.listener, {:disconnect, :error, reason})

        {:connect, :reconnect, %{state | http_conn: conn, websocket: websocket}}
    end
  end

  ## GenServer callbacks

  @impl true
  def handle_call(:connected?, _from, state) do
    if conn = state.http_conn do
      {:reply, conn.state == :open, state}
    else
      {:reply, false, state}
    end
  end

  def handle_call(:close, caller, state) do
    {:disconnect, {:close, caller}, state}
  end

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

  @impl true
  def handle_info(message, state) do
    case Client.receive(state.http_conn, state.ref, state.websocket, message) do
      {:ok, conn, websocket, :connected} ->
        send(state.listener, build_message({:ok, :connected}))

        {:noreply, %{state | http_conn: conn, websocket: websocket}}

      {:error, conn, websocket, %Mint.TransportError{} = reason} ->
        send(state.listener, build_message({:error, reason}))

        {:connect, :receive, %{state | http_conn: conn, websocket: websocket}}

      {term, conn, websocket, data} ->
        state =
          {term, data}
          |> build_message()
          |> send_reply(state)

        {:noreply, %{state | http_conn: conn, websocket: websocket}}

      {:error, _} = error ->
        send(state.listener, build_message(error))

        {:noreply, state}
    end
  end

  # Private

  defp send_reply({:response, :error, reason}, state) do
    for {id, caller} <- state.reply, reduce: state do
      acc ->
        Connection.reply(caller, {:error, reason})
        %{acc | reply: Map.delete(acc.reply, id)}
    end
  end

  defp send_reply({:response, id, result}, state) do
    if caller = state.reply[id] do
      Connection.reply(caller, result)
    end

    %{state | reply: Map.delete(state.reply, id)}
  end

  defp send_reply(message, state) do
    send(state.listener, message)

    state
  end

  defp build_message({:ok, :connected}) do
    {:connect, :ok, :connected}
  end

  defp build_message({:ok, %Client.Response{body: nil, status: nil}}) do
    :pong
  end

  defp build_message({:error, %Client.Response{body: nil, status: status}}) do
    {:response, :error, Plug.Conn.Status.reason_phrase(status)}
  end

  defp build_message({:ok, %Client.Response{body: body}}) do
    case LivebookProto.Response.decode(body) do
      %{id: -1, type: {:error, %{details: reason}}} ->
        {:response, :error, reason}

      %{id: id, type: {:error, %{details: reason}}} ->
        {:response, id, {:error, reason}}

      %{id: id, type: result} ->
        {:response, id, result}
    end
  end

  defp build_message({:error, %Client.Response{body: body} = response})
       when response.status != nil do
    %{type: {:error, %{details: reason}}} = LivebookProto.Response.decode(body)
    {:connect, :error, reason}
  end

  defp build_message({:error, %Client.Response{body: body}}) do
    case LivebookProto.Response.decode(body) do
      %{id: -1, type: {:error, %{details: reason}}} ->
        {:response, :error, reason}

      %{id: id, type: {:error, %{details: reason}}} ->
        {:response, id, {:error, reason}}
    end
  end

  defp build_message({:error, %Mint.TransportError{} = reason}) do
    {:connect, :error, reason}
  end

  defp build_message({:error, reason}) do
    {:unknown, :error, reason}
  end
end
