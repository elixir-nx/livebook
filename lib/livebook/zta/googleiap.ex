defmodule Livebook.ZTA.GoogleIAP do
  @moduledoc false

  use GenServer
  require Logger
  import Plug.Conn

  @assertion "cf-access-jwt-assertion"
  @renew_afer 24 * 60 * 60 * 1000

  defstruct [:name, :req_options, :identity]

  def start_link(opts) do
    identity = identity(opts[:identity][:key])
    options = [req_options: [url: identity.certs], identity: identity]
    GenServer.start_link(__MODULE__, options, name: opts[:name])
  end

  def authenticate(name, conn) do
    token = get_req_header(conn, @assertion)
    GenServer.call(name, {:authenticate, token})
  end

  @impl true
  def init(options) do
    :ets.new(options[:name], [:public, :named_table])
    {:ok, struct!(__MODULE__, options)}
  end

  @impl true
  def handle_call(:get_keys, _from, state) do
    keys = get_from_ets(state.name) || request_and_store_in_ets(state)
    {:reply, keys, state}
  end

  def handle_call({:authenticate, token}, _from, state) do
    keys = get_from_ets(state.name) || request_and_store_in_ets(state)
    user = authenticate(token, state.identity, keys)
    {:reply, user, state}
  end

  @impl true
  def handle_info(:request, state) do
    request_and_store_in_ets(state)
    {:noreply, state}
  end

  defp request_and_store_in_ets(state) do
    Logger.debug("[#{inspect(__MODULE__)}] requesting #{inspect(state.req_options)}")
    keys = Req.request!(state.req_options).body["keys"]
    :ets.insert(state.name, keys: keys)
    Process.send_after(self(), :request, @renew_afer)
    keys
  end

  defp get_from_ets(name) do
    case :ets.lookup(name, :keys) do
      [keys: keys] -> keys
      [] -> nil
    end
  end

  defp authenticate(token, identity, keys) do
    with [token] <- token,
         {:ok, token} <- verify_token(token, keys),
         :ok <- verify_iss(token, identity.iss) do
      %{name: token.fields["email"]}
    else
      _ -> nil
    end
  end

  defp verify_token(token, keys) do
    Enum.find_value(keys, fn key ->
      case JOSE.JWT.verify(key, token) do
        {true, token, _s} -> {:ok, token}
        {_, _t, _s} -> nil
      end
    end)
  end

  defp verify_iss(%{fields: %{"iss" => iss}}, iss), do: :ok
  defp verify_iss(_, _), do: nil

  defp identity(key) do
    %{
      key: key,
      key_type: "aud",
      iss: "https://cloud.google.com/iap",
      certs: "https://www.gstatic.com/iap/verify/public_key",
      assertion: "x-goog-iap-jwt-assertion",
      email: "x-goog-authenticated-user-email"
    }
  end
end
