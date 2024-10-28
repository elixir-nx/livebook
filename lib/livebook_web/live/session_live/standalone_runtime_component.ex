defmodule LivebookWeb.SessionLive.StandaloneRuntimeComponent do
  use LivebookWeb, :live_component

  import Ecto.Changeset

  alias Livebook.{Session, Runtime}

  @impl true
  def mount(socket) do
    unless Livebook.Config.runtime_enabled?(Livebook.Runtime.Standalone) do
      raise "runtime module not allowed"
    end

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    changeset =
      case socket.assigns[:changeset] do
        nil ->
          changeset(assigns.runtime)

        changeset when socket.assigns.runtime == assigns.runtime ->
          changeset

        changeset ->
          changeset(assigns.runtime, changeset.params)
      end

    socket =
      socket
      |> assign(assigns)
      |> assign(:changeset, changeset)

    {:ok, socket}
  end

  defp changeset(runtime, attrs \\ %{}) do
    data =
      case runtime do
        %Runtime.Standalone{erl_flags: erl_flags} ->
          %{erl_flags: erl_flags}

        _ ->
          %{erl_flags: nil}
      end

    types = %{erl_flags: :string}

    cast({data, types}, attrs, [:erl_flags])
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-col space-y-5">
      <p class="text-gray-700">
        Start a new local Elixir node to evaluate code. Whenever you reconnect this runtime,
        a fresh node is started.
      </p>
      <.form
        :let={f}
        for={@changeset}
        as={:data}
        phx-submit="init"
        phx-change="validate"
        phx-target={@myself}
        autocomplete="off"
        spellcheck="false"
      >
        <div class="flex flex-col space-y-4 mb-5">
          <.text_field field={f[:erl_flags]} label="Erl flags" />
        </div>
        <.button type="submit" disabled={@runtime_status == :connecting or not @changeset.valid?}>
          <%= label(@changeset, @runtime_status) %>
        </.button>
      </.form>
    </div>
    """
  end

  defp label(changeset, runtime_status) do
    reconnecting? = changeset.valid? and changeset.data == apply_changes(changeset)

    case {reconnecting?, runtime_status} do
      {true, :connected} -> "Reconnect"
      {true, :connecting} -> "Connecting..."
      _ -> "Connect"
    end
  end

  @impl true
  def handle_event("validate", %{"data" => data}, socket) do
    changeset =
      socket.assigns.runtime
      |> changeset(data)
      |> Map.replace!(:action, :validate)

    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event("init", %{"data" => data}, socket) do
    socket.assigns.runtime
    |> changeset(data)
    |> apply_action(:insert)
    |> case do
      {:ok, data} ->
        runtime = Runtime.Standalone.new(erl_flags: data.erl_flags)
        Session.set_runtime(socket.assigns.session.pid, runtime)
        Session.connect_runtime(socket.assigns.session.pid)
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
