defmodule DiscordWeb.AppLiveTest do
  # async: false required — LiveView processes share the DB sandbox and PubSub
  use DiscordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Discord.AccountsFixtures
  import Discord.ServersFixtures

  alias Discord.Servers

  describe "authentication" do
    test "redirects unauthenticated users to login" do
      conn = build_conn()
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/channels")
      assert path =~ "/users/log-in"
    end
  end

  describe "empty state" do
    setup :register_and_log_in_user

    test "shows 'no server selected' when user has no servers", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/channels")
      assert html =~ "No server selected"
    end
  end

  describe "server creation" do
    setup :register_and_log_in_user

    test "creates a server in the DB with a name and invite token", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/channels")

      lv |> element("button[title='Create a Server']") |> render_click()

      lv
      |> form("form[phx-submit='create_server']", %{server: %{name: "New Server"}})
      |> render_submit()

      assert [server] = Servers.list_servers_for_user(user)
      assert server.name == "New Server"
      assert is_binary(server.invite_token)
    end

    test "shows the server initials in the rail when loading the page", %{conn: conn, user: user} do
      {:ok, server} = Servers.create_server(user, %{"name" => "Rail Server"})
      channel = channel_fixture(server)
      {:ok, _lv, html} = live(conn, ~p"/channels/#{server.id}/#{channel.id}")
      assert html =~ "RS"
    end
  end

  describe "real-time messaging between two users" do
    setup do
      user_a = user_fixture()
      user_b = user_fixture()
      server = server_fixture(user_a)
      {:ok, _} = Servers.join_server(user_b, server)
      channel = channel_fixture(server)
      %{user_a: user_a, user_b: user_b, server: server, channel: channel}
    end

    test "both users see each other's messages live", %{
      conn: conn,
      user_a: user_a,
      user_b: user_b,
      server: server,
      channel: channel
    } do
      {:ok, lv_a, _} = live(log_in_user(conn, user_a), ~p"/channels/#{server.id}/#{channel.id}")
      {:ok, lv_b, _} = live(log_in_user(conn, user_b), ~p"/channels/#{server.id}/#{channel.id}")

      # A sends a message
      lv_a |> form("form[phx-submit='send_message']", %{content: "hey from A"}) |> render_submit()

      assert render(lv_a) =~ "hey from A"
      assert render(lv_b) =~ "hey from A"

      # B replies
      lv_b |> form("form[phx-submit='send_message']", %{content: "hey from B"}) |> render_submit()

      assert render(lv_a) =~ "hey from B"
      assert render(lv_b) =~ "hey from B"
    end

    test "messages persist — visible on reconnect", %{
      conn: conn,
      user_a: user_a,
      server: server,
      channel: channel
    } do
      conn_a = log_in_user(conn, user_a)
      {:ok, lv, _} = live(conn_a, ~p"/channels/#{server.id}/#{channel.id}")
      lv |> form("form[phx-submit='send_message']", %{content: "persisted!"}) |> render_submit()

      # Fresh mount simulates reconnect
      {:ok, _lv2, html} = live(conn_a, ~p"/channels/#{server.id}/#{channel.id}")
      assert html =~ "persisted!"
    end

    test "joining via invite link adds user to the server", %{
      conn: conn,
      server: server
    } do
      outsider = user_fixture()
      conn_out = log_in_user(conn, outsider)

      conn_out = get(conn_out, ~p"/invite/#{server.invite_token}")
      assert redirected_to(conn_out) =~ "/channels/#{server.id}"

      assert Enum.any?(Servers.list_servers_for_user(outsider), &(&1.id == server.id))
    end
  end
end
