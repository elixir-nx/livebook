defmodule LivebookWeb.SessionLive.K8sRuntimeComponent do
  use LivebookWeb, :live_component

  import Ecto.Changeset

  alias Livebook.{Session, Runtime}
  alias Livebook.K8s.{Auth, Pod, PVC}

  @config_secret_prefix "K8S_RUNTIME_"
  @kubeconfig_pipeline Application.compile_env(:livebook, :k8s_kubeconfig_pipeline)

  @impl true
  def mount(socket) do
    unless Livebook.Config.runtime_enabled?(Livebook.Runtime.K8s) do
      raise "runtime module not allowed"
    end

    kubeconfig = Kubereq.Kubeconfig.load(@kubeconfig_pipeline)
    context_options = Enum.map(kubeconfig.contexts, & &1["name"])

    {:ok,
     socket
     |> assign(
       kubeconfig: kubeconfig,
       context_options: context_options,
       context: nil,
       reqs: nil,
       cluster_check: %{status: :initial, error: nil},
       namespace: nil,
       namespace_options: nil,
       rbac: %{status: :inflight, errors: [], permissions: []},
       save_config: nil,
       pvcs: nil,
       pvc_action: nil,
       home_pvc: nil,
       docker_tag: hd(Livebook.Config.docker_images()).tag,
       pod_template: %{template: Pod.default_pod_template(), status: :valid, message: nil}
     )}
  end

  @impl true
  @spec update(maybe_improper_list() | map(), any()) :: {:ok, any()}
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      cond do
        is_map_key(socket.assigns, :config_defaults) ->
          socket

        is_struct(assigns.runtime, Runtime.K8s) ->
          %{config: config} = assigns.runtime

          config_defaults =
            Map.new(config, fn {key, value} ->
              {Atom.to_string(key), value}
            end)

          socket
          |> assign(config_defaults: config_defaults)
          |> load_config_defaults()

        true ->
          socket
          |> assign(config_defaults: nil)
          |> set_context(socket.assigns.kubeconfig.current_context)
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <p class="text-gray-700">
        Start a temporary Kubernetes Pod with an Elixir node to evaluate code.
        The Pod is automatically deleted, once you disconnect the runtime.
      </p>

      <.save_config_form :if={@save_config} save_config={@save_config} hub={@hub} myself={@myself} />

      <div :if={@save_config == nil}>
        <.config_actions hub_secrets={@hub_secrets} myself={@myself} />

        <.message_box :if={@kubeconfig.current_cluster == nil} kind={:error}>
          In order to use the Kubernetes context, you need to set the <code>KUBECONFIG</code>
          environment variable to a path pointing to a <a
            class="text-blue-600 hover:text-blue-700"
            href="https://kubernetes.io/docs/reference/config-api/kubeconfig.v1/"
            phx-no-format
          >Kubernetes configuration</a> YAML file (e.g. to <code>"~/.kube/config"</code>).
        </.message_box>

        <form
          :if={@context_options != []}
          phx-change="set_context"
          phx-nosubmit
          phx-target={@myself}
          class="mt-1"
        >
          <.select_field name="context" value={@context} label="Context" options={@context_options} />
        </form>

        <.loader :if={@cluster_check.status == :inflight} />

        <.cluster_check_error :if={@cluster_check.status == :error} error={@cluster_check.error} />

        <form
          :if={@cluster_check.status == :ok}
          phx-change="set_namespace"
          phx-nosubmit
          phx-target={@myself}
          class="mt-4"
        >
          <.select_field
            :if={@namespace_options != nil}
            name="namespace"
            value={@namespace}
            label="Namespace"
            options={@namespace_options}
          />
          <div :if={@namespace_options == nil}>
            <.text_field name="namespace" value={@namespace} label="Namespace" phx-debounce="600" />
            <div class="text-sm text-amber-600">
              Authenticated user has no permission to list namespaces. But you can enter a name of an existing namespace.
            </div>
          </div>
        </form>

        <.message_box :if={@rbac.status === :errors} kind={:error}>
          <%= for error <- @rbac.errors do %>
            <.rbac_error error={error} />
          <% end %>
        </.message_box>

        <div :if={@rbac.status == :ok} class="mt-8">
          <div class="text-lg text-gray-800 font-semibold">
            Pod
          </div>
          <div class="mt-1 text-gray-700">
            You can fully customize the runtime pod by editing the pod template.
          </div>
          <form
            :if={@cluster_check.status == :ok}
            phx-change="set_docker_tag"
            phx-nosubmit
            phx-target={@myself}
            class="mt-4"
          >
            <.radio_field
              :if={@rbac.status == :ok}
              name="docker_tag"
              value={@docker_tag}
              label="Base Docker image"
              options={LivebookWeb.AppComponents.docker_tag_options()}
            />
          </form>
          <form
            :if={@cluster_check.status == :ok}
            phx-change="set_pod_template"
            phx-nosubmit
            phx-target={@myself}
            class="mt-4"
          >
            <.textarea_field
              name="pod_template"
              label="Template"
              value={@pod_template.template}
              phx-debounce={500}
              monospace={true}
              phx-hook="TextareaAutosize"
            />

            <.message_box :if={@pod_template.status != :valid} kind={@pod_template.status}>
              <div class="flex items-center gap-2">
                <span><%= @pod_template.message %></span>
              </div>
            </.message_box>
          </form>
        </div>

        <.storage_config
          :if={@rbac.status == :ok}
          myself={@myself}
          home_pvc={@home_pvc}
          pvcs={@pvcs}
          pvc_action={@pvc_action}
          rbac={@rbac}
        />

        <div :if={@rbac.status == :ok} class="mt-8">
          <div class="flex gap-2">
            <.button phx-click="init" phx-target={@myself} disabled={@runtime_status == :connecting}>
              <%= label(@namespace, @runtime, @runtime_status) %>
            </.button>
            <.button
              :if={@runtime_status == :connecting}
              color="red"
              outlined
              phx-click="disconnect"
              phx-target={@myself}
            >
              Disconnect
            </.button>
          </div>
          <div
            :if={reconnecting?(@namespace, @runtime) && @runtime_connect_info}
            class="mt-4 scroll-mb-8"
            phx-mounted={JS.dispatch("lb:scroll_into_view", detail: %{behavior: "instant"})}
          >
            <.message_box kind={:info}>
              <div class="flex items-center gap-2">
                <.spinner />
                <span>Step: <%= @runtime_connect_info %></span>
              </div>
            </.message_box>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp storage_config(assigns) do
    ~H"""
    <div class="mt-8">
      <div class="text-lg text-gray-800 font-semibold">
        Storage
      </div>
      <div class="mt-1 text-gray-700">
        Every time you connect to the runtime, a fresh machine is created.
        In order to persist data and caches, you can optionally mount a
        volume at <code>/home/livebook</code>. Setting a Persistent Volume
        Claim will automatically add a <code>.template.spec.volumes[]</code>
        entry and a <code>.template.spec.containers[name="livebook-runtime"].volumeMounts[]</code>
        entry to the pod template.
      </div>

      <div class="mt-4 flex flex-col">
        <div class="flex items-start gap-1">
          <form phx-change="set_home_pvc" phx-target={@myself} class="grow">
            <.select_field
              :if={@rbac.permissions.list_pvc}
              value={@home_pvc}
              name="home_pvc"
              label="Persistent Volume Claim"
              options={[{"None", nil} | @pvcs]}
            />
            <div :if={!@rbac.permissions.list_pvc}>
              <.text_field value={@home_pvc} name="home_pvc" label="Persistent Volume Claim" />
              <div class="text-sm text-amber-600">
                Authenticated user has no permission to list PVCs. But you can enter a name of an existing PVC to be attached.
              </div>
            </div>
          </form>

          <div class="mt-7 flex items-center gap-1">
            <span
              :if={@rbac.permissions.delete_pvc}
              class="tooltip left"
              data-tooltip="Delete selected PVC"
            >
              <.icon_button
                phx-click="delete_pvc"
                phx-target={@myself}
                disabled={@home_pvc == nil or @pvc_action != nil}
              >
                <.remix_icon icon="delete-bin-6-line" />
              </.icon_button>
            </span>
            <span
              :if={@rbac.permissions.create_pvc}
              class="tooltip left"
              data-tooltip="Create new PVC"
            >
              <.icon_button phx-click="new_pvc" phx-target={@myself}>
                <.remix_icon icon="add-line" />
              </.icon_button>
            </span>
          </div>
        </div>
        <div
          :if={@pvc_action[:type] in [:delete, :delete_inflight]}
          class="px-4 py-3 mt-4 flex space-x-4 items-center border border-gray-200 rounded-lg"
        >
          <p class="grow text-gray-700 text-sm">
            Are you sure you want to irreversibly delete Persistent Volume Claim <span class="font-semibold"><%= @home_pvc %></span>?
          </p>
          <div class="flex space-x-4">
            <button
              class="text-red-600 font-medium text-sm whitespace-nowrap"
              phx-click="confirm_delete_pvc"
              phx-target={@myself}
              disabled={@pvc_action[:type] == :delete_inflight}
            >
              <.remix_icon icon="delete-bin-6-line" class="align-middle mr-1" />
              <%= if @pvc_action[:type] == :delete, do: "Delete", else: "Deleting..." %>
            </button>
            <button
              class="text-gray-600 font-medium text-sm"
              phx-click="cancel_delete_pvc"
              phx-target={@myself}
              disabled={@pvc_action[:type] == :delete_inflight}
            >
              Cancel
            </button>
          </div>
        </div>

        <.form
          :let={pvcf}
          :if={@pvc_action[:type] in [:new, :new_inflight]}
          for={@pvc_action.changeset}
          as={:pvc}
          phx-submit="create_pvc"
          phx-change="validate_pvc"
          phx-target={@myself}
          class="flex gap-2 mt-4 items-center"
          autocomplete="off"
          spellcheck="false"
        >
          <div>
            <.remix_icon icon="corner-down-right-line" class="text-gray-400 text-lg" />
          </div>
          <div class="grid grid-cols-4 gap-2 grow">
            <.text_field field={pvcf[:name]} placeholder="Name" />
            <.text_field field={pvcf[:size_gb]} placeholder="Size (Gi)" type="number" min="1" />
            <.select_field
              field={pvcf[:access_mode]}
              options={["ReadWriteOnce", "ReadWriteMany", "ReadWriteOncePod"]}
            />
            <.select_field field={pvcf[:storage_class]} options={@pvc_action.storage_classes} />
          </div>
          <.button
            :if={@pvc_action[:type] == :new}
            type="submit"
            disabled={not @pvc_action.changeset.valid? or @pvc_action[:type] == :new_inflight}
          >
            <%= if @pvc_action[:type] == :new, do: "Create", else: "Creating..." %>
          </.button>
          <.button
            :if={@pvc_action[:type] == :new}
            type="button"
            color="gray"
            outlined
            phx-click="cancel_new_pvc"
            phx-target={@myself}
            disabled={@pvc_action[:type] == :new_inflight}
          >
            Cancel
          </.button>
        </.form>
        <.error :if={@pvc_action[:error]}><%= @pvc_action[:error] %></.error>
      </div>
    </div>
    """
  end

  defp save_config_form(assigns) do
    ~H"""
    <.form
      :let={f}
      for={@save_config.changeset}
      as={:secret}
      class="mt-4 flex flex-col"
      phx-change="validate_save_config"
      phx-submit="save_config"
      phx-target={@myself}
      autocomplete="off"
      spellcheck="false"
    >
      <div class="text-lg text-gray-800 font-semibold">
        Save config
      </div>
      <div class="mt-1 text-gray-700">
        Store the config in a secret in the <.workspace hub={@hub} /> workspace to reuse it later.
      </div>
      <div :if={error = @save_config.error} class="mt-4">
        <.message_box kind={:error} message={error} />
      </div>
      <div class="mt-4 grid grid-cols-3">
        <.text_field field={f[:name]} label="Secret name" class="uppercase" autofocus />
      </div>
      <div class="mt-6 flex gap-2">
        <.button type="submit" disabled={not @save_config.changeset.valid? or @save_config.inflight}>
          <%= if(@save_config.inflight, do: "Saving...", else: "Save") %>
        </.button>
        <.button
          color="gray"
          outlined
          type="button"
          phx-click="cancel_save_config"
          phx-target={@myself}
        >
          Cancel
        </.button>
      </div>
    </.form>
    """
  end

  defp workspace(assigns) do
    ~H"""
    <span class="font-medium">
      <span class="text-lg"><%= @hub.hub_emoji %></span>
      <span><%= @hub.hub_name %></span>
    </span>
    """
  end

  defp config_actions(assigns) do
    ~H"""
    <div class="mt-1 flex justify-end gap-1">
      <.button
        color="gray"
        outlined
        small
        type="button"
        phx-click="open_save_config"
        phx-target={@myself}
      >
        Save config
      </.button>
      <.menu id="config-secret-menu">
        <:toggle>
          <.button color="gray" outlined small type="button">
            <span>Load config</span>
            <.remix_icon icon="arrow-down-s-line" class="text-base leading-none" />
          </.button>
        </:toggle>
        <div
          :if={config_secret_names(@hub_secrets) == []}
          class="px-3 py-1 whitespace-nowrap text-gray-600 text-sm"
        >
          No configs saved yet
        </div>
        <.menu_item :for={name <- config_secret_names(@hub_secrets)}>
          <button
            class="text-gray-500 text-sm"
            type="button"
            role="menuitem"
            phx-click={JS.push("load_config", value: %{name: name}, target: @myself)}
          >
            <%= name %>
          </button>
        </.menu_item>
      </.menu>
    </div>
    """
  end

  defp loader(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <span class="text-sm font-gray-700">Loading</span>
      <.spinner />
    </div>
    """
  end

  defp cluster_check_error(%{error: %{status: 401}} = assigns) do
    ~H"""
    <.message_box kind={:error}>
      <div class="flex items-center justify-between">
        <div>Authentication with cluster failed.</div>
      </div>
    </.message_box>
    """
  end

  defp cluster_check_error(%{error: %{reason: :timeout}} = assigns) do
    ~H"""
    <.message_box kind={:error}>
      <div class="flex items-center justify-between">
        <div>Connection to cluster timed out.</div>
      </div>
    </.message_box>
    """
  end

  defp cluster_check_error(assigns) do
    ~H"""
    <.message_box kind={:error}>
      <div class="flex items-center justify-between">
        <div>Connection to cluster failed.</div>
      </div>
    </.message_box>
    """
  end

  defp rbac_error(%{error: %Req.Response{status: 201} = resp} = assigns) do
    resourceAttributes = resp.body["spec"]["resourceAttributes"]
    verb = resourceAttributes["verb"]
    namespace = resourceAttributes["namespace"]

    gkv =
      String.trim(
        "#{resourceAttributes["group"]}/#{resourceAttributes["version"]}/#{resourceAttributes["resource"]}",
        "/"
      )

    assigns = assign(assigns, verb: verb, gkv: gkv, namespace: namespace)

    ~H"""
    <div class="flex items-center justify-between">
      <div>
        Authenticated user has no permission to <span class="font-semibold"><%= @verb %></span>
        <code><%= @gkv %></code>
        <span :if={@namespace}> in namespace <code><%= @namespace %></code> (or the namespace doesn't exist)</span>.
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("set_context", %{"context" => context}, socket) do
    {:noreply, socket |> set_context(context) |> set_namespace(nil)}
  end

  def handle_event("set_namespace", %{"namespace" => namespace}, socket) do
    {:noreply, set_namespace(socket, namespace)}
  end

  def handle_event("set_docker_tag", %{"docker_tag" => docker_tag}, socket) do
    {:noreply, assign(socket, :docker_tag, docker_tag)}
  end

  def handle_event("set_pod_template", %{"pod_template" => pod_template}, socket) do
    {:noreply, set_pod_template(socket, pod_template)}
  end

  def handle_event("set_home_pvc", %{"home_pvc" => home_pvc}, socket) do
    {:noreply, assign(socket, :home_pvc, home_pvc)}
  end

  def handle_event("disconnect", %{}, socket) do
    Session.disconnect_runtime(socket.assigns.session.pid)
    {:noreply, socket}
  end

  def handle_event("new_pvc", %{}, socket) do
    pvc_action = %{
      type: :new,
      changeset: PVC.changeset(),
      storage_classes: storage_classes(socket.assigns),
      inflight: false,
      error: false
    }

    {:noreply, assign(socket, pvc_action: pvc_action)}
  end

  def handle_event("validate_pvc", %{"pvc" => pvc}, socket) do
    changeset =
      pvc
      |> PVC.changeset()
      |> Map.replace!(:action, :validate)

    {:noreply, assign_nested(socket, :pvc_action, changeset: changeset)}
  end

  def handle_event("cancel_new_pvc", %{}, socket) do
    {:noreply, assign(socket, pvc_action: nil)}
  end

  def handle_event("create_pvc", %{"pvc" => pvc}, socket) do
    pvc
    |> PVC.changeset()
    |> apply_action(:insert)
    |> case do
      {:ok, applied_pvc} ->
        {:noreply, create_pvc(socket, applied_pvc)}

      {:error, changeset} ->
        {:noreply, assign_nested(socket, :pvc_action, changeset: changeset)}
    end
  end

  def handle_event("delete_pvc", %{}, socket) do
    pvc_action = %{type: :delete, error: nil}
    {:noreply, assign(socket, pvc_action: pvc_action)}
  end

  def handle_event("confirm_delete_pvc", %{}, socket) do
    %{namespace: namespace, home_pvc: name} = socket.assigns
    req = socket.assigns.reqs.pvc

    socket =
      socket
      |> start_async(:delete_pvc, fn -> Kubereq.delete(req, namespace, name) end)
      |> assign_nested(:pvc_action, type: :delete_inflight)

    {:noreply, socket}
  end

  def handle_event("cancel_delete_pvc", %{}, socket) do
    {:noreply, assign(socket, pvc_action: nil)}
  end

  def handle_event("init", %{}, socket) do
    config = build_config(socket)
    runtime = Runtime.K8s.new(config, socket.assigns.reqs.pod)
    Session.set_runtime(socket.assigns.session.pid, runtime)
    Session.connect_runtime(socket.assigns.session.pid)
    {:noreply, socket}
  end

  def handle_event("open_save_config", %{}, socket) do
    changeset = config_secret_changeset(socket, %{name: @config_secret_prefix})
    save_config = %{changeset: changeset, inflight: false, error: false}
    {:noreply, assign(socket, save_config: save_config)}
  end

  def handle_event("cancel_save_config", %{}, socket) do
    {:noreply, assign(socket, save_config: nil)}
  end

  def handle_event("validate_save_config", %{"secret" => secret}, socket) do
    changeset =
      socket
      |> config_secret_changeset(secret)
      |> Map.replace!(:action, :validate)

    {:noreply, assign_nested(socket, :save_config, changeset: changeset)}
  end

  def handle_event("save_config", %{"secret" => secret}, socket) do
    changeset = config_secret_changeset(socket, secret)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, secret} ->
        {:noreply, save_config_secret(socket, secret, changeset)}

      {:error, changeset} ->
        {:noreply, assign_nested(socket, :save_config, changeset: changeset)}
    end
  end

  def handle_event("load_config", %{"name" => name}, socket) do
    secret = Enum.find(socket.assigns.hub_secrets, &(&1.name == name))

    case Jason.decode(secret.value) do
      {:ok, config_defaults} ->
        {:noreply,
         socket
         |> assign(config_defaults: config_defaults)
         |> load_config_defaults()}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_async(:rbac_check, {:ok, %{errors: errors, permissions: permissions}}, socket) do
    status = if errors === [], do: :ok, else: :errors
    {:noreply, assign(socket, :rbac, %{status: status, errors: errors, permissions: permissions})}
  end

  def handle_async(:load_namespace_options, {:ok, [:ok, {:ok, resp}]}, socket) do
    socket =
      case resp do
        %Req.Response{status: 200, body: %{"items" => resources}} ->
          namespace_options = Enum.map(resources, & &1["metadata"]["name"])

          socket
          |> assign(:namespace_options, namespace_options)
          |> set_namespace(List.first(namespace_options))
          |> assign(:cluster_check, %{status: :ok, error: nil})

        %Req.Response{status: _other} ->
          # cannot list namespaces
          socket
          |> assign(:namespace_options, nil)
          |> assign(:cluster_check, %{status: :ok, error: nil})
      end

    {:noreply, socket}
  end

  def handle_async(:delete_pvc, {:ok, result}, socket) do
    socket =
      case result do
        {:ok, %{status: 200}} ->
          socket
          |> assign(home_pvc: nil, pvc_action: nil)
          |> pvc_options()

        {:ok, %{body: %{"message" => message}}} ->
          assign_nested(socket, :pvc_action, error: message, type: :delete)
      end

    {:noreply, socket}
  end

  def handle_async(:create_pvc, {:ok, result}, socket) do
    socket =
      case result do
        {:ok, %{status: 201, body: created_pvc}} ->
          socket
          |> assign(home_pvc: created_pvc["metadata"]["name"], pvc_action: nil)
          |> pvc_options()

        {:ok, %{body: body}} ->
          socket
          |> assign_nested(:pvc_action,
            error: "Creating the PVC failed: #{body["message"]}",
            type: :new
          )

        {:error, error} when is_exception(error) ->
          socket
          |> assign_nested(:pvc_action,
            error: "Creating the PVC failed: #{Exception.message(error)}",
            type: :new
          )
      end

    {:noreply, socket}
  end

  def handle_async(:load_namespace_options, {:ok, results}, socket) do
    {:error, error} = List.first(results, &match?({:error, _}, &1))

    socket =
      socket
      |> assign(:namespace_options, nil)
      |> assign(:cluster_check, %{status: :error, error: error})

    {:noreply, socket}
  end

  def handle_async(:save_config, {:ok, result}, socket) do
    socket =
      case result do
        :ok ->
          assign(socket, save_config: nil)

        {:error, %Ecto.Changeset{} = changeset} ->
          assign_nested(socket, :save_config, changeset: changeset, inflight: false)

        {:transport_error, error} ->
          assign_nested(socket, :save_config, error: error, inflight: false)
      end

    {:noreply, socket}
  end

  defp label(namespace, runtime, runtime_status) do
    reconnecting? = reconnecting?(namespace, runtime)

    case {reconnecting?, runtime_status} do
      {true, :connected} -> "Reconnect"
      {true, :connecting} -> "Connecting..."
      _ -> "Connect"
    end
  end

  defp reconnecting?(namespace, runtime) do
    match?(%Runtime.K8s{config: %{namespace: ^namespace}}, runtime)
  end

  defp create_pvc(socket, pvc) do
    namespace = socket.assigns.namespace
    manifest = PVC.manifest(pvc, namespace)
    req = socket.assigns.reqs.pvc

    socket
    |> start_async(:create_pvc, fn -> Kubereq.create(req, manifest) end)
    |> assign_nested(:pvc_action, type: :new_inflight)
  end

  defp set_context(socket, nil), do: assign(socket, :context, nil)

  defp set_context(socket, context) do
    kubeconfig = Kubereq.Kubeconfig.set_current_context(socket.assigns.kubeconfig, context)

    reqs = %{
      access_reviews:
        Kubereq.new(kubeconfig, "apis/authorization.k8s.io/v1/selfsubjectaccessreviews"),
      namespaces: Kubereq.new(kubeconfig, "api/v1/namespaces/:name"),
      pod: Kubereq.new(kubeconfig, "api/v1/namespaces/:namespace/pods/:name"),
      pvc: Kubereq.new(kubeconfig, "api/v1/namespaces/:namespace/persistentvolumeclaims/:name"),
      sc: Kubereq.new(kubeconfig, "apis/storage.k8s.io/v1/storageclasses/:name")
    }

    socket
    |> start_async(:load_namespace_options, fn ->
      [
        Task.async(fn ->
          Livebook.K8s.Auth.can_i?(reqs.access_reviews,
            verb: "create",
            group: "authorization.k8s.io",
            version: "v1",
            resource: "selfsubjectaccessreviews"
          )
        end),
        Task.async(fn -> Kubereq.list(reqs.namespaces, nil) end)
      ]
      |> Task.await_many(:infinity)
    end)
    |> assign(
      kubeconfig: kubeconfig,
      context: context,
      namespace: nil,
      namespace_options: nil,
      rbac_error: nil,
      reqs: reqs,
      cluster_check: %{status: :inflight, error: nil}
    )
  end

  defp set_namespace(socket, nil) do
    assign(socket, namespace: nil, rbac: %{status: :inflight, errors: [], permissions: []})
  end

  defp set_namespace(socket, ns) do
    reqs = socket.assigns.reqs

    socket
    |> start_async(:rbac_check, fn ->
      {required_permissions, optional_permissions} =
        Auth.batch_check(reqs.access_reviews, [
          # required permissions:
          [verb: "get", version: "v1", resource: "pods", namespace: ns],
          [verb: "list", version: "v1", resource: "pods", namespace: ns],
          [verb: "watch", version: "v1", resource: "pods", namespace: ns],
          [verb: "create", version: "v1", resource: "pods", namespace: ns],
          [verb: "delete", version: "v1", resource: "pods", namespace: ns],
          [verb: "create", version: "v1", resource: "pods/portforward", namespace: ns],
          # optional permissions:
          [verb: "list", version: "v1", resource: "persistentvolumeclaims", namespace: ns],
          [verb: "create", version: "v1", resource: "persistentvolumeclaims", namespace: ns],
          [verb: "delete", version: "v1", resource: "persistentvolumeclaims", namespace: ns],
          [verb: "list", version: "v1", resource: "storageclasses", namespace: ns]
        ])
        |> Enum.split(6)

      errors =
        required_permissions
        |> Enum.reject(&(&1 === :ok))
        |> Enum.map(fn {:error, error} -> error end)

      permissions =
        optional_permissions
        |> Enum.map(&(&1 === :ok))
        |> then(&Enum.zip([:list_pvc, :create_pvc, :delete_pvc, :list_sc], &1))
        |> Map.new()

      %{errors: errors, permissions: permissions}
    end)
    |> assign(
      namespace: ns,
      rbac: %{status: :inflight, errors: :inflight, permissions: :inflight}
    )
    |> pvc_options()
  end

  def set_pod_template(socket, pod_template_yaml) do
    namespace = socket.assigns.namespace

    with {:parse, {:ok, pod_template}} <-
           {:parse, YamlElixir.read_from_string(pod_template_yaml)},
         {:validate, :ok} <- {:validate, Pod.validate_pod_template(pod_template, namespace)} do
      assign(socket, :pod_template, %{template: pod_template_yaml, status: :valid, message: nil})
    else
      {:parse, {:error, error}} ->
        assign(socket, :pod_template, %{
          template: pod_template_yaml,
          status: :error,
          message: Exception.message(error)
        })

      {:validate, {:error, message}} ->
        assign(socket, :pod_template, %{
          template: pod_template_yaml,
          status: :error,
          message: message
        })
    end
  end

  defp pvc_options(%{assigns: %{rbac: %{permissions: %{list_pvc: false}}}} = socket) do
    assign(socket, :pvcs, [])
  end

  defp pvc_options(socket) do
    %{reqs: %{pvc: req}, namespace: ns} = socket.assigns

    case Kubereq.list(req, ns) do
      {:ok, %Req.Response{status: 200} = resp} ->
        pvcs =
          resp.body["items"]
          |> Enum.reject(& &1["metadata"]["deletionTimestamp"])
          |> Enum.map(& &1["metadata"]["name"])

        socket
        |> assign(:pvcs, pvcs)

      _ ->
        assign(socket, :pvcs, [])
    end
  end

  defp storage_classes(%{rbac: %{permissions: %{list_sc: false}}}), do: []

  defp storage_classes(assigns) do
    %{reqs: %{sc: req}} = assigns

    case Kubereq.list(req, nil) do
      {:ok, %Req.Response{status: 200} = resp} ->
        Enum.map(resp.body["items"], & &1["metadata"]["name"])

      _ ->
        []
    end
  end

  defp config_secret_names(hub_secrets) do
    names =
      for %{name: name} <- hub_secrets,
          String.starts_with?(name, @config_secret_prefix),
          do: name

    Enum.sort(names)
  end

  defp load_config_defaults(socket) do
    config_defaults = socket.assigns.config_defaults

    socket
    |> assign(
      home_pvc: config_defaults["home_pvc"],
      docker_tag: config_defaults["docker_tag"]
    )
    |> set_context(config_defaults["context"])
    |> set_namespace(config_defaults["namespace"])
    |> set_pod_template(config_defaults["pod_template"])
  end

  defp config_secret_changeset(socket, attrs) do
    hub = socket.assigns.hub
    value = socket |> build_config() |> Jason.encode!()
    secret = %Livebook.Secrets.Secret{hub_id: hub.id, name: nil, value: value}

    secret
    |> Livebook.Secrets.change_secret(attrs)
    |> validate_format(:name, ~r/^#{@config_secret_prefix}\w+$/,
      message: "must be in the format #{@config_secret_prefix}*"
    )
  end

  defp save_config_secret(socket, secret, changeset) do
    hub = socket.assigns.hub
    exists? = Enum.any?(socket.assigns.hub_secrets, &(&1.name == secret.name))

    socket
    |> start_async(:save_config, fn ->
      result =
        if exists? do
          Livebook.Hubs.update_secret(hub, secret)
        else
          Livebook.Hubs.create_secret(hub, secret)
        end

      with {:error, errors} <- result do
        {:error,
         changeset
         |> Livebook.Utils.put_changeset_errors(errors)
         |> Map.replace!(:action, :validate)}
      end
    end)
    |> assign_nested(:save_config, inflight: true)
  end

  defp assign_nested(socket, key, keyword) do
    update(socket, key, fn map ->
      Enum.reduce(keyword, map, fn {key, value}, map -> Map.replace!(map, key, value) end)
    end)
  end

  defp build_config(socket) do
    %{
      context: socket.assigns.context,
      namespace: socket.assigns.namespace,
      home_pvc: socket.assigns.home_pvc,
      docker_tag: socket.assigns.docker_tag,
      pod_template: socket.assigns.pod_template.template
    }
  end
end
