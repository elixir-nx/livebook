defmodule Livebook.Hubs.Dockerfile do
  # This module is responsible for building Dockerfile to deploy apps.

  import Ecto.Changeset

  alias Livebook.Hubs

  @type config :: %{
          deploy_all: boolean(),
          docker_tag: String.t(),
          clustering: nil | :fly_io,
          zta_provider: atom() | nil,
          zta_key: String.t() | nil
        }

  @doc """
  Builds a changeset for app Dockerfile configuration.
  """
  @spec config_changeset(map()) :: Ecto.Changeset.t()
  def config_changeset(attrs \\ %{}) do
    default_image = Livebook.Config.docker_images() |> hd()

    data = %{
      deploy_all: false,
      docker_tag: default_image.tag,
      clustering: nil,
      zta_provider: nil,
      zta_key: nil
    }

    zta_types =
      for provider <- Livebook.Config.identity_providers(),
          do: provider.type

    types = %{
      deploy_all: :boolean,
      docker_tag: :string,
      clustering: Ecto.ParameterizedType.init(Ecto.Enum, values: [:fly_io]),
      zta_provider: Ecto.ParameterizedType.init(Ecto.Enum, values: zta_types),
      zta_key: :string
    }

    cast({data, types}, attrs, [:deploy_all, :docker_tag, :clustering, :zta_provider, :zta_key])
    |> validate_required([:deploy_all, :docker_tag])
  end

  @doc """
  Builds Dockerfile definition for app deployment.
  """
  @spec build_dockerfile(
          config(),
          Hubs.Provider.t(),
          list(Livebook.Secrets.Secret.t()),
          list(Livebook.FileSystem.t()),
          Livebook.FileSystem.File.t() | nil,
          list(Livebook.Notebook.file_entry()),
          Livebook.Session.Data.secrets()
        ) :: String.t()
  def build_dockerfile(config, hub, hub_secrets, hub_file_systems, file, file_entries, secrets) do
    base_image = Enum.find(Livebook.Config.docker_images(), &(&1.tag == config.docker_tag))

    image = """
    FROM ghcr.io/livebook-dev/livebook:#{base_image.tag}
    """

    image_envs = format_envs(base_image.env)

    hub_type = Hubs.Provider.type(hub)
    used_secrets = used_hub_secrets(config, hub_secrets, secrets) |> Enum.sort_by(& &1.name)
    hub_config = format_hub_config(hub_type, config, hub, hub_file_systems, used_secrets)

    apps_config = """
    # Apps configuration
    ENV LIVEBOOK_APPS_PATH "/apps"
    ENV LIVEBOOK_APPS_PATH_WARMUP "manual"
    ENV LIVEBOOK_APPS_PATH_HUB_ID "#{hub.id}"
    """

    notebook =
      if config.deploy_all do
        """
        # Notebooks and files
        COPY . /apps
        """
      else
        notebook_file_name = Livebook.FileSystem.File.name(file)

        notebook =
          """
          # Notebook
          COPY #{notebook_file_name} /apps/
          """

        attachments =
          file_entries
          |> Enum.filter(&(&1.type == :attachment))
          |> Enum.sort_by(& &1.name)

        if attachments == [] do
          notebook
        else
          list = Enum.map_join(attachments, " ", &"files/#{&1.name}")

          """
          # Files
          COPY #{list} /apps/files/

          #{notebook}\
          """
        end
      end

    apps_warmup = """
    # Cache apps setup at build time
    RUN /app/bin/warmup_apps
    """

    random_secret_key_base = Livebook.Utils.random_secret_key_base()
    random_cookie = Livebook.Utils.random_cookie()

    startup =
      if config.clustering == :fly_io do
        """
        # --- Clustering ---

        # Set the same Livebook secrets across all nodes
        ENV LIVEBOOK_SECRET_KEY_BASE "#{random_secret_key_base}"
        ENV LIVEBOOK_COOKIE "#{random_cookie}"

        """ <>
          ~S"""
          # Runtime configuration to cluster multiple Livebook nodes on Fly.io
          RUN printf '\
          export ERL_AFLAGS="-proto_dist inet6_tcp"\n\
          export LIVEBOOK_NODE="${FLY_APP_NAME}-${FLY_IMAGE_REF##*-}@${FLY_PRIVATE_IP}"\n\
          export LIVEBOOK_CLUSTER="dns:${FLY_APP_NAME}.internal"\n\
          ' > /app/user/env.sh
          """
      end

    [
      image,
      image_envs,
      hub_config,
      apps_config,
      notebook,
      apps_warmup,
      startup
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp format_hub_config("team", config, hub, hub_file_systems, used_secrets) do
    base_env =
      """
      ARG TEAMS_KEY="#{hub.teams_key}"

      # Teams Hub configuration for airgapped deployment
      ENV LIVEBOOK_TEAMS_KEY ${TEAMS_KEY}
      ENV LIVEBOOK_TEAMS_AUTH "offline:#{hub.hub_name}:#{hub.org_public_key}"
      """

    secrets =
      if used_secrets != [] do
        """
        ENV LIVEBOOK_TEAMS_SECRETS "#{encrypt_secrets_to_dockerfile(used_secrets, hub)}"
        """
      end

    file_systems =
      if hub_file_systems != [] do
        """
        ENV LIVEBOOK_TEAMS_FS "#{encrypt_file_systems_to_dockerfile(hub_file_systems, hub)}"
        """
      end

    zta =
      if zta_configured?(config) do
        """
        ENV LIVEBOOK_IDENTITY_PROVIDER "#{config.zta_provider}:#{config.zta_key}"
        """
      end

    [base_env, secrets, file_systems, zta]
    |> Enum.reject(&is_nil/1)
    |> Enum.join()
  end

  defp format_hub_config("personal", _config, _hub, _hub_file_systems, used_secrets) do
    if used_secrets != [] do
      envs = used_secrets |> Enum.map(&{"LB_" <> &1.name, &1.value}) |> format_envs()

      """
      # Personal Hub secrets
      #{envs}\
      """
    end
  end

  defp format_envs([]), do: nil

  defp format_envs(list) do
    Enum.map_join(list, fn {key, value} -> ~s/ENV #{key} "#{value}"\n/ end)
  end

  defp encrypt_secrets_to_dockerfile(secrets, hub) do
    secrets_map =
      for %{name: name, value: value} <- secrets,
          into: %{},
          do: {name, value}

    encrypt_to_dockerfile(hub, secrets_map)
  end

  defp encrypt_file_systems_to_dockerfile(file_systems, hub) do
    file_systems =
      for file_system <- file_systems do
        file_system
        |> Livebook.FileSystem.dump()
        |> Map.put_new(:type, Livebook.FileSystems.type(file_system))
      end

    encrypt_to_dockerfile(hub, file_systems)
  end

  defp encrypt_to_dockerfile(hub, data) do
    secret_key = Livebook.Teams.derive_key(hub.teams_key)

    data
    |> Jason.encode!()
    |> Livebook.Teams.encrypt(secret_key)
  end

  defp used_hub_secrets(config, hub_secrets, secrets) do
    if config.deploy_all do
      hub_secrets
    else
      Enum.filter(hub_secrets, fn hub_secret ->
        if secret = secrets[hub_secret.name] do
          secret.hub_id == hub_secret.hub_id
        end
      end)
    end
  end

  defp used_hub_file_systems(config, hub_file_systems, file_entries) do
    if config.deploy_all do
      hub_file_systems
    else
      file_entry_file_system_ids =
        for entry <- file_entries,
            entry.type == :file,
            do: entry.file.file_system_id,
            into: MapSet.new()

      Enum.filter(hub_file_systems, &(&1.id in file_entry_file_system_ids))
    end
  end

  defp zta_configured?(config) do
    config.zta_provider != nil and config.zta_key != nil
  end

  @doc """
  Returns a list of Dockerfile-related warnings.

  The returned messages may include HTML.
  """
  @spec warnings(
          config(),
          Hubs.Provider.t(),
          list(Livebook.Secrets.Secret.t()),
          list(Livebook.FileSystem.t()),
          Livebook.Notebook.AppSettings.t(),
          list(Livebook.Notebook.file_entry()),
          Livebook.Session.Data.secrets()
        ) :: list(String.t())
  def warnings(config, hub, hub_secrets, hub_file_systems, app_settings, file_entries, secrets) do
    common_warnings =
      [
        if Livebook.Session.Data.session_secrets(secrets, hub.id) != [] do
          "The notebook uses session secrets, but those are not available to deployed apps." <>
            " Convert them to Hub secrets instead."
        end
      ]

    hub_warnings =
      case Hubs.Provider.type(hub) do
        "personal" ->
          used_hub_secrets = used_hub_secrets(config, hub_secrets, secrets)
          used_hub_file_systems = used_hub_file_systems(config, hub_file_systems, file_entries)

          [
            if used_hub_secrets != [] do
              "You are deploying an app with secrets and the secrets are included in the Dockerfile" <>
                " as environment variables. If someone else deploys this app, they must also set the" <>
                " same secrets. Use Livebook Teams to automatically encrypt and synchronize secrets" <>
                " across your team and deployments."
            end,
            if used_hub_file_systems != [] do
              %module{} = hd(used_hub_file_systems)
              name = LivebookWeb.FileSystemComponents.file_system_name(module)

              "The #{name} file storage, defined in your personal hub, will not be available in the Docker image." <>
                " You must either download all references as attachments or use Livebook Teams to automatically" <>
                " encrypt and synchronize file storages across your team and deployments."
            end,
            if app_settings.access_type == :public do
              teams_link =
                ~s{<a class="font-medium underline text-gray-900 hover:no-underline" href="https://livebook.dev/teams?ref=LivebookApp" target="_blank">Livebook Teams</a>}

              "This app has no password configuration and anyone with access to the server will be able" <>
                " to use it. You may either configure a password or use #{teams_link} to add Zero Trust Authentication" <>
                " to your deployed notebooks."
            end
          ]

        "team" ->
          [
            if app_settings.access_type == :public and not zta_configured?(config) do
              "This app has no password configuration and anyone with access to the server will be able" <>
                " to use it. You may either configure a password or configure Zero Trust Authentication."
            end
          ]
      end

    Enum.reject(common_warnings ++ hub_warnings, &is_nil/1)
  end
end
