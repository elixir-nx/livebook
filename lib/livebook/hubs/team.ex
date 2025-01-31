defmodule Livebook.Hubs.Team do
  use Ecto.Schema
  import Ecto.Changeset

  defmodule Offline do
    use Ecto.Schema

    @type t :: %__MODULE__{
            file_systems: list(Livebook.FileSystem.t()),
            secrets: list(Livebook.Secrets.Secret.t())
          }

    @primary_key false
    embedded_schema do
      field :secrets, {:array, :map}, default: []
      field :file_systems, {:array, :map}, default: []
    end
  end

  @type t :: %__MODULE__{
          id: String.t() | nil,
          org_id: non_neg_integer() | nil,
          user_id: non_neg_integer() | nil,
          org_key_id: non_neg_integer() | nil,
          teams_key: String.t() | nil,
          org_public_key: String.t() | nil,
          session_token: String.t() | nil,
          hub_name: String.t() | nil,
          hub_emoji: String.t() | nil,
          offline: Offline.t() | nil
        }

  @enforce_keys [:org_id, :org_key_id, :session_token, :teams_key]

  embedded_schema do
    field :org_id, :integer
    field :user_id, :integer
    field :org_key_id, :integer
    field :teams_key, :string
    field :org_public_key, :string
    field :session_token, :string, redact: true
    field :hub_name, :string
    field :hub_emoji, :string
    field :trial_ends_at, :utc_datetime
    field :cancel_at, :utc_datetime

    embeds_one :offline, Offline
  end

  @fields ~w(
    org_id
    user_id
    org_key_id
    teams_key
    org_public_key
    session_token
    hub_name
    hub_emoji
  )a

  @editable_fields ~w(hub_emoji)a

  @doc """
  Initializes a new Team hub.
  """
  @spec new() :: t()
  def new() do
    %__MODULE__{
      user_id: nil,
      org_id: nil,
      org_key_id: nil,
      session_token: nil,
      org_public_key: nil,
      teams_key: nil
    }
  end

  def creation_changeset(team, attrs) do
    team
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> add_id()
  end

  def update_changeset(team, attrs) do
    team
    |> cast(attrs, @editable_fields)
    |> validate_required(@editable_fields)
  end

  defp add_id(changeset) do
    if name = get_field(changeset, :hub_name) do
      change(changeset, %{id: "team-#{name}"})
    else
      changeset
    end
  end

  @doc """
  Returns the public key prefix
  """
  @spec public_key_prefix() :: String.t()
  def public_key_prefix(), do: "lb_opk_"

  @doc """
  Returns the billing info.
  """
  def billing_info(%__MODULE__{trial_ends_at: %DateTime{} = datetime}) do
    days = Date.diff(datetime, Date.utc_today())

    if days > 0 do
      %{disabled?: false, status: :trial_until, trial_days_left: days}
    else
      %{disabled?: true, status: :trial_ended}
    end
  end

  def billing_info(%__MODULE__{cancel_at: %DateTime{} = datetime}) do
    if DateTime.after?(datetime, DateTime.utc_now()) do
      %{disabled?: false, status: :active_until}
    else
      %{disabled?: true, status: :canceled}
    end
  end

  def billing_info(%__MODULE__{}) do
    %{disabled?: false, status: :active}
  end
end

