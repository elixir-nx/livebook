defmodule LivebookWeb.FormComponents do
  use Phoenix.Component

  import LivebookWeb.CoreComponents

  alias Phoenix.LiveView.JS

  @doc """
  Renders a text input with label and error messages.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :errors, :list, default: []
  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form"

  attr :rest, :global, include: ~w(autocomplete readonly disabled)

  def text_field(assigns) do
    assigns = assigns_from_field(assigns)

    ~H"""
    <.field_wrapper id={@id} name={@name} label={@label} errors={@errors}>
      <input
        type="text"
        name={@name}
        id={@id || @name}
        value={Phoenix.HTML.Form.normalize_value("text", @value)}
        class="input"
        {@rest}
      />
    </.field_wrapper>
    """
  end

  @doc """
  Renders a textarea input with label and error messages.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :errors, :list, default: []
  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form"

  attr :resizable, :boolean, default: false

  attr :rest, :global, include: ~w(autocomplete readonly disabled rows cols)

  def textarea_field(assigns) do
    assigns = assigns_from_field(assigns)

    ~H"""
    <.field_wrapper id={@id} name={@name} label={@label} errors={@errors}>
      <textarea
        id={@id || @name}
        name={@name}
        class={["input", not @resizable && "resize-none"]}
        {@rest}
      ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
    </.field_wrapper>
    """
  end

  @doc """
  Renders a hidden input.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :value, :any
  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form"

  attr :rest, :global, include: ~w(autocomplete readonly disabled)

  def hidden_field(assigns) do
    assigns = assigns_from_field(assigns)

    ~H"""
    <input type="hidden" name={@name} id={@id || @name} value={@value} {@rest} />
    """
  end

  @doc """
  Renders a password input with label and error messages.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :errors, :list, default: []
  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form"

  attr :rest, :global, include: ~w(autocomplete readonly disabled)

  def password_field(assigns) do
    assigns = assigns_from_field(assigns)

    ~H"""
    <.field_wrapper id={@id} name={@name} label={@label} errors={@errors}>
      <.with_password_toggle id={@id <> "-toggle"}>
        <input
          type="password"
          name={@name}
          id={@id || @name}
          value={Phoenix.HTML.Form.normalize_value("text", @value)}
          class="input"
          {@rest}
        />
      </.with_password_toggle>
    </.field_wrapper>
    """
  end

  @doc """
  Renders a hex color input with label and error messages.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :errors, :list, default: []
  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form"

  attr :randomize, JS, default: %JS{}
  attr :rest, :global

  def hex_color_field(assigns) do
    assigns = assigns_from_field(assigns)

    ~H"""
    <.field_wrapper id={@id} name={@name} label={@label} errors={@errors}>
      <div class="flex space-x-4 items-center">
        <div
          class="border-[3px] rounded-lg p-1 flex justify-center items-center"
          style={"border-color: #{@value}"}
        >
          <div class="rounded h-5 w-5" style={"background-color: #{@value}"}></div>
        </div>
        <div class="relative grow">
          <input
            type="text"
            name={@name}
            id={@id || @name}
            value={@value}
            class="input"
            spellcheck="false"
            maxlength="7"
            {@rest}
          />
          <button class="icon-button absolute right-2 top-1" type="button" phx-click={@randomize}>
            <.remix_icon icon="refresh-line" class="text-xl" />
          </button>
        </div>
      </div>
    </.field_wrapper>
    """
  end

  @doc """
  Renders a switch input with label and error messages.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :errors, :list, default: []
  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form"

  attr :disabled, :boolean, default: false
  attr :checked_value, :string, default: "true"
  attr :unchecked_value, :string, default: "false"
  attr :tooltip, :string, default: nil

  attr :rest, :global

  def switch_field(assigns) do
    assigns = assigns_from_field(assigns)

    ~H"""
    <div phx-feedback-for={@name} class={[@errors != [] && "show-errors"]}>
      <div class="flex items-center gap-1 sm:gap-3 justify-between">
        <span
          :if={@label}
          class={["text-gray-700", @tooltip && "tooltip top"]}
          data-tooltip={@tooltip}
        >
          <%= @label %>
        </span>
        <label class={[
          "relative inline-block w-14 h-7 select-none",
          @disabled && "pointer-events-none opacity-50"
        ]}>
          <input type="hidden" value={@unchecked_value} name={@name} />
          <input
            type="checkbox"
            value={@checked_value}
            class={[
              "appearance-none absolute block w-7 h-7 rounded-full bg-white border-[5px] border-gray-200 cursor-pointer transition-all duration-300",
              "peer checked:bg-white checked:border-blue-600 checked:translate-x-full"
            ]}
            name={@name}
            id={@id || @name}
            checked={to_string(@value) == @checked_value}
            {@rest}
          />
          <div class={[
            "block h-full w-full rounded-full bg-gray-200 cursor-pointer transition-all duration-300",
            "peer-checked:bg-blue-600"
          ]}>
          </div>
        </label>
      </div>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  @doc """
  Renders radio inputs with label and error messages.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :errors, :list, default: []
  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form"

  attr :options, :list, default: [], doc: "a list of `{value, description}` tuples"

  attr :rest, :global

  def radio_field(assigns) do
    assigns = assigns_from_field(assigns)

    ~H"""
    <div phx-feedback-for={@name} class={[@errors != [] && "show-errors"]}>
      <div class="flex gap-4 text-gray-600">
        <label :for={{value, description} <- @options} class="flex items-center gap-2 cursor-pointer">
          <input
            type="radio"
            class="radio"
            name={@name}
            value={value}
            checked={to_string(@value) == value}
            {@rest}
          />
          <span><%= description %></span>
        </label>
      </div>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  @doc """
  Renders emoji input with label and error messages.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :errors, :list, default: []
  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form"

  attr :rest, :global

  def emoji_field(assigns) do
    assigns = assigns_from_field(assigns)

    ~H"""
    <.field_wrapper id={@id} name={@name} label={@label} errors={@errors}>
      <div class="flex border-[1px] bg-gray-50 rounded-lg space-x-4 items-center">
        <div
          id={"#{@id}-picker"}
          class="grid grid-cols-1 md:grid-cols-3 w-full"
          phx-hook="EmojiPicker"
        >
          <div class="place-content-start">
            <div class="p-1 pl-3">
              <span id={"#{@id}-preview"} data-emoji-preview><%= @value %></span>
            </div>
          </div>

          <div />

          <div class="flex items-center place-content-end">
            <button
              id={"#{@id}-button"}
              type="button"
              data-emoji-button
              class="p-1 pl-3 pr-3 rounded-tr-lg rounded-br-lg bg-gray-50 hover:bg-gray-100 active:bg-gray-200 border-l-[1px] bg-white flex justify-center items-center cursor-pointer"
            >
              <.remix_icon icon="emotion-line" class="text-xl" />
            </button>
          </div>
          <input
            type="hidden"
            name={@name}
            id={@id || @name}
            value={@value}
            class="hidden emoji-picker-input"
            data-emoji-input
          />
        </div>
      </div>
    </.field_wrapper>
    """
  end

  @doc """
  Renders select input with label and error messages.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :errors, :list, default: []
  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form"

  attr :options, :list, default: []
  attr :prompt, :string, default: nil

  attr :rest, :global

  def select_field(assigns) do
    assigns = assigns_from_field(assigns)

    ~H"""
    <.field_wrapper id={@id} name={@name} label={@label} errors={@errors}>
      <select id={@id} name={@name} class="input" {@rest}>
        <option :if={@prompt} value="" disabled selected><%= @prompt %></option>
        <%= Phoenix.HTML.Form.options_for_select(@options, @value) %>
      </select>
    </.field_wrapper>
    """
  end

  defp assigns_from_field(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(field.errors, &translate_error/1))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
  end

  defp assigns_from_field(assigns), do: assigns

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # Because the error messages we show in our forms and APIs
    # are defined inside Ecto, we need to translate them dynamically.
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  attr :id, :any, required: true
  attr :name, :any, required: true
  attr :label, :string, required: true
  attr :errors, :list, required: true
  slot :inner_block, required: true

  defp field_wrapper(assigns) do
    ~H"""
    <div phx-feedback-for={@name} class={[@errors != [] && "show-errors"]}>
      <.label :if={@label} for={@id}><%= @label %></.label>
      <%= render_slot(@inner_block) %>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="mb-1 block text-sm text-gray-800 font-medium">
      <%= render_slot(@inner_block) %>
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="text-red-600 text-sm hidden phx-form-error:block">
      <%= render_slot(@inner_block) %>
    </p>
    """
  end

  @doc """
  Renders a wrapper around password input with an added visibility
  toggle button.

  The toggle switches the input's type between `password` and `text`.

  ## Examples

      <.with_password_toggle id="secret-password-toggle">
        <input type="password" ...>
      </.with_password_toggle>

  """
  attr :id, :string, required: true

  slot :inner_block, required: true

  def with_password_toggle(assigns) do
    ~H"""
    <div id={@id} class="relative flex">
      <%= render_slot(@inner_block) %>
      <div class="flex items-center absolute inset-y-0 right-1">
        <button
          class="icon-button"
          data-show
          type="button"
          aria-label="show password"
          phx-click={
            JS.remove_attribute("type", to: "##{@id} input")
            |> JS.set_attribute({"type", "text"}, to: "##{@id} input")
            |> JS.add_class("hidden", to: "##{@id} [data-show]")
            |> JS.remove_class("hidden", to: "##{@id} [data-hide]")
          }
        >
          <.remix_icon icon="eye-line" class="text-xl" />
        </button>
        <button
          class="icon-button hidden"
          data-hide
          type="button"
          aria-label="hide password"
          phx-click={
            JS.remove_attribute("type", to: "##{@id} input")
            |> JS.set_attribute({"type", "password"}, to: "##{@id} input")
            |> JS.remove_class("hidden", to: "##{@id} [data-show]")
            |> JS.add_class("hidden", to: "##{@id} [data-hide]")
          }
        >
          <.remix_icon icon="eye-off-line" class="text-xl" />
        </button>
      </div>
    </div>
    """
  end
end
