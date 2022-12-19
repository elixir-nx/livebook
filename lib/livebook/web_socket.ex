defmodule Livebook.WebSocket do
  @moduledoc false

  alias Livebook.WebSocket.Client

  defmodule Connection do
    defstruct [:conn, :websocket, :ref]

    @type t :: %__MODULE__{
            conn: Client.conn() | nil,
            websocket: Client.websocket() | nil,
            ref: Client.ref() | nil
          }
  end

  @type proto :: LivebookProto.SessionRequest.t()
  @typep headers :: Mint.Types.headers()

  @doc """
  Connects with the WebSocket server for given URL and headers.
  """
  @spec connect(String.t(), headers()) ::
          {:ok, Connection.t(), :connected | {atom(), proto()}}
          | {:error, Connection.t(), String.t() | LivebookProto.Error.t()}
  def connect(url, headers \\ []) do
    with {:ok, conn, ref} <- Client.connect(url, headers) do
      conn
      |> Client.receive(ref)
      |> handle_receive(ref)
    end
  end

  @doc """
  Disconnects the given WebSocket client.
  """
  @spec disconnect(Connection.t()) :: {:ok, Connection.t()} | {:error, Connection.t(), any()}
  def disconnect(%Connection{} = connection) do
    case Client.disconnect(connection.conn, connection.websocket, connection.ref) do
      {:ok, conn, websocket} ->
        {:ok, %{connection | conn: conn, websocket: websocket, ref: nil}}

      {:error, conn, websocket, reason} ->
        {:error, %{connection | conn: conn, websocket: websocket}, reason}
    end
  end

  @doc """
  Sends a request to the given server.
  """
  @spec send_request(Connection.t(), proto()) ::
          {:ok, Connection.t()}
          | {:error, Connection.t(), Client.ws_error() | Client.mint_error()}
  def send_request(%Connection{} = connection, data) do
    frame = LivebookProto.build_request_frame(data)

    case Client.send(connection.conn, connection.websocket, connection.ref, frame) do
      {:ok, conn, websocket} ->
        {:ok, %{connection | conn: conn, websocket: websocket}}

      {:error, conn, websocket, reason} ->
        {:error, %{connection | conn: conn, websocket: websocket}, reason}
    end
  end

  @doc """
  Receives a response from the given server.
  """
  @spec receive_response(Connection.t()) ::
          {:ok, Connection.t(), Client.Response.t() | :connect}
          | {:error, Connection.t(), Client.Response.t() | term()}
  def receive_response(%Connection{conn: conn, websocket: websocket, ref: ref}) do
    conn
    |> Client.receive(ref, websocket)
    |> handle_receive(ref)
  end

  defp handle_receive({:ok, conn, websocket, :connected}, ref) do
    {:ok, %Connection{conn: conn, websocket: websocket, ref: ref}, :connected}
  end

  defp handle_receive({:ok, conn, websocket, %Client.Response{body: response}}, ref) do
    %{type: result} = LivebookProto.Response.decode(response)
    {:ok, %Connection{conn: conn, websocket: websocket, ref: ref}, result}
  end

  defp handle_receive({:error, conn, websocket, %Client.Response{body: nil, status: status}}, ref) do
    {:error, %Connection{conn: conn, websocket: websocket, ref: ref},
     Plug.Conn.Status.reason_phrase(status)}
  end

  defp handle_receive({:error, conn, websocket, %Client.Response{body: response}}, ref) do
    %{type: {:error, error}} = LivebookProto.Response.decode(response)
    {:error, %Connection{conn: conn, websocket: websocket, ref: ref}, error}
  end

  defp handle_receive({:error, reason}, ref) do
    {:error, %Connection{ref: ref}, reason}
  end

  @doc """
  Subscribe to WebSocket Server events.

  ## Messages

    * `{:ok, pid, random_id, :connected}`
    * `{:ok, pid, random_id, %Livebook.WebSocket.Response{}}`
    * `{:error, pid, random_id, %Livebook.WebSocket.Response{}}`
    * `{:error, pid, random_id, reason}`

  """
  @spec subscribe() :: :ok | {:error, {:already_registered, pid()}}
  def subscribe do
    Phoenix.PubSub.subscribe(Livebook.PubSub, "websocket:clients")
  end

  @doc """
  Unsubscribes from `subscribe/0`.
  """
  @spec unsubscribe() :: :ok
  def unsubscribe do
    Phoenix.PubSub.unsubscribe(Livebook.PubSub, "websocket:clients")
  end

  @doc """
  Notifies interested processes about WebSocket Server messages.

  Broadcasts the given message under the `"websocket:clients"` topic.
  """
  @spec broadcast_message(any()) :: :ok
  def broadcast_message(message) do
    Phoenix.PubSub.broadcast(Livebook.PubSub, "websocket:clients", message)
  end
end
