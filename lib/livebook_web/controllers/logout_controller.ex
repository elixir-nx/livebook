defmodule LivebookWeb.LogoutController do
  use LivebookWeb, :controller

  def logout(conn, _params) do
    if get_session(conn, :user_id) do
      conn
      |> configure_session(renew: true)
      |> clear_session()
      |> render("logout.html")
    else
      redirect(conn, to: ~p"/")
    end
  end
end