defimpl Livebook.Hubs.Provider, for: Livebook.Hubs.Team do
  alias Livebook.Hubs.{Team, TeamClient}
  alias Livebook.Teams.Requests
  alias Livebook.FileSystem
  alias Livebook.Secrets.Secret

  @teams_key_prefix Livebook.Teams.Org.teams_key_prefix()
  @public_key_prefix Livebook.Hubs.Team.public_key_prefix()

  def load(team, fields) do
    {offline?, fields} = Map.pop(fields, :offline?, false)

    # We don't want to persist offline in storage, so we read from persistent term
    offline =
      if offline? do
        :persistent_term.get({__MODULE__, :offline, fields.id})
      end

    team
    |> struct(fields)
    |> Map.replace!(:offline, offline)
  end

  def to_metadata(team) do
    %Livebook.Hubs.Metadata{
      id: team.id,
      name: team.hub_name,
      provider: team,
      emoji: team.hub_emoji,
      connected?: TeamClient.connected?(team.id)
    }
  end

  def type(_team), do: "team"

  def connection_spec(team), do: {TeamClient, team}

  def disconnect(team), do: TeamClient.stop(team.id)

  def connection_status(team) do
    cond do
      team.offline ->
        "You are running an offline Workspace for deployment. You cannot modify its settings."

      team.user_id == nil ->
        "You are running a Livebook app server. This workspace is in read-only mode."

      reason = TeamClient.get_connection_status(team.id) ->
        "Cannot connect to Teams: #{reason}.\nWill attempt to reconnect automatically..."

      true ->
        nil
    end
  end

  def notebook_stamp(team, notebook_source, metadata) do
    # We apply authenticated encryption using the shared teams key,
    # just as for the personal hub, but we additionally sign the token
    # with a private organization key stored on the Teams server. We
    # then validate the signature using the corresponding public key.
    #
    # This results in a two factor mechanism, where creating a valid
    # stamp requires access to the shared local key and an authenticated
    # request to the Teams server (which ensures team membership).

    @teams_key_prefix <> teams_key = team.teams_key
    token = Livebook.Stamping.chapoly_encrypt(metadata, notebook_source, teams_key)

    case Requests.org_sign(team, token) do
      {:ok, %{"signature" => token_signature}} ->
        stamp = %{"version" => 1, "token" => token, "token_signature" => token_signature}
        {:ok, stamp}

      _ ->
        {:error, "request to Livebook Teams failed"}
    end
  end

  def verify_notebook_stamp(team, notebook_source, stamp) do
    %{"version" => 1, "token" => token, "token_signature" => token_signature} = stamp

    @teams_key_prefix <> teams_key = team.teams_key
    @public_key_prefix <> org_public_key = team.org_public_key

    if Livebook.Stamping.rsa_verify?(token_signature, token, org_public_key) do
      Livebook.Stamping.chapoly_decrypt(token, notebook_source, teams_key)
    else
      {:error, :invalid}
    end
  end

  def dump(team) do
    # Offline hub is kept in storage, but only during the lifetime of
    # the runtime (we remove it on the subsequent startup). With this
    # assumption we can safely store the %Offline{} struct in memory,
    # so that the secrets are never written to disk.
    if team.offline do
      :persistent_term.put({__MODULE__, :offline, team.id}, team.offline)
    end

    team
    |> Map.from_struct()
    |> Map.delete(:offline)
    |> Map.put(:offline?, team.offline != nil)
  end

  def get_secrets(team), do: TeamClient.get_secrets(team.id)

  def create_secret(%Team{} = team, %Secret{} = secret) do
    case Requests.create_secret(team, secret) do
      {:ok, %{"id" => _}} -> :ok
      {:error, %{"errors" => errors}} -> {:error, parse_secret_errors(errors)}
      any -> any
    end
  end

  def update_secret(%Team{} = team, %Secret{} = secret) do
    case Requests.update_secret(team, secret) do
      {:ok, %{"id" => _}} -> :ok
      {:error, %{"errors" => errors}} -> {:error, parse_secret_errors(errors)}
      any -> any
    end
  end

  def delete_secret(%Team{} = team, %Secret{} = secret) do
    case Requests.delete_secret(team, secret) do
      {:ok, _} -> :ok
      {:error, %{"errors" => errors}} -> {:error, parse_secret_errors(errors)}
      any -> any
    end
  end

  def get_file_systems(team), do: TeamClient.get_file_systems(team.id)

  def create_file_system(%Team{} = team, file_system) do
    case Requests.create_file_system(team, file_system) do
      {:ok, %{"id" => _}} -> :ok
      {:error, %{"errors" => errors}} -> {:error, parse_file_system_errors(file_system, errors)}
      any -> any
    end
  end

  def update_file_system(%Team{} = team, file_system) do
    case Requests.update_file_system(team, file_system) do
      {:ok, %{"id" => _}} -> :ok
      {:error, %{"errors" => errors}} -> {:error, parse_file_system_errors(file_system, errors)}
      any -> any
    end
  end

  def delete_file_system(%Team{} = team, file_system) do
    case Requests.delete_file_system(team, file_system) do
      {:ok, _} -> :ok
      {:error, %{"errors" => errors}} -> {:error, parse_file_system_errors(file_system, errors)}
      any -> any
    end
  end

  def deployment_groups(team), do: TeamClient.get_deployment_groups(team.id)

  def get_app_specs(team) do
    for app_deployment <- TeamClient.get_agent_app_deployments(team.id) do
      %Livebook.Apps.TeamsAppSpec{
        slug: app_deployment.slug,
        version: app_deployment.version,
        hub_id: app_deployment.hub_id,
        app_deployment_id: app_deployment.id
      }
    end
  end

  defp parse_secret_errors(errors_map) do
    Requests.to_error_list(Secret, errors_map)
  end

  defp parse_file_system_errors(%struct{} = file_system, errors_map) do
    %{error_field: field} = FileSystem.external_metadata(file_system)
    errors_map = Map.new(errors_map, fn {_key, values} -> {field, values} end)
    Requests.to_error_list(struct, errors_map)
  end
end
