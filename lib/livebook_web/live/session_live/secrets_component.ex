defmodule LivebookWeb.SessionLive.SecretsComponent do
  use LivebookWeb, :live_component

  alias Livebook.Secrets.Secret

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if socket.assigns[:data] do
        socket
      else
        assign(socket,
          data: %{"name" => prefill_secret_name(socket), "value" => "", "store" => "session"},
          title: title(socket),
          grant_access: must_grant_access(socket)
        )
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-4xl flex flex-col space-y-5">
      <h3 class="text-2xl font-semibold text-gray-800">
        <%= @title %>
      </h3>
      <%= if @grant_access do %>
        <.grant_access_message grant_access={@grant_access} target={@myself} />
      <% end %>
      <div class="flex flex-columns gap-4">
        <%= if @select_secret_ref do %>
          <div class="basis-1/2 grow-0 pr-4 border-r">
            <div class="flex flex-col space-y-4">
              <p class="text-gray-800">
                Choose a secret
              </p>
              <div class="flex flex-wrap">
                <%= for secret <- @secrets do %>
                  <.secret_with_badge
                    secret_name={secret.name}
                    stored="Session"
                    action="select_secret"
                    active={secret.name == @preselect_name}
                    target={@myself}
                  />
                <% end %>
                <%= for secret <- livebook_only_secrets(@secrets, @livebook_secrets) do %>
                  <.secret_with_badge
                    secret_name={secret.name}
                    stored="livebook"
                    action="select_livebook_secret"
                    active={secret.name == @preselect_name}
                    target={@myself}
                  />
                <% end %>
                <%= if @secrets == [] && @livebook_secrets == [] do %>
                  <div class="w-full text-center text-gray-400 border rounded-lg p-8">
                    <.remix_icon icon="folder-lock-line" class="align-middle text-2xl" />
                    <span class="mt-1 block text-sm text-gray-700">
                      Secrets not found. <br /> Add to see them here.
                    </span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
        <.form
          let={f}
          for={:data}
          phx-submit="save"
          phx-change="validate"
          autocomplete="off"
          phx-target={@myself}
          errors={data_errors(@data)}
          class="basis-1/2 grow"
        >
          <div class="flex flex-col space-y-4">
            <%= if @select_secret_ref do %>
              <p class="text-gray-700">
                Add new secret
              </p>
            <% end %>
            <.input_wrapper form={f} field={:name}>
              <div class="input-label">
                Name <span class="text-xs text-gray-500">(alphanumeric and underscore)</span>
              </div>
              <%= text_input(f, :name,
                value: @data["name"],
                class: "input",
                autofocus: !@prefill_secret_name,
                spellcheck: "false"
              ) %>
            </.input_wrapper>
            <.input_wrapper form={f} field={:value}>
              <div class="input-label">Value</div>
              <%= text_input(f, :value,
                value: @data["value"],
                class: "input",
                autofocus:
                  !!@prefill_secret_name ||
                    unavailable_secret?(@preselect_name, @secrets, @livebook_secrets),
                spellcheck: "false"
              ) %>
            </.input_wrapper>
            <div>
              <span class="text-base font-medium text-gray-900">Store</span>
              <div class="mt-2 space-y-1">
                <%= label  class: "flex items-center gap-2 text-gray-600" do %>
                  <%= radio_button(f, :store, "session", checked: @data["store"] == "session") %> Session
                <% end %>
                <%= label class: "flex items-center gap-2 text-gray-600" do %>
                  <%= radio_button(f, :store, "livebook", checked: @data["store"] == "livebook") %> Notebook
                <% end %>
              </div>
            </div>
            <div class="flex space-x-2">
              <button class="button-base button-blue" type="submit" disabled={f.errors != []}>
                <.remix_icon icon="add-line" class="align-middle" />
                <span class="font-normal">Add</span>
              </button>
              <%= live_patch("Cancel", to: @return_to, class: "button-base button-outlined-gray") %>
            </div>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp secret_with_badge(assigns) do
    ~H"""
    <div
      role="button"
      class={
        if @active,
          do:
            "flex justify-between w-full bg-blue-100 text-sm text-blue-700 p-2 border-b cursor-pointer",
          else:
            "flex justify-between w-full text-sm text-gray-700 p-2 border-b cursor-pointer hover:bg-gray-100"
      }
      phx-value-secret_name={@secret_name}
      phx-target={@target}
      phx-click={@action}
    >
      <%= @secret_name %>
      <span class={
        if @active,
          do:
            "inline-flex items-center rounded-full bg-indigo-100 px-2.5 py-0.5 text-xs font-medium text-blue-800",
          else:
            "inline-flex items-center rounded-full bg-gray-100 px-2.5 py-0.5 text-xs font-medium text-gray-800"
      }>
        <%= if @active do %>
          <svg class="-ml-0.5 mr-1.5 h-2 w-2 text-blue-400" fill="currentColor" viewBox="0 0 8 8">
            <circle cx="4" cy="4" r="3" />
          </svg>
        <% end %>
        <%= @stored %>
      </span>
    </div>
    """
  end

  defp grant_access_message(assigns) do
    ~H"""
    <div>
      <div class="mx-auto">
        <div class="rounded-lg bg-blue-600 p-2 shadow-sm">
          <div class="flex flex-wrap items-center justify-between">
            <div class="flex w-0 flex-1 items-center">
              <.remix_icon
                icon="error-warning-fill"
                class="align-middle text-2xl flex text-gray-100 rounded-lg py-2"
              />
              <span class="ml-2 text-sm font-normal text-gray-100">
                The secret <span class="font-semibold text-white"><%= @grant_access %></span>
                needs to be made available to the session
              </span>
            </div>
            <button
              class="button-base button-gray"
              phx-click="grant_access"
              phx-value-secret_name={@grant_access}
              phx-target={@target}
            >
              Grant access
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("save", %{"data" => data}, socket) do
    if data_errors(data) == [] do
      secret_name = String.upcase(data["name"])
      secret = %{name: secret_name, value: data["value"]}
      store = data["store"]

      put_secret(socket.assigns.session.pid, secret, store)

      if socket.assigns.select_secret_ref && store == "livebook",
        do: put_secret(socket.assigns.session.pid, secret, "session")

      {:noreply,
       socket
       |> maybe_sync_secrets(secret, store)
       |> push_patch(to: socket.assigns.return_to)
       |> push_secret_selected(secret_name)}
    else
      {:noreply, assign(socket, data: data)}
    end
  end

  def handle_event("select_secret", %{"secret_name" => secret_name}, socket) do
    {:noreply,
     socket |> push_patch(to: socket.assigns.return_to) |> push_secret_selected(secret_name)}
  end

  def handle_event("select_livebook_secret", %{"secret_name" => secret_name}, socket) do
    grant_access(secret_name, socket)

    {:noreply,
     socket |> push_patch(to: socket.assigns.return_to) |> push_secret_selected(secret_name)}
  end

  def handle_event("validate", %{"data" => data}, socket) do
    {:noreply, assign(socket, data: data)}
  end

  def handle_event("grant_access", %{"secret_name" => secret_name}, socket) do
    grant_access(secret_name, socket)

    {:noreply,
     socket |> push_patch(to: socket.assigns.return_to) |> push_secret_selected(secret_name)}
  end

  defp data_errors(data) do
    Enum.flat_map(data, fn {key, value} ->
      if error = data_error(key, value) do
        [{String.to_existing_atom(key), {error, []}}]
      else
        []
      end
    end)
  end

  defp data_error("name", value) do
    cond do
      String.match?(value, ~r/^\w+$/) -> nil
      value == "" -> "can't be blank"
      true -> "is invalid"
    end
  end

  defp data_error("value", ""), do: "can't be blank"
  defp data_error(_key, _value), do: nil

  defp push_secret_selected(%{assigns: %{select_secret_ref: nil}} = socket, _), do: socket

  defp push_secret_selected(%{assigns: %{select_secret_ref: ref}} = socket, secret_name) do
    push_event(socket, "secret_selected", %{select_secret_ref: ref, secret_name: secret_name})
  end

  defp prefill_secret_name(socket) do
    case socket.assigns.prefill_secret_name do
      nil ->
        if unavailable_secret?(
             socket.assigns.preselect_name,
             socket.assigns.secrets,
             socket.assigns.livebook_secrets
           ),
           do: socket.assigns.preselect_name,
           else: ""

      prefill ->
        prefill
    end
  end

  defp unavailable_secret?(nil, _, _), do: false
  defp unavailable_secret?("", _, _), do: false

  defp unavailable_secret?(preselect_name, secrets, livebook_secrets) do
    preselect_name not in Enum.map(secrets, & &1.name) &&
      preselect_name not in Enum.map(livebook_secrets, & &1.name)
  end

  defp title(%{assigns: %{select_secret_ref: nil}}), do: "Add secret"
  defp title(%{assigns: %{select_secret_options: %{"title" => title}}}), do: title
  defp title(_), do: "Select secret"

  defp put_secret(pid, secret, "session"), do: Livebook.Session.put_secret(pid, secret)
  defp put_secret(_pid, secret, "livebook"), do: Livebook.Secrets.set_secret(secret)

  defp grant_access(secret_name, socket) do
    secret_value =
      Enum.find_value(
        socket.assigns.livebook_secrets,
        &if(&1.name == secret_name, do: &1.value)
      )

    secret = %{name: secret_name, value: secret_value}
    put_secret(socket.assigns.session.pid, secret, "session")
  end

  defp livebook_only_secrets(secrets, livebook_secrets) do
    Enum.reject(livebook_secrets, &(&1.name in get_in(secrets, [Access.all(), :name])))
  end

  defp maybe_sync_secrets(socket, secret, "livebook") do
    old_secret =
      Enum.find(socket.assigns.livebook_secrets, %Secret{}, &(&1.name == secret.name))
      |> Map.from_struct()

    if old_secret in socket.assigns.secrets,
      do: put_secret(socket.assigns.session.pid, secret, "session")

    socket
  end

  defp maybe_sync_secrets(socket, secret, "session") do
    old_secret = Enum.find(socket.assigns.secrets, &(&1.name == secret.name))
    livebook_secrets = Enum.map(socket.assigns.livebook_secrets, &Map.from_struct/1)

    if old_secret in livebook_secrets,
      do: put_secret(socket.assigns.session.pid, secret, "livebook")

    socket
  end

  defp must_grant_access(%{assigns: %{select_secret_ref: nil}}), do: nil

  defp must_grant_access(%{assigns: %{preselect_name: preselect_name}} = socket) do
    secrets = livebook_only_secrets(socket.assigns.secrets, socket.assigns.livebook_secrets)
    if preselect_name in get_in(secrets, [Access.all(), Access.key!(:name)]), do: preselect_name
  end
end
