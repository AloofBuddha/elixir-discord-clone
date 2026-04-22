defmodule Discord.Servers do
  import Ecto.Query
  alias Discord.Repo
  alias Discord.Servers.{Server, Channel, Membership, Message}

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

  def get_channel(id), do: Repo.get(Channel, id)

  def list_channels(server) do
    Repo.all(from c in Channel, where: c.server_id == ^server.id, order_by: [asc: c.inserted_at])
  end

  def list_messages(channel, limit \\ 50) do
    Repo.all(
      from m in Message,
        where: m.channel_id == ^channel.id,
        order_by: [asc: m.inserted_at],
        limit: ^limit,
        preload: [:user]
    )
  end

  def create_message(user, channel, content) do
    %Message{}
    |> Message.changeset(%{"content" => content, "channel_id" => channel.id, "user_id" => user.id})
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        message = %{message | user: user}
        Phoenix.PubSub.broadcast(Discord.PubSub, channel_topic(channel), {:new_message, message})
        {:ok, message}

      error ->
        error
    end
  end

  def subscribe_to_channel(channel) do
    Phoenix.PubSub.subscribe(Discord.PubSub, channel_topic(channel))
  end

  def get_server_by_invite_token(token) when is_binary(token) do
    Repo.get_by(Server, invite_token: token)
  end

  def join_server(user, server) do
    %Membership{}
    |> Membership.changeset(%{"server_id" => server.id, "user_id" => user.id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:server_id, :user_id])
    |> case do
      {:ok, _} -> {:ok, server}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def create_server(user, attrs) do
    token = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)

    changeset =
      %Server{}
      |> Server.changeset(attrs |> Map.put("owner_id", user.id) |> Map.put("invite_token", token))

    if changeset.valid? do
      Repo.transaction(fn ->
        server = Repo.insert!(changeset)

        %Channel{}
        |> Channel.changeset(%{"name" => "general", "server_id" => server.id})
        |> Repo.insert!()

        %Membership{}
        |> Membership.changeset(%{"server_id" => server.id, "user_id" => user.id})
        |> Repo.insert!()

        server
      end)
    else
      {:error, changeset}
    end
  end

  defp channel_topic(channel), do: "channel:#{channel.id}"
end
