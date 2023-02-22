defmodule LivebookWeb.EnvVarsComponent do
  use LivebookWeb, :live_component

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:target, fn -> nil end)
      |> assign_new(:edit_label, fn -> "Edit" end)

    ~H"""
    <div id={@id} class="flex flex-col space-y-4">
      <div class="flex flex-col space-y-4">
        <div
          :for={env_var <- @env_vars}
          class="flex items-center justify-between border border-gray-200 rounded-lg p-4"
        >
          <.env_var_info env_var={env_var} edit_label={@edit_label} target={@target} />
        </div>
      </div>
      <div class="flex">
        <.link patch={@add_env_var_path} class="button-base button-blue" id="add-env-var">
          Add environment variable
        </.link>
      </div>
    </div>
    """
  end

  defp env_var_info(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 w-full">
      <div class="place-content-start">
        <.labeled_text label="Name">
          <%= @env_var.name %>
        </.labeled_text>
      </div>

      <div class="flex items-center place-content-end">
        <.menu id={"env-var-#{@env_var.name}-menu"}>
          <:toggle>
            <button class="icon-button" aria-label="open session menu" type="button">
              <.remix_icon icon="more-2-fill" class="text-xl" />
            </button>
          </:toggle>
          <:content>
            <button
              id={"env-var-#{@env_var.name}-edit"}
              type="button"
              phx-click={JS.push("edit_env_var", value: %{env_var: @env_var.name})}
              phx-target={@target}
              role="menuitem"
              class="menu-item text-gray-600"
            >
              <.remix_icon icon="file-edit-line" />
              <span class="font-medium"><%= @edit_label %></span>
            </button>
            <button
              id={"env-var-#{@env_var.name}-delete"}
              type="button"
              phx-click={
                with_confirm(
                  JS.push("delete_env_var", value: %{env_var: @env_var.name}),
                  title: "Delete #{@env_var.name}",
                  description: "Are you sure you want to delete environment variable?",
                  confirm_text: "Delete",
                  confirm_icon: "delete-bin-6-line"
                )
              }
              phx-target={@target}
              role="menuitem"
              class="menu-item text-red-600"
            >
              <.remix_icon icon="delete-bin-line" />
              <span class="font-medium">Delete</span>
            </button>
          </:content>
        </.menu>
      </div>
    </div>
    """
  end
end
