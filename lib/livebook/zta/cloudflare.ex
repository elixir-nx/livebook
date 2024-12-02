defmodule Livebook.ZTA.Cloudflare do
  @behaviour Livebook.ZTA

  use GenServer
  require Logger
  import Plug.Conn

  @assertion "cf-access-jwt-assertion"
  @renew_after 24 * 60 * 60 * 1000
  @fields %{"user_uuid" => :id, "name" => :name, "email" => :email}

  defstruct [:req_options, :identity, :name]

  def start_link(opts) do
    identity = opts[:custom_identity] || identity(opts[:identity_key])
    name = Keyword.fetch!(opts, :name)
    options = [req_options: [url: identity.certs], identity: identity, name: name]
    GenServer.start_link(__MODULE__, options, name: name)
  end

  @impl true
  def authenticate(name, conn, _opts) do
    token = get_req_header(conn, @assertion)
    {identity, keys} = Livebook.ZTA.get(name)
    {conn, authenticate_user(token, identity, keys)}
  end

  @impl true
  def logout(_name, _socket) do
    :error
  end

  @impl true
  def init(options) do
    state = struct!(__MODULE__, options)
    {:ok, renew(state)}
  end

  @impl true
  def handle_info(:renew, state) do
    {:noreply, renew(state)}
  end

  defp renew(state) do
    Logger.debug("[#{inspect(__MODULE__)}] requesting #{inspect(state.req_options)}")
    keys = Req.request!(state.req_options).body["keys"]
    Process.send_after(self(), :renew, @renew_after)
    Livebook.ZTA.put(state.name, {state.identity, keys})
    state
  end

  defp authenticate_user(token, identity, keys) do
    with [encoded_token] <- token,
         {:ok, token} <- verify_token(encoded_token, keys),
         :ok <- verify_iss(token, identity.iss),
         {:ok, user} <- get_user_identity(encoded_token, identity.user_identity) do
      for({k, v} <- user, new_k = @fields[k], do: {new_k, v}, into: %{payload: token.fields})
    else
      _ -> nil
    end
  end

  defp verify_token(token, keys) do
    Enum.find_value(keys, :error, fn key ->
      case JOSE.JWT.verify(key, token) do
        {true, token, _s} -> {:ok, token}
        _ -> nil
      end
    end)
  end

  defp verify_iss(%{fields: %{"iss" => iss}}, iss), do: :ok
  defp verify_iss(_, _), do: :error

  defp get_user_identity(token, url) do
    cookie = "CF_Authorization=#{token}"
    resp = Req.request!(url: url, headers: [cookie: cookie])
    if resp.status == 200, do: {:ok, resp.body}, else: :error
  end

  defp identity(key) do
    %{
      key: key,
      key_type: "domain",
      iss: "https://#{key}.cloudflareaccess.com",
      certs: "https://#{key}.cloudflareaccess.com/cdn-cgi/access/certs",
      assertion: "cf-access-jwt-assertion",
      email: "cf-access-authenticated-user-email",
      user_identity: "https://#{key}.cloudflareaccess.com/cdn-cgi/access/get-identity"
    }
  end
end
