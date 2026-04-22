defmodule Discord.ServersTest do
  use Discord.DataCase, async: true

  alias Discord.Servers
  import Discord.AccountsFixtures
  import Discord.ServersFixtures

  describe "create_server/2" do
    test "creates server with a name, invite token, #general channel, and owner membership" do
      user = user_fixture()
      assert {:ok, server} = Servers.create_server(user, %{"name" => "My Server"})

      assert server.name == "My Server"
      assert server.owner_id == user.id
      assert is_binary(server.invite_token)

      assert [channel] = Servers.list_channels(server)
      assert channel.name == "general"

      assert [member_server] = Servers.list_servers_for_user(user)
      assert member_server.id == server.id
    end

    test "returns error for blank name" do
      user = user_fixture()
      assert {:error, changeset} = Servers.create_server(user, %{"name" => ""})
      assert %{name: [_ | _]} = errors_on(changeset)
    end
  end

  describe "list_servers_for_user/1" do
    test "returns only servers the user is a member of" do
      user_a = user_fixture()
      user_b = user_fixture()
      {:ok, _server_a} = Servers.create_server(user_a, %{"name" => "Server A"})
      {:ok, server_b} = Servers.create_server(user_b, %{"name" => "Server B"})

      assert [result] = Servers.list_servers_for_user(user_b)
      assert result.id == server_b.id
    end

    test "returns empty list when user has no servers" do
      user = user_fixture()
      assert [] = Servers.list_servers_for_user(user)
    end

    test "returns multiple servers in insertion order" do
      user = user_fixture()
      {:ok, s1} = Servers.create_server(user, %{"name" => "First"})
      {:ok, s2} = Servers.create_server(user, %{"name" => "Second"})

      ids = Servers.list_servers_for_user(user) |> Enum.map(& &1.id)
      assert ids == [s1.id, s2.id]
    end
  end

  describe "join_server/2" do
    test "adds a second user to an existing server" do
      owner = user_fixture()
      joiner = user_fixture()
      server = server_fixture(owner)

      assert {:ok, _} = Servers.join_server(joiner, server)
      assert Enum.any?(Servers.list_servers_for_user(joiner), &(&1.id == server.id))
    end

    test "is idempotent when joining a server the user is already in" do
      user = user_fixture()
      server = server_fixture(user)

      # Already a member from create_server — joining again should not error
      assert {:ok, _} = Servers.join_server(user, server)
      assert length(Servers.list_servers_for_user(user)) == 1
    end
  end

  describe "get_server_by_invite_token/1" do
    test "returns the server for a valid token" do
      user = user_fixture()
      server = server_fixture(user)

      found = Servers.get_server_by_invite_token(server.invite_token)
      assert found.id == server.id
    end

    test "returns nil for an unknown token" do
      assert nil == Servers.get_server_by_invite_token("no-such-token")
    end
  end

  describe "create_message/3" do
    test "persists the message and broadcasts it to the channel topic" do
      user = user_fixture()
      server = server_fixture(user)
      channel = channel_fixture(server)

      Phoenix.PubSub.subscribe(Discord.PubSub, "channel:#{channel.id}")

      assert {:ok, message} = Servers.create_message(user, channel, "hello!")
      assert message.content == "hello!"
      assert message.user.id == user.id

      assert_receive {:new_message, broadcast}
      assert broadcast.content == "hello!"
      assert broadcast.id == message.id
    end

    test "returns error for blank content" do
      user = user_fixture()
      server = server_fixture(user)
      channel = channel_fixture(server)

      assert {:error, changeset} = Servers.create_message(user, channel, "")
      assert %{content: [_ | _]} = errors_on(changeset)
    end
  end

  describe "list_messages/1" do
    test "returns messages in chronological order with users preloaded" do
      user = user_fixture()
      server = server_fixture(user)
      channel = channel_fixture(server)

      {:ok, _} = Servers.create_message(user, channel, "first")
      {:ok, _} = Servers.create_message(user, channel, "second")

      messages = Servers.list_messages(channel)
      assert length(messages) == 2
      assert hd(messages).content == "first"
      assert hd(messages).user.id == user.id
    end

    test "returns empty list for a channel with no messages" do
      user = user_fixture()
      server = server_fixture(user)
      channel = channel_fixture(server)

      assert [] = Servers.list_messages(channel)
    end
  end
end
