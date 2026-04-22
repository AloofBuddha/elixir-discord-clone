defmodule DiscordWeb.InviteController do
  use DiscordWeb, :controller

  alias Discord.Servers

  def join(conn, %{"token" => token}) do
    user = conn.assigns.current_scope.user

    case Servers.get_server_by_invite_token(token) do
      nil ->
        conn
        |> put_flash(:error, "Invite link is invalid or has expired.")
        |> redirect(to: ~p"/channels")

      server ->
        case Servers.join_server(user, server) do
          {:ok, _} ->
            conn
            |> put_flash(:info, "You joined #{server.name}!")
            |> redirect(to: ~p"/channels/#{server.id}")

          {:error, _} ->
            conn
            |> put_flash(:error, "Could not join server.")
            |> redirect(to: ~p"/channels")
        end
    end
  end
end
