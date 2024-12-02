defmodule LivebookWeb.SidebarHook do
  use LivebookWeb, :verified_routes
  require Logger

  import Phoenix.Component
  import Phoenix.LiveView
  import LivebookWeb.Confirm

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      Livebook.Hubs.Broadcasts.subscribe([:crud, :connection])
      Phoenix.PubSub.subscribe(Livebook.PubSub, "sidebar")
    end

    socket =
      socket
      |> assign(saved_hubs: Livebook.Hubs.get_metadata())
      |> attach_hook(:hubs, :handle_info, &handle_info/2)
      |> attach_hook(:shutdown, :handle_info, &handle_info/2)
      |> attach_hook(:shutdown, :handle_event, &handle_event/3)
      |> attach_hook(:logout, :handle_info, &handle_info/2)
      |> attach_hook(:logout, :handle_event, &handle_event/3)

    {:cont, socket}
  end

  defp handle_info(:shutdown, socket) do
    {:halt, put_flash(socket, :info, "Livebook is shutting down. You can close this page.")}
  end

  defp handle_info(:logout, socket) do
    {_type, module, _key} = Livebook.Config.identity_provider()

    case module.logout(LivebookWeb.ZTA, socket) do
      :ok ->
        Livebook.Users.unsubscribe(socket.assigns.current_user.id)

        {:halt,
         socket
         |> assign(current_user: nil)
         |> redirect(to: ~p"/logout")}

      :error ->
        {:cont, socket}
    end
  end

  @connection_events ~w(hub_connected hub_changed hub_deleted)a

  defp handle_info(event, socket) when elem(event, 0) in @connection_events do
    {:cont, assign(socket, saved_hubs: Livebook.Hubs.get_metadata())}
  end

  defp handle_info({:hub_connection_failed, _hub_id, _reason}, socket) do
    {:cont, assign(socket, saved_hubs: Livebook.Hubs.get_metadata())}
  end

  defp handle_info({:hub_server_error, _hub_id, error}, socket) do
    {:cont,
     socket
     |> assign(saved_hubs: Livebook.Hubs.get_metadata())
     |> put_flash(:error, error)}
  end

  defp handle_info(_event, socket), do: {:cont, socket}

  defp handle_event("shutdown", _params, socket) do
    on_confirm = fn socket ->
      Livebook.Config.shutdown()
      socket
    end

    {:halt,
     confirm(socket, on_confirm,
       title: "Shut Down",
       description: "Are you sure you want to shut down Livebook now?",
       confirm_text: "Shut Down",
       confirm_icon: "shut-down-line"
     )}
  end

  defp handle_event("logout", _params, socket) do
    on_confirm = fn socket ->
      Phoenix.PubSub.broadcast(Livebook.PubSub, "sidebar", :logout)
      put_flash(socket, :info, "Livebook is logging out. You will be redirected soon.")
    end

    {:halt,
     confirm(socket, on_confirm,
       title: "Log out",
       description: "Are you sure you want to log out Livebook now?",
       confirm_text: "Log out",
       confirm_icon: "logout-box-line"
     )}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
