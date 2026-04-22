defmodule Discord.Servers do
  import Ecto.Query
  alias Discord.Repo
  alias Discord.Servers.{Server, Channel, Membership}

  def list_servers_for_user(user) do
    Repo.all(
      from s in Server,
        join: m in Membership,
        on: m.server_id == s.id,
        where: m.user_id == ^user.id,
        order_by: [asc: s.inserted_at]
    )
  end

  def get_server(id), do: Repo.get(Server, id)

  def list_channels(server) do
    Repo.all(from c in Channel, where: c.server_id == ^server.id, order_by: [asc: c.inserted_at])
  end

  def create_server(user, attrs) do
    Repo.transaction(fn ->
      server =
        %Server{}
        |> Server.changeset(Map.put(attrs, "owner_id", user.id))
        |> Repo.insert!()

      %Channel{}
      |> Channel.changeset(%{"name" => "general", "server_id" => server.id})
      |> Repo.insert!()

      %Membership{}
      |> Membership.changeset(%{"server_id" => server.id, "user_id" => user.id})
      |> Repo.insert!()

      server
    end)
  end
end
