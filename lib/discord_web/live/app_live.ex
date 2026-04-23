defmodule DiscordWeb.AppLive do
  use DiscordWeb, :live_view

  alias Discord.Servers

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    servers = Servers.list_servers_for_user(user)

    {:ok,
     assign(socket,
       servers: servers,
       current_server: nil,
       current_channel: nil,
       channels: [],
       messages: [],
       message_input: "",
       show_create_modal: false,
       show_invite_modal: false,
       server_name: "",
       create_form: to_form(%{"name" => ""}, as: :server)
     )}
  end

  @impl true
  def handle_params(%{"server_id" => server_id, "channel_id" => channel_id}, _uri, socket) do
    server = find_server(socket, server_id)
    channels = if server, do: Servers.list_channels(server), else: []
    channel = Enum.find(channels, &(to_string(&1.id) == channel_id))

    socket =
      socket
      |> maybe_unsubscribe()
      |> assign(current_server: server, channels: channels, current_channel: channel)
      |> load_messages_and_subscribe(channel)

    {:noreply, socket}
  end

  def handle_params(%{"server_id" => server_id}, _uri, socket) do
    server = find_server(socket, server_id)
    channels = if server, do: Servers.list_channels(server), else: []

    socket = maybe_unsubscribe(socket)

    socket =
      case channels do
        [first | _] ->
          push_patch(socket, to: ~p"/channels/#{server_id}/#{first.id}")

        [] ->
          assign(socket, current_server: server, channels: [], current_channel: nil, messages: [])
      end

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    socket = maybe_unsubscribe(socket)

    {:noreply,
     assign(socket, current_server: nil, channels: [], current_channel: nil, messages: [])}
  end

  @impl true
  def handle_event("show_create_modal", _, socket) do
    {:noreply,
     assign(socket,
       show_create_modal: true,
       server_name: "",
       create_form: to_form(%{"name" => ""}, as: :server)
     )}
  end

  def handle_event("hide_create_modal", _, socket) do
    {:noreply, assign(socket, show_create_modal: false)}
  end

  def handle_event("validate_server", %{"server" => %{"name" => name}}, socket) do
    {:noreply, assign(socket, server_name: name)}
  end

  def handle_event("create_server", %{"server" => %{"name" => name}}, socket) do
    name = String.trim(name)
    user = socket.assigns.current_scope.user

    case Servers.create_server(user, %{"name" => name}) do
      {:ok, server} ->
        servers = socket.assigns.servers ++ [server]

        {:noreply,
         socket
         |> assign(servers: servers, show_create_modal: false)
         |> push_navigate(to: ~p"/channels/#{server.id}")
         |> put_flash(:info, "Server \"#{name}\" created!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create server.")}
    end
  end

  def handle_event("show_invite_modal", _, socket) do
    {:noreply, assign(socket, show_invite_modal: true)}
  end

  def handle_event("hide_invite_modal", _, socket) do
    {:noreply, assign(socket, show_invite_modal: false)}
  end

  def handle_event("update_message_input", %{"content" => value}, socket) do
    {:noreply, assign(socket, message_input: value)}
  end

  def handle_event("send_message", %{"content" => content}, socket) do
    content = String.trim(content)
    user = socket.assigns.current_scope.user
    channel = socket.assigns.current_channel

    if content != "" and channel do
      case Servers.create_message(user, channel, content) do
        {:ok, _message} ->
          {:noreply, assign(socket, message_input: "")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not send message.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    {:noreply, update(socket, :messages, &(&1 ++ [message]))}
  end

  # --- Private helpers ---

  defp find_server(socket, server_id) do
    Enum.find(socket.assigns.servers, &(to_string(&1.id) == server_id))
  end

  defp load_messages_and_subscribe(socket, nil), do: assign(socket, messages: [])

  defp load_messages_and_subscribe(socket, channel) do
    Servers.subscribe_to_channel(channel)
    assign(socket, messages: Servers.list_messages(channel))
  end

  defp maybe_unsubscribe(socket) do
    if channel = socket.assigns[:current_channel] do
      Phoenix.PubSub.unsubscribe(Discord.PubSub, "channel:#{channel.id}")
    end

    socket
  end

  # --- Template helpers ---

  defp server_btn_class(active) do
    base =
      "size-12 flex items-center justify-center font-semibold text-sm transition-all duration-200 cursor-pointer"

    if active do
      base <> " rounded-2xl bg-primary text-primary-content"
    else
      base <>
        " rounded-full bg-base-100 text-base-content hover:rounded-2xl hover:bg-primary hover:text-primary-content"
    end
  end

  defp indicator_class(active) do
    base =
      "absolute left-0 top-1/2 -translate-y-1/2 w-1 rounded-r-full bg-base-content transition-all duration-200"

    if active do
      base <> " h-8"
    else
      base <> " h-2 opacity-0 group-hover/item:opacity-100 group-hover/item:h-5"
    end
  end

  defp server_initials(name) do
    name
    |> String.split()
    |> Enum.map(&String.first/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
  end

  defp user_display_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp user_display_name(%{email: email}), do: email |> String.split("@") |> hd()

  defp user_initial(user), do: user |> user_display_name() |> String.first() |> String.upcase()
end
