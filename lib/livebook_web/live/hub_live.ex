defmodule LivebookWeb.HubLive do
  use LivebookWeb, :live_view

  import LivebookWeb.UserHelpers

  alias Livebook.Hub
  alias Livebook.Hub.Fly
  alias Livebook.Hub.Settings
  alias Livebook.Users.User
  alias LivebookWeb.{PageHelpers, SidebarHelpers}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> SidebarHelpers.sidebar_handlers()
     |> assign(
       selected_hub_service: nil,
       machines: [],
       machine_options: [],
       data: %{},
       page_title: "Livebook - Hub"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex grow h-full">
      <SidebarHelpers.sidebar
        socket={@socket}
        current_user={@current_user}
        current_page=""
        saved_hubs={@saved_hubs}
      />

      <div class="grow px-6 py-8 overflow-y-auto">
        <div class="max-w-screen-md w-full mx-auto px-4 pb-8 space-y-8">
          <div>
            <PageHelpers.title text="Hub" socket={@socket} />
            <p class="mt-4 text-gray-700">
              Here you can create your Hubs.
              Keep in mind that this configuration gets persisted and
              will be restored on application launch.
            </p>
            <p class="mt-4 text-gray-700">
              Follow the next steps to create you Hub configuration.
            </p>
          </div>

          <div class="flex flex-col space-y-4">
            <h2 class="text-xl text-gray-800 font-semibold pb-2 border-b border-gray-200">
              1. Select your Hub service
            </h2>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <.card_item id="fly" selected={@selected_hub_service} title="Fly">
                <:logo>
                  <.fly_logo />
                </:logo>
                <:headline>
                  Connect your Livebook on Fly
                </:headline>
              </.card_item>

              <.card_item id="enterprise" selected={@selected_hub_service} title="Livebook Enterprise">
                <:logo>
                  <img src="/images/logo.png" class="max-h-full max-w-[75%]" alt="Fly logo" />
                </:logo>
                <:headline>
                  Write notebooks in Livebook then securely deploy and share them
                  with your team and company with Livebook Enterprise.
                </:headline>
              </.card_item>
            </div>
          </div>

          <%= if @selected_hub_service do %>
            <div class="flex flex-col space-y-4">
              <h2 class="text-xl text-gray-800 font-semibold pb-2 border-b border-gray-200">
                2. Connect to your Hub with the following form
              </h2>

              <%= if @selected_hub_service == "fly" do %>
                <.fly_form socket={@socket} data={@data} machines={@machine_options} />
              <% end %>

              <%= if @selected_hub_service == "enterprise" do %>
                <div class="flex">
                  <span class="text-sm font-medium">
                    If you want to learn more, <a
                      href="https://livebook.dev/#livebook-plans"
                      class="pointer-events-auto text-blue-600"
                      target="_blank"
                    >click here</a>.
                  </span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <.current_user_modal current_user={@current_user} />
    </div>
    """
  end

  defp card_item(assigns) do
    ~H"""
    <div
      id={@id}
      class={"flex card-item flex-col " <> card_item_bg_color(@id, @selected)}
      phx-hook="SelectHubService"
    >
      <div class="flex items-center justify-center card-item--logo p-6 border-2 rounded-t-2xl h-[150px]">
        <%= render_slot(@logo) %>
      </div>
      <div class="card-item--body px-6 py-4 rounded-b-2xl grow">
        <p class="text-gray-800 font-semibold cursor-pointer mt-2 text-sm text-gray-600">
          <%= @title %>
        </p>

        <p class="mt-2 text-sm text-gray-600">
          <%= render_slot(@headline) %>
        </p>
      </div>
    </div>
    """
  end

  defp card_item_bg_color(id, selected) when id == selected, do: "selected"
  defp card_item_bg_color(_id, _selected), do: ""

  defp fly_logo(assigns) do
    ~H"""
    <svg
      role="img"
      class=""
      fill-rule="evenodd"
      viewBox="0 0 273 84"
      style="pointer-events: none; width: auto; height: 36px;"
      aria-labelledby="logo-title logo-description"
    >
      <title id="logo-title">Fly</title>
      <g buffered-rendering="static">
        <path
          d="M57.413 10.134h9.454c8.409 0 15.236 6.827 15.236 15.236v33.243c0 8.409-6.827 15.236-15.236 15.236h-.745c-4.328-.677-6.205-1.975-7.655-3.072l-12.02-9.883a1.692 1.692 0 0 0-2.128 0l-3.905 3.211-10.998-9.043a1.688 1.688 0 0 0-2.127 0L12.01 68.503c-3.075 2.501-5.109 2.039-6.428 1.894C2.175 67.601 0 63.359 0 58.613V25.37c0-8.409 6.827-15.236 15.237-15.236h9.433l-.017.038-.318.927-.099.318-.428 1.899-.059.333-.188 1.902-.025.522-.004.183.018.872.043.511.106.8.135.72.16.663.208.718.54 1.52.178.456.94 1.986.332.61 1.087 1.866.416.673 1.517 2.234.219.296 1.974 2.569.638.791 2.254 2.635.463.507 1.858 1.999.736.762 1.216 1.208-.244.204-.152.137c-.413.385-.805.794-1.172 1.224a10.42 10.42 0 0 0-.504.644 8.319 8.319 0 0 0-.651 1.064 6.234 6.234 0 0 0-.261.591 5.47 5.47 0 0 0-.353 1.606l-.007.475a5.64 5.64 0 0 0 .403 1.953 5.44 5.44 0 0 0 1.086 1.703c.338.36.723.674 1.145.932.359.22.742.401 1.14.539a6.39 6.39 0 0 0 2.692.306h.005a6.072 6.072 0 0 0 2.22-.659c.298-.158.582-.341.848-.549a5.438 5.438 0 0 0 1.71-2.274c.28-.699.417-1.446.405-2.198l-.022-.393a5.535 5.535 0 0 0-.368-1.513 6.284 6.284 0 0 0-.285-.618 8.49 8.49 0 0 0-.67-1.061 11.022 11.022 0 0 0-.354-.453 14.594 14.594 0 0 0-1.308-1.37l-.329-.28.557-.55 2.394-2.5.828-.909 1.287-1.448.837-.979 1.194-1.454.808-1.016 1.187-1.587.599-.821.85-1.271.708-1.083 1.334-2.323.763-1.524.022-.047.584-1.414a.531.531 0 0 0 .02-.056l.629-1.962.066-.286.273-1.562.053-.423.016-.259.019-.978-.005-.182-.05-.876-.062-.68-.31-1.961c-.005-.026-.01-.052-.018-.078l-.398-1.45-.137-.403-.179-.446Zm4.494 41.455a3.662 3.662 0 0 0-3.61 3.61 3.663 3.663 0 0 0 3.61 3.609 3.665 3.665 0 0 0 3.611-3.609 3.663 3.663 0 0 0-3.611-3.61Z"
          fill="url(#_Radial1)"
          fill-opacity="1"
        >
        </path>
        <path
          d="M32.915 73.849H15.237a15.171 15.171 0 0 1-9.655-3.452c1.319.145 3.353.607 6.428-1.894l15.279-13.441a1.688 1.688 0 0 1 2.127 0l10.998 9.043 3.905-3.211a1.692 1.692 0 0 1 2.128 0l12.02 9.883c1.45 1.097 3.327 2.395 7.655 3.072h-7.996a3.399 3.399 0 0 1-1.963-.654l-.14-.108-10.578-8.784-10.439 8.784a3.344 3.344 0 0 1-2.091.762Zm28.992-22.26a3.662 3.662 0 0 0-3.61 3.61 3.663 3.663 0 0 0 3.61 3.609 3.665 3.665 0 0 0 3.611-3.609 3.663 3.663 0 0 0-3.611-3.61ZM38.57 40.652l-1.216-1.208-.736-.762-1.858-1.999-.463-.507-2.254-2.635-.638-.791-1.974-2.569-.219-.296-1.517-2.234-.416-.673-1.087-1.866-.332-.61-.94-1.986-.178-.456-.54-1.52-.208-.718-.16-.663-.135-.72-.106-.8-.043-.511-.018-.872.004-.183.025-.522.188-1.902.059-.333.428-1.899.099-.318.318-.927.102-.24.506-1.112.351-.662.489-.806.487-.718.347-.456.4-.482.44-.484.377-.379.918-.808.671-.549c.016-.014.033-.026.05-.038l.794-.537.631-.402 1.198-.631c.018-.011.039-.02.058-.029l1.699-.705.157-.059 1.51-.442.638-.143.862-.173.572-.087.877-.109.598-.053 1.187-.063.465-.005.881.018.229.013 1.276.106 1.688.238.195.041 1.668.415.49.146.544.188.663.251.524.222.77.363.485.249.872.512.325.2 1.189.868.341.296.829.755.041.041.703.754.242.273.825 1.096.168.262.655 1.106.197.379.369.825.386.963.137.403.398 1.45a.731.731 0 0 1 .018.078l.31 1.961.062.68.05.876.005.182-.019.978-.016.259-.053.423-.273 1.562-.066.286-.629 1.962a.531.531 0 0 1-.02.056l-.584 1.414-.022.047-.763 1.524-1.334 2.323-.708 1.083-.85 1.271-.599.821-1.187 1.587-.808 1.016-1.194 1.454-.837.979-1.287 1.448-.828.909-2.394 2.5-.557.55.329.28c.465.428.902.885 1.308 1.37.122.148.24.299.354.453a8.49 8.49 0 0 1 .67 1.061c.106.2.201.407.285.618.191.484.32.996.368 1.513l.022.393a5.666 5.666 0 0 1-.405 2.198 5.438 5.438 0 0 1-1.71 2.274c-.266.208-.55.391-.848.549a6.072 6.072 0 0 1-2.22.659h-.005A6.39 6.39 0 0 1 39 51.724a5.854 5.854 0 0 1-1.14-.539 5.523 5.523 0 0 1-1.145-.932 5.44 5.44 0 0 1-1.086-1.703 5.64 5.64 0 0 1-.403-1.953l.007-.475a5.47 5.47 0 0 1 .353-1.606c.077-.202.164-.399.261-.591.19-.371.408-.726.651-1.064.159-.221.328-.436.504-.644.367-.43.759-.839 1.172-1.224l.152-.137.244-.204Z"
          fill="var(--darkreader-inline-fill)"
        >
        </path>
        <path
          d="m45.445 64.303 10.578 8.784a3.396 3.396 0 0 0 2.139.762H32.879c.776 0 1.528-.269 2.127-.762l10.439-8.784Zm-4.341-20.731.096.028c.031.015.057.037.085.056l.08.071c.198.182.39.373.575.569.13.139.257.282.379.43.155.187.3.383.432.587.057.09.11.181.16.276.043.082.082.167.116.253.06.15.105.308.119.469l-.003.302a1.723 1.723 0 0 1-.817 1.343 2.338 2.338 0 0 1-.994.327l-.373.011-.315-.028a2.398 2.398 0 0 1-.433-.105 2.07 2.07 0 0 1-.41-.192l-.246-.18a1.688 1.688 0 0 1-.56-.96 2.418 2.418 0 0 1-.029-.19l-.009-.288c.005-.078.017-.155.034-.232.043-.168.105-.331.183-.486a4.47 4.47 0 0 1 .344-.559c.213-.288.444-.562.691-.821.159-.168.322-.331.492-.488l.121-.109c.084-.056.085-.056.181-.084h.101ZM40.485 3.42l.039-.003v33.669l-.084-.155a94.125 94.125 0 0 1-3.093-6.268 67.022 67.022 0 0 1-2.099-5.255 41.439 41.439 0 0 1-1.265-4.327c-.266-1.163-.47-2.343-.554-3.535a17.312 17.312 0 0 1-.029-1.528c.008-.444.026-.887.054-1.33.044-.697.115-1.392.217-2.082.081-.543.181-1.084.305-1.619.098-.425.212-.847.342-1.262.188-.6.413-1.186.675-1.758.096-.206.199-.411.307-.612.65-1.204 1.532-2.313 2.687-3.055a5.617 5.617 0 0 1 2.498-.88Zm4.366.085 2.265.646c1.049.387 2.059.892 2.987 1.522a11.984 11.984 0 0 1 3.212 3.204c.503.748.919 1.555 1.244 2.398.471 1.247.763 2.554.866 3.883.03.348.047.697.054 1.046.008.324.006.649-.02.973a10.97 10.97 0 0 1-.407 2.14 16.94 16.94 0 0 1-.587 1.684c-.28.685-.591 1.357-.932 2.013-.755 1.458-1.624 2.853-2.554 4.202a65.451 65.451 0 0 1-3.683 4.806 91.058 91.058 0 0 1-4.418 4.897 93.697 93.697 0 0 0 2.908-5.95c.5-1.124.971-2.26 1.414-3.407a53.41 53.41 0 0 0 1.317-3.831c.29-.969.546-1.948.757-2.938.181-.849.323-1.707.411-2.57.074-.72.101-1.444.083-2.166a30.807 30.807 0 0 0-.049-1.325c-.106-1.776-.376-3.546-.894-5.249a15.341 15.341 0 0 0-.714-1.892c-.663-1.444-1.588-2.794-2.84-3.779l-.42-.307Z"
          fill="#fff"
        >
        </path>

        <path
          d="m188.849 65.24-11.341-24.279c-.947-2.023-1.511-2.762-2.458-3.62l-.923-.832c-.734-.713-1.217-1.372-1.217-2.157 0-1.123.888-2.067 2.508-2.067h9.846c1.546 0 2.508.804 2.508 2.004 0 .67-.308 1.172-.697 1.664-.462.586-1.063 1.157-1.063 2.197 0 .652.189 1.302.556 2.132l6.768 15.85 6.071-15.451c.373-1.028.629-1.933.629-2.658 0-1.127-.613-1.587-1.086-2.091-.411-.438-.74-.901-.74-1.643 0-1.212.986-2.004 2.313-2.004h6.064c1.7 0 2.508.879 2.508 2.004 0 .72-.414 1.386-1.23 2.105l-.858.705c-1.194.976-1.747 2.387-2.373 3.847l-9.195 22.152c-1.087 2.59-2.704 6.185-5.175 9.134-2.509 2.996-5.893 5.326-10.477 5.326-3.838 0-6.16-1.832-6.16-4.473 0-2.419 1.788-4.346 4.138-4.346 1.288 0 1.957.608 2.637 1.233.561.516 1.131 1.045 2.254 1.045 1.042 0 2.014-.441 2.893-1.152 1.343-1.087 2.47-2.798 3.3-4.625Zm66.644-.087c5.105 0 9.288-1.749 12.551-5.239 3.259-3.486 4.889-7.682 4.889-12.588 0-4.787-1.549-8.721-4.637-11.805-3.086-3.081-7.092-4.629-12.021-4.629-5.19 0-9.436 1.685-12.74 5.043-3.307 3.361-4.962 7.432-4.962 12.214 0 4.74 1.578 8.756 4.73 12.052 3.153 3.298 7.215 4.952 12.19 4.952Zm-43.168-.38c2.952 0 5.052-1.987 5.052-4.852 0-2.798-2.169-4.789-5.052-4.789-3.02 0-5.182 1.994-5.182 4.789 0 2.862 2.163 4.852 5.182 4.852Zm10.511-4.541.718-.759c.856-.831 1.13-1.67 1.13-3.982V41.82c0-1.999-.272-2.891-1.119-3.655l-.846-.758c-.827-.73-1.099-1.185-1.099-1.915 0-1.038.804-1.889 2.098-2.185l5.739-1.392c.549-.133 1.167-.263 1.648-.263.66 0 1.2.217 1.579.594s.603.921.603 1.6v21.645c0 2.183.265 3.198 1.176 3.964a.544.544 0 0 1 .042.041l.641.748c.806.784 1.141 1.304 1.141 2.019 0 1.275-.963 2.004-2.509 2.004h-9.715c-1.474 0-2.443-.725-2.443-2.004 0-.718.334-1.243 1.216-2.031Zm-64.946 0 .718-.759c.855-.831 1.13-1.67 1.13-3.982V26.948c0-1.936-.205-2.886-1.111-3.649l-.867-.84c-.749-.726-1.022-1.177-1.022-1.904 0-1.039.81-1.887 2.033-2.184l5.674-1.392c.549-.133 1.168-.263 1.648-.263.655 0 1.21.198 1.606.572.396.375.642.934.642 1.685v36.518c0 2.188.271 3.145 1.186 3.973l.732.774c.811.789 1.081 1.306 1.081 2.025 0 .529-.161.957-.449 1.282-.406.46-1.087.722-1.994.722h-9.716c-.907 0-1.587-.262-1.994-.722-.287-.325-.449-.753-.449-1.282 0-.72.267-1.241 1.152-2.031Zm-26.457-14.698v9.83c0 1.482.293 2.85 1.515 3.976l.789.765c.883.858 1.152 1.372 1.152 2.158 0 1.2-.963 2.004-2.508 2.004h-10.955c-1.545 0-2.508-.804-2.508-2.004 0-.933.274-1.375 1.157-2.162l.787-.763c.915-.83 1.512-1.96 1.512-3.974V29.099c0-1.6-.354-2.908-1.514-3.975l-.79-.766c-.812-.788-1.152-1.306-1.152-2.094 0-1.272.965-2.067 2.508-2.067h29.343c1.122 0 2.108.249 2.737.867.438.429.718 1.034.749 1.875l.457 6.774c.046.847-.204 1.553-.693 1.988-.336.299-.789.479-1.359.479-.718 0-1.269-.271-1.76-.739-.442-.421-.836-1.012-1.28-1.707-1.071-1.713-1.571-2.329-2.713-3.13-1.59-1.173-4.012-1.576-8.592-1.576-2.643 0-4.311.115-5.361.386-.68.175-1.072.403-1.282.737-.215.342-.239.775-.239 1.303v13.311h6.882c1.647 0 2.805-.297 4.147-2.132l.007-.01c.538-.685.927-1.189 1.297-1.524.432-.39.846-.574 1.396-.574 1.032 0 1.986.848 1.986 2.004v9.177c0 1.23-.957 2.068-1.986 2.068-.511 0-.928-.182-1.36-.564-.372-.328-.762-.817-1.269-1.473-1.468-1.9-2.505-2.203-4.218-2.203h-6.882Zm116.265-.233c0-3.292.717-5.658 2.204-7.081 1.468-1.405 3.047-2.116 4.743-2.116 2.334 0 4.436 1.305 6.332 3.874 1.939 2.625 2.897 6.174 2.897 10.639 0 3.296-.72 5.684-2.208 7.148-1.467 1.445-3.044 2.177-4.739 2.177-2.334 0-4.435-1.316-6.332-3.905-1.939-2.647-2.897-6.228-2.897-10.736Zm-19.201-17.805c2.958 0 5.051-1.664 5.051-4.536 0-2.804-2.091-4.472-5.051-4.472-3.029 0-5.117 1.67-5.117 4.472 0 2.802 2.089 4.536 5.117 4.536Z"
          fill="currentColor"
        >
        </path>
      </g>
      <defs>
        <radialGradient
          id="_Radial1"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(43.593 41.714) scale(59.4764)"
        >
          <stop offset="0" stop-color="#ba7bf0"></stop>
          <stop offset=".45" stop-color="#996bec"></stop>
          <stop offset="1" stop-color="#5046e4"></stop>
        </radialGradient>
      </defs>
    </svg>
    """
  end

  defp fly_form(assigns) do
    ~H"""
    <.form
      id="fly-form"
      class="flex flex-col space-y-4"
      let={f}
      for={:fly}
      phx-submit="save_hub"
      phx-change="update_data"
      phx-debounce="blur"
    >
      <div class="flex flex-col space-y-1">
        <h3 class="text-lg text-gray-800 font-semibold">
          Access Token
        </h3>
        <%= password_input(f, :token,
          phx_change: "fetch_machines",
          phx_debounce: "blur",
          value: @data["token"],
          class: "input w-full",
          autofocus: true,
          spellcheck: "false",
          autocomplete: "off"
        ) %>
      </div>

      <%= if length(@machines) > 0 do %>
        <div class="flex flex-col space-y-1">
          <h3 class="text-lg text-gray-800 font-semibold">
            Application
          </h3>
          <%= select(f, :application, @machines, class: "input") %>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div class="flex flex-col space-y-1">
            <h3 class="text-lg text-gray-800 font-semibold">
              Name
            </h3>
            <%= text_input(f, :name, value: @data["name"], class: "input") %>
          </div>

          <div class="flex flex-col space-y-1">
            <h3 class="text-lg text-gray-800 font-semibold">
              Color
            </h3>

            <div class="flex space-x-4 items-center">
              <.hex_color form={f} name="hex_color" value={@data["hex_color"]} />
            </div>
          </div>
        </div>

        <%= submit("Save", class: "button-base button-blue") %>
      <% end %>
    </.form>
    """
  end

  defp hex_color(assigns) do
    ~H"""
    <div
      class="border-[3px] rounded-lg p-1 flex justify-center items-center"
      style={"border-color: #{@value}"}
    >
      <div class="rounded h-5 w-5" style={"background-color: #{@value}"}></div>
    </div>
    <div class="relative grow">
      <%= text_input(@form, @name,
        value: @value,
        class: "input",
        spellcheck: "false",
        maxlength: 7
      ) %>
      <button class="icon-button absolute right-2 top-1" type="button" phx-click="randomize_color">
        <.remix_icon icon="refresh-line" class="text-xl" />
      </button>
    </div>
    """
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    machine = Settings.machine_by_id!(id)
    machines = [machine]

    data =
      case machine.hub do
        "fly" ->
          %{
            "application" => machine.id,
            "token" => machine.token,
            "name" => machine.name,
            "hex_color" => machine.color
          }
      end

    opts = select_machine_options(machines, data["application"])

    {:noreply,
     assign(socket,
       operation: :edit,
       selected_hub_service: machine.hub,
       data: data,
       machines: machines,
       machine_options: opts
     )}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, operation: :new)}
  end

  @impl true
  def handle_event("select_hub_service", %{"value" => service}, socket) do
    {:noreply, assign(socket, selected_hub_service: service)}
  end

  def handle_event("fetch_machines", %{"fly" => %{"token" => token}}, socket) do
    case Hub.fetch_machines(%Fly{token: token}) do
      {:ok, machines} ->
        data = %{"token" => token, "hex_color" => User.random_hex_color()}
        opts = select_machine_options(machines)

        {:noreply, assign(socket, data: data, machines: machines, machine_options: opts)}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(mahcines: [], machine_options: [], data: %{})
         |> put_flash(:error, "Invalid Access Token")}
    end
  end

  def handle_event("save_hub", %{"fly" => params}, socket) do
    case Enum.find(socket.assigns.machines, &(&1.id == params["application"])) do
      nil ->
        {:noreply,
         socket
         |> assign(data: params)
         |> put_flash(:error, "Internal Server Error")}

      selected_machine ->
        case {socket.assigns.operation, Settings.machine_exists?(selected_machine)} do
          {:new, false} ->
            {:noreply, save_fly_machine(socket, params, selected_machine)}

          {:edit, true} ->
            {:noreply, save_fly_machine(socket, params, selected_machine)}

          _any ->
            {:noreply,
             socket
             |> assign(data: params)
             |> put_flash(:error, "Hub already exists")}
        end
    end
  end

  def handle_event("update_data", %{"fly" => data}, socket) do
    opts = select_machine_options(socket.assigns.machines, data["application"])

    {:noreply, assign(socket, data: data, machine_options: opts)}
  end

  def handle_event("randomize_color", _, socket) do
    data = Map.put(socket.assigns.data, "hex_color", User.random_hex_color())
    {:noreply, assign(socket, data: data)}
  end

  defp save_fly_machine(socket, params, selected_machine) do
    opts = select_machine_options(socket.assigns.machines, params["application"])

    Settings.save_machine(%{
      selected_machine
      | name: params["name"],
        hub: socket.assigns.selected_hub_service,
        color: params["hex_color"],
        token: params["token"]
    })

    send(self(), :update_hub)

    assign(socket, data: params, machine_options: opts)
  end

  defp select_machine_options(machines, machine_id \\ nil) do
    for machine <- machines do
      if machine.id == machine_id do
        [key: machine.name, value: machine.id, selected: true]
      else
        [key: machine.name, value: machine.id]
      end
    end
  end
end
