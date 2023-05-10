defmodule LivebookWeb.SessionLive.InsertButtonsComponent do
  use LivebookWeb, :live_component

  defguardp is_many(list) when tl(list) != []

  def render(assigns) do
    ~H"""
    <div
      class="relative top-0.5 m-0 flex justify-center"
      role="toolbar"
      aria-label="insert new"
      data-el-insert-buttons
    >
      <div class={
        "w-full absolute z-10 hover:z-[11] #{if(@persistent, do: "opacity-100", else: "opacity-0")} hover:opacity-100 focus-within:opacity-100 flex space-x-2 justify-center items-center"
      }>
        <button
          class="button-base button-small"
          phx-click="insert_cell_below"
          phx-value-type="code"
          phx-value-section_id={@section_id}
          phx-value-cell_id={@cell_id}
        >
          + Code
        </button>
        <.menu id={"#{@id}-block-menu"} position={:bottom_left}>
          <:toggle>
            <button class="button-base button-small">+ Block</button>
          </:toggle>
          <.menu_item>
            <button
              role="menuitem"
              phx-click="insert_cell_below"
              phx-value-type="markdown"
              phx-value-section_id={@section_id}
              phx-value-cell_id={@cell_id}
            >
              <.remix_icon icon="markdown-fill" />
              <span>Markdown</span>
            </button>
          </.menu_item>
          <.menu_item>
            <button
              role="menuitem"
              phx-click="insert_section_below"
              phx-value-section_id={@section_id}
              phx-value-cell_id={@cell_id}
            >
              <.remix_icon icon="h-2" />
              <span>Section</span>
            </button>
          </.menu_item>
          <div class="my-2 border-b border-gray-200"></div>
          <.menu_item>
            <button
              role="menuitem"
              phx-click="insert_cell_below"
              phx-value-type="diagram"
              phx-value-section_id={@section_id}
              phx-value-cell_id={@cell_id}
            >
              <.remix_icon icon="organization-chart" />
              <span>Diagram</span>
            </button>
          </.menu_item>
          <.menu_item>
            <.link
              patch={
                ~p"/sessions/#{@session_id}/cell-upload?section_id=#{@section_id}&cell_id=#{@cell_id || ""}"
              }
              aria-label="insert image"
              role="menuitem"
            >
              <.remix_icon icon="image-add-line" />
              <span>Image</span>
            </.link>
          </.menu_item>
          <%= if @code_block_definitions != [] do %>
            <div class="my-2 border-b border-gray-200"></div>
            <.menu_item :for={definition <- Enum.sort_by(@code_block_definitions, & &1.name)}>
              <.code_block_insert_button
                definition={definition}
                runtime={@runtime}
                section_id={@section_id}
                cell_id={@cell_id}
              />
            </.menu_item>
          <% end %>
        </.menu>
        <%= cond do %>
          <% not Livebook.Runtime.connected?(@runtime) -> %>
            <button
              class="button-base button-small"
              phx-click={
                JS.push("setup_default_runtime",
                  value: %{reason: "To see the available smart cells, you need a connected runtime."}
                )
              }
            >
              + Smart
            </button>
          <% @smart_cell_definitions == [] -> %>
            <span class="tooltip right" data-tooltip="No smart cells available">
              <button class="button-base button-small" disabled>+ Smart</button>
            </span>
          <% true -> %>
            <.menu id={"#{@id}-smart-menu"} position={:bottom_left}>
              <:toggle>
                <button class="button-base button-small">+ Smart</button>
              </:toggle>
              <.menu_item :for={definition <- Enum.sort_by(@smart_cell_definitions, & &1.name)}>
                <.smart_cell_insert_button
                  definition={definition}
                  section_id={@section_id}
                  cell_id={@cell_id}
                />
              </.menu_item>
            </.menu>
        <% end %>
      </div>
    </div>
    """
  end

  defp code_block_insert_button(assigns) when is_many(assigns.definition.variants) do
    ~H"""
    <.submenu>
      <:primary>
        <button role="menuitem">
          <.remix_icon icon={@definition.icon} />
          <span><%= @definition.name %></span>
        </button>
      </:primary>
      <.menu_item :for={{variant, idx} <- Enum.with_index(@definition.variants)}>
        <button
          role="menuitem"
          phx-click={on_code_block_click(@definition, idx, @runtime, @section_id, @cell_id)}
        >
          <span><%= variant.name %></span>
        </button>
      </.menu_item>
    </.submenu>
    """
  end

  defp code_block_insert_button(assigns) do
    ~H"""
    <button
      role="menuitem"
      phx-click={on_code_block_click(@definition, 0, @runtime, @section_id, @cell_id)}
    >
      <.remix_icon icon={@definition.icon} />
      <span><%= @definition.name %></span>
    </button>
    """
  end

  defp smart_cell_insert_button(assigns) when is_many(assigns.definition.requirement_presets) do
    ~H"""
    <.submenu>
      <:primary>
        <button role="menuitem">
          <span><%= @definition.name %></span>
        </button>
      </:primary>
      <.menu_item :for={{preset, idx} <- Enum.with_index(@definition.requirement_presets)}>
        <button
          role="menuitem"
          phx-click={on_smart_cell_click(@definition, idx, @section_id, @cell_id)}
        >
          <span><%= preset.name %></span>
        </button>
      </.menu_item>
    </.submenu>
    """
  end

  defp smart_cell_insert_button(assigns) do
    ~H"""
    <button role="menuitem" phx-click={on_smart_cell_click(@definition, @section_id, @cell_id)}>
      <span><%= @definition.name %></span>
    </button>
    """
  end

  defp on_code_block_click(definition, variant_idx, runtime, section_id, cell_id) do
    if Livebook.Runtime.connected?(runtime) do
      JS.push("insert_code_block_below",
        value: %{
          definition_name: definition.name,
          variant_idx: variant_idx,
          section_id: section_id,
          cell_id: cell_id
        }
      )
    else
      JS.push("setup_default_runtime",
        value: %{reason: "To insert this block, you need a connected runtime."}
      )
    end
  end

  defp on_smart_cell_click(definition, section_id, cell_id) do
    preset_idx = if definition.requirement_presets == [], do: nil, else: 0
    on_smart_cell_click(definition, preset_idx, section_id, cell_id)
  end

  defp on_smart_cell_click(definition, preset_idx, section_id, cell_id) do
    JS.push("insert_smart_cell_below",
      value: %{
        kind: definition.kind,
        section_id: section_id,
        cell_id: cell_id,
        preset_idx: preset_idx
      }
    )
  end
end
