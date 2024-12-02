defmodule Livebook.ZTA do
  @type name :: atom()

  @typedoc """
  A metadata of keys returned by zero-trust authentication provider.

  The following keys are supported:

    * `:id` - a string that uniquely identifies the user
    * `:name` - the user name
    * `:email` - the user email
    * `:payload` - the provider payload

  Note that none of the keys are required. The metadata returned depends
  on the provider.
  """
  @type metadata :: %{
          optional(:id) => String.t(),
          optional(:name) => String.t(),
          optional(:email) => String.t(),
          optional(:payload) => map()
        }

  @doc """
  Each provider must specify a child specification for its processes.

  The `:name` and `:identity_key` keys are expected.
  """
  @callback child_spec(name: name(), identity_key: String.t()) :: Supervisor.child_spec()

  @doc """
  Authenticates against the given name.

  It will return one of:

    * `{non_halted_conn, nil}` - the authentication failed and you must
      halt the connection and render the appropriate report

    * `{halted_conn, nil}` - the authentication failed and the connection
      was modified accordingly to request the credentials

    * `{non_halted_conn, metadata}` - the authentication succeed and the
      following metadata about the user is available

  """
  @callback authenticate(name(), Plug.Conn.t(), keyword()) :: {Plug.Conn.t(), metadata() | nil}

  @doc """
  Logouts against the given name.
  """
  @callback logout(name(), Phoenix.LiveView.Socket.t()) :: :ok | :error

  @doc false
  def init do
    :ets.new(__MODULE__, [:named_table, :public, :set, read_concurrency: true])
  end

  def get(name) do
    :ets.lookup_element(__MODULE__, name, 2)
  end

  def put(name, value) do
    :ets.insert(__MODULE__, [{name, value}])
  end
end
