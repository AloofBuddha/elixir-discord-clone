defmodule Discord.ServersFixtures do
  alias Discord.Servers
  import Discord.AccountsFixtures

  def server_fixture(user \\ nil) do
    user = user || user_fixture()

    {:ok, server} =
      Servers.create_server(user, %{"name" => "Test Server #{System.unique_integer()}"})

    server
  end

  def channel_fixture(server) do
    Servers.list_channels(server) |> hd()
  end
end
