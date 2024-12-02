defmodule Livebook.Teams.Requests do
  alias Livebook.FileSystem
  alias Livebook.FileSystems
  alias Livebook.Hubs.Team
  alias Livebook.Secrets.Secret
  alias Livebook.Teams
  alias Livebook.Teams.{AppDeployment, DeploymentGroup, Org}

  @error_message "Something went wrong, try again later or please file a bug if it persists"

  @doc """
  Send a request to Livebook Team API to create a new org.
  """
  @spec create_org(Org.t()) ::
          {:ok, map()} | {:error, map() | String.t()} | {:transport_error, String.t()}
  def create_org(org) do
    post("/api/v1/org-request", %{name: org.name, key_hash: Org.key_hash(org)})
  end

  @doc """
  Send a request to Livebook Team API to join an org.
  """
  @spec join_org(Org.t()) ::
          {:ok, map()} | {:error, map() | String.t()} | {:transport_error, String.t()}
  def join_org(org) do
    post("/api/v1/org-request/join", %{name: org.name, key_hash: Org.key_hash(org)})
  end

  @doc """
  Send a request to Livebook Team API to get an org request.
  """
  @spec get_org_request_completion_data(pos_integer(), binary) ::
          {:ok, map()} | {:error, map() | String.t()} | {:transport_error, String.t()}
  def get_org_request_completion_data(id, device_code) do
    get("/api/v1/org-request/#{id}?device_code=#{device_code}")
  end

  @doc """
  Send a request to Livebook Team API to sign the given payload.
  """
  @spec org_sign(Team.t(), String.t()) ::
          {:ok, map()} | {:error, map() | String.t()} | {:transport_error, String.t()}
  def org_sign(team, payload) do
    post("/api/v1/org/sign", %{payload: payload}, team)
  end

  @doc """
  Send a request to Livebook Team API to create a secret.
  """
  @spec create_secret(Team.t(), Secret.t()) ::
          {:ok, map()} | {:error, map() | String.t()} | {:transport_error, String.t()}
  def create_secret(team, %{deployment_group_id: nil} = secret) do
    secret_key = Teams.derive_key(team.teams_key)
    secret_value = Teams.encrypt(secret.value, secret_key)

    post("/api/v1/org/secrets", %{name: secret.name, value: secret_value}, team)
  end

  def create_secret(team, secret) do
    secret_key = Teams.derive_key(team.teams_key)
    secret_value = Teams.encrypt(secret.value, secret_key)

    params = %{
      name: secret.name,
      value: secret_value,
      deployment_group_id: secret.deployment_group_id
    }

    post("/api/v1/org/deployment-groups/secrets", params, team)
  end

  @doc """
  Send a request to Livebook Team API to update a secret.
  """
  @spec update_secret(Team.t(), Secret.t()) ::
          {:ok, map()} | {:error, map() | String.t()} | {:transport_error, String.t()}
  def update_secret(team, %{deployment_group_id: nil} = secret) do
    secret_key = Teams.derive_key(team.teams_key)
    secret_value = Teams.encrypt(secret.value, secret_key)

    put("/api/v1/org/secrets", %{name: secret.name, value: secret_value}, team)
  end

  def update_secret(team, secret) do
    secret_key = Teams.derive_key(team.teams_key)
    secret_value = Teams.encrypt(secret.value, secret_key)

    params = %{
      name: secret.name,
      value: secret_value,
      deployment_group_id: secret.deployment_group_id
    }

    put("/api/v1/org/deployment-groups/secrets", params, team)
  end

  @doc """
  Send a request to Livebook Team API to delete a secret.
  """
  @spec delete_secret(Team.t(), Secret.t()) ::
          {:ok, map()} | {:error, map() | String.t()} | {:transport_error, String.t()}
  def delete_secret(team, %{deployment_group_id: nil} = secret) do
    delete("/api/v1/org/secrets", %{name: secret.name}, team)
  end

  def delete_secret(team, secret) do
    params = %{name: secret.name, deployment_group_id: secret.deployment_group_id}

    delete("/api/v1/org/deployment-groups/secrets", params, team)
  end

  @doc """
  Send a request to Livebook Team API to create a file system.
  """
  @spec create_file_system(Team.t(), FileSystem.t()) ::
          {:ok, map()} | {:error, map() | String.t()} | {:transport_error, String.t()}
  def create_file_system(team, file_system) do
    secret_key = Teams.derive_key(team.teams_key)

    type = FileSystems.type(file_system)
    %{name: name} = FileSystem.external_metadata(file_system)
    attrs = FileSystem.dump(file_system)
    json = Jason.encode!(attrs)

    params = %{
      name: name,
      type: to_string(type),
      value: Teams.encrypt(json, secret_key)
    }

    post("/api/v1/org/file-systems", params, team)
  end

  @doc """
  Send a request to Livebook Team API to update a file system.
  """
  @spec update_file_system(Team.t(), FileSystem.t()) ::
          {:ok, map()} | {:error, map() | String.t()} | {:transport_error, String.t()}
  def update_file_system(team, file_system) do
    secret_key = Teams.derive_key(team.teams_key)

    type = FileSystems.type(file_system)
    %{name: name} = FileSystem.external_metadata(file_system)
    attrs = FileSystem.dump(file_system)
    json = Jason.encode!(attrs)

    params = %{
      id: file_system.external_id,
      name: name,
      type: to_string(type),
      value: Teams.encrypt(json, secret_key)
    }

    put("/api/v1/org/file-systems", params, team)
  end

  @doc """
  Send a request to Livebook Team API to delete a file system.
  """
  @spec delete_file_system(Team.t(), FileSystem.t()) ::
          {:ok, map()} | {:error, map() | String.t()} | {:transport_error, String.t()}
  def delete_file_system(team, file_system) do
    delete("/api/v1/org/file-systems", %{id: file_system.external_id}, team)
  end

  @doc """
  Send a request to Livebook Team API to create a deployment group.
  """
  @spec create_deployment_group(Team.t(), DeploymentGroup.t()) ::
          {:ok, map()} | {:error, map() | String.t()} | {:transport_error, String.t()}
  def create_deployment_group(team, deployment_group) do
    params = %{
      name: deployment_group.name,
      mode: deployment_group.mode,
      clustering: deployment_group.clustering,
      zta_provider: deployment_group.zta_provider,
      url: deployment_group.url
    }

    post("/api/v1/org/deployment-groups", params, team)
  end

  @doc """
  Send a request to Livebook Team API to deploy an app.
  """
  @spec deploy_app(Team.t(), AppDeployment.t()) ::
          {:ok, map()} | {:error, map() | String.t()} | {:transport_error, String.t()}
  def deploy_app(team, app_deployment) do
    secret_key = Teams.derive_key(team.teams_key)

    params = %{
      title: app_deployment.title,
      slug: app_deployment.slug,
      multi_session: app_deployment.multi_session,
      access_type: app_deployment.access_type,
      deployment_group_id: app_deployment.deployment_group_id,
      sha: app_deployment.sha
    }

    encrypted_content = Teams.encrypt(app_deployment.file, secret_key)
    upload("/api/v1/org/apps", encrypted_content, params, team)
  end

  @doc """
  Send a request to Livebook Team API to download an app revision.
  """
  @spec download_revision(Team.t(), AppDeployment.t()) ::
          {:ok, binary()} | {:error, map() | String.t()} | {:transport_error, String.t()}
  def download_revision(team, app_deployment) do
    params = %{id: app_deployment.id, deployment_group_id: app_deployment.deployment_group_id}
    get("/api/v1/org/apps", params, team)
  end

  @doc """
  Send a request to Livebook Team API to create a new auth request.
  """
  @spec create_auth_request(Team.t()) ::
          {:ok, map()} | {:error, map() | String.t()} | {:transport_error, String.t()}
  def create_auth_request(team) do
    post("/api/v1/org/identity", %{}, team)
  end

  @doc """
  Send a request to Livebook Team API to get the access token from given auth request code.
  """
  @spec retrieve_access_token(Team.t(), String.t()) ::
          {:ok, map()} | {:error, map() | String.t()} | {:transport_error, String.t()}
  def retrieve_access_token(team, code) do
    post("/api/v1/org/identity/token", %{code: code}, team)
  end

  @doc """
  Send a request to Livebook Team API to get the user information from given access token.
  """
  @spec get_user_info(Team.t(), String.t()) ::
          {:ok, map()} | {:error, map() | String.t()} | {:transport_error, String.t()}
  def get_user_info(team, access_token) do
    get("/api/v1/org/identity", %{access_token: access_token}, team)
  end

  @doc """
  Send a request to Livebook Team API to get the user information from given access token.
  """
  @spec logout_identity_provider(Team.t(), String.t()) ::
          {:ok, String.t()} | {:error, map() | String.t()} | {:transport_error, String.t()}
  def logout_identity_provider(team, access_token) do
    delete("/api/v1/org/identity/logout", %{access_token: access_token}, team)
  end

  @doc """
  Normalizes errors map into errors for the given schema.
  """
  @spec to_error_list(module(), %{String.t() => list(String.t())}) ::
          list({atom(), list(String.t())})
  def to_error_list(struct, errors_map) do
    fields = struct.__schema__(:fields) |> MapSet.new()

    for {key, errors} <- errors_map,
        field = String.to_atom(key),
        field in fields,
        do: {field, errors}
  end

  @doc false
  def error_message(), do: @error_message

  defp post(path, json, team \\ nil) do
    build_req()
    |> add_team_auth(team)
    |> request(method: :post, url: path, json: json)
    |> dispatch_messages(team)
  end

  defp put(path, json, team) do
    build_req()
    |> add_team_auth(team)
    |> request(method: :put, url: path, json: json)
    |> dispatch_messages(team)
  end

  defp delete(path, json, team) do
    build_req()
    |> add_team_auth(team)
    |> request(method: :delete, url: path, json: json)
    |> dispatch_messages(team)
  end

  defp get(path, params \\ %{}, team \\ nil) do
    build_req()
    |> add_team_auth(team)
    |> request(method: :get, url: path, params: params)
  end

  defp upload(path, content, params, team) do
    build_req()
    |> add_team_auth(team)
    |> Req.Request.put_header("content-length", "#{byte_size(content)}")
    |> request(method: :post, url: path, params: params, body: content)
    |> dispatch_messages(team)
  end

  defp build_req() do
    base_url = URI.new!(Livebook.Config.teams_url())

    options =
      if userinfo = base_url.userinfo do
        [
          base_url: %{base_url | userinfo: nil},
          auth: {:basic, userinfo}
        ]
      else
        [
          base_url: base_url
        ]
      end

    Req.new([headers: [{"x-lb-version", Livebook.Config.app_version()}]] ++ options)
    |> Livebook.Utils.req_attach_defaults()
  end

  defp add_team_auth(req, nil), do: req

  defp add_team_auth(req, team) do
    if team.offline do
      Req.Request.append_request_steps(req,
        unauthorized: fn req ->
          {req, Req.Response.new(status: 401)}
        end
      )
    else
      token =
        if team.user_id do
          "#{team.user_id}:#{team.org_id}:#{team.org_key_id}:#{team.session_token}"
        else
          "#{team.session_token}:#{Livebook.Config.agent_name()}:#{team.org_id}:#{team.org_key_id}"
        end

      Req.Request.merge_options(req, auth: {:bearer, token})
    end
  end

  defp request(req, opts) do
    case Req.request(req, opts) do
      {:ok, %{status: 204, body: body}} ->
        {:ok, body}

      {:ok, %{status: status} = response} when status in 200..299 ->
        {:ok, response.body}

      {:ok, %{status: status} = response} when status in [410, 422] ->
        if json?(response),
          do: {:error, response.body},
          else: {:transport_error, response.body}

      {:ok, %{status: 401}} ->
        {:transport_error,
         "You are not authorized to perform this action, make sure you have the access and you are not in a Livebook App Server/Offline instance"}

      _otherwise ->
        {:transport_error, @error_message}
    end
  end

  defp dispatch_messages({:ok, %{"messages" => _} = body}, %Livebook.Hubs.Team{} = team) do
    {messages, body} = Map.pop!(body, "messages")

    for message <- messages do
      %{type: event} =
        message
        |> Base.url_decode64!(padding: false)
        |> LivebookProto.Event.decode()

      Livebook.Hubs.TeamClient.handle_event(team.id, event)
    end

    {:ok, body}
  end

  defp dispatch_messages(result, _), do: result

  defp json?(response) do
    "application/json; charset=utf-8" in Req.Response.get_header(response, "content-type")
  end
end
