defmodule Livebook.ZTA.Tailscale do
  @behaviour Livebook.ZTA
  require Logger

  @impl true
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    address = Keyword.fetch!(opts, :identity_key)

    if not String.starts_with?(address, "http") and
         not File.exists?(address) do
      Logger.error("Tailscale socket does not exist: #{inspect(address)}")
      raise "invalid Tailscale ZTA configuration"
    end

    Livebook.ZTA.put(name, address)
    :ignore
  end

  @impl true
  def authenticate(name, conn, _opts) do
    remote_ip = to_string(:inet_parse.ntoa(conn.remote_ip))
    tailscale_address = Livebook.ZTA.get(name)
    user = authenticate_ip(remote_ip, tailscale_address)
    {conn, user}
  end

  @impl true
  def logout(_name, _socket) do
    :error
  end

  defp authenticate_ip(remote_ip, address) do
    {url, options} =
      if String.starts_with?(address, "http") do
        uri = URI.parse(address)

        options =
          if uri.userinfo do
            # Req does not handle userinfo as part of the URL
            [auth: "Basic #{Base.encode64(uri.userinfo)}"]
          else
            []
          end

        url = to_string(%{uri | userinfo: nil, path: "/localapi/v0/whois?addr=#{remote_ip}:1"})

        {url, options}
      else
        {
          "http://local-tailscaled.sock/localapi/v0/whois?addr=#{remote_ip}:1",
          [
            unix_socket: address,
            # Req or Finch do not pass on the host from the URL when using a unix socket,
            # so we set the host header explicitly
            headers: [host: "local-tailscaled.sock"]
          ]
        }
      end

    with {:ok, response} <- Req.get(url, options),
         200 <- response.status,
         %{"UserProfile" => user} <- response.body do
      %{
        id: to_string(user["ID"]),
        name: user["DisplayName"],
        email: user["LoginName"]
      }
    else
      _ -> nil
    end
  end
end
