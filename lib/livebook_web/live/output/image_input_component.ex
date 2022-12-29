defmodule LivebookWeb.Output.ImageInputComponent do
  use LivebookWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok, assign(socket, initialized: false)}
  end

  @impl true
  def update(assigns, socket) do
    {value, assigns} = Map.pop!(assigns, :value)

    socket = assign(socket, assigns)

    socket =
      if socket.assigns.initialized do
        socket
      else
        socket =
          if value do
            push_event(socket, "image_input_init:#{socket.assigns.id}", %{
              data: Base.encode64(value.data),
              height: value.height,
              width: value.width
            })
          else
            socket
          end

        assign(socket, initialized: true)
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"#{@id}-root"}
      class="inline-flex flex-col p-4 border-2 border-dashed border-gray-200 rounded-lg"
      phx-hook="ImageInput"
      phx-update="ignore"
      data-id={@id}
      data-phx-target={@target}
      data-height={@height}
      data-width={@width}
      data-format={@format}
      data-fit={@fit}
    >
      <input type="file" data-input class="hidden" name="value" accept="image/*" capture="user" />
      <div class="flex justify-center" data-preview>
        <div class="flex justify-center text-gray-500">
          Drag an image file
        </div>
      </div>
      <div class="hidden flex justify-center" data-camera-preview></div>
      <div class="mt-4 flex items-center justify-center gap-4">
        <.menu id={"#{@id}-camera-select-menu"} position="bottom-left">
          <:toggle>
            <button
              class="button-base button-gray border-transparent py-2 px-4 inline-flex text-gray-500"
              data-btn-open-camera
            >
              <.remix_icon icon="camera-line" class="text-lg leading-none mr-2" />
              <span>Open camera</span>
            </button>
          </:toggle>
          <:content>
            <div data-camera-list></div>
          </:content>
        </.menu>
        <button
          class="hidden button-base button-gray border-transparent py-2 px-4 inline-flex text-gray-500"
          data-btn-capture-camera
        >
          <.remix_icon icon="camera-line" class="text-lg leading-none mr-2" />
          <span>Take photo</span>
        </button>
        <button
          class="hidden button-base button-gray border-transparent py-2 px-4 inline-flex text-gray-500"
          data-btn-cancel
        >
          <.remix_icon icon="close-circle-line" class="text-lg leading-none mr-2" />
          <span>Cancel</span>
        </button>
        <button
          class="button-base button-gray border-transparent py-2 px-4 inline-flex text-gray-500"
          data-btn-upload
        >
          <.remix_icon icon="upload-2-line" class="text-lg leading-none mr-2" />
          <span>Upload</span>
        </button>
      </div>
    </div>
    """
  end
end
