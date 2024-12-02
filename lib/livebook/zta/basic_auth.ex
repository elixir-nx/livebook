defmodule Livebook.ZTA.BasicAuth do
  @behaviour Livebook.ZTA

  @impl true
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(options) do
    name = Keyword.fetch!(options, :name)
    identity_key = Keyword.fetch!(options, :identity_key)
    [username, password] = String.split(identity_key, ":", parts: 2)

    Livebook.ZTA.put(name, {username, password})
    :ignore
  end

  @impl true
  def authenticate(name, conn, _opts) do
    {username, password} = Livebook.ZTA.get(name)
    conn = Plug.BasicAuth.basic_auth(conn, username: username, password: password)

    if conn.halted do
      {conn, nil}
    else
      {conn, %{}}
    end
  end

  @impl true
  def logout(_name, _socket) do
    :error
  end
end
