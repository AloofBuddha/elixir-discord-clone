defmodule DiscordWeb.PageController do
  use DiscordWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
