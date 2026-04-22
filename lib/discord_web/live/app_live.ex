defmodule DiscordWeb.AppLive do
  use DiscordWeb, :live_view

  @mock_servers [
    %{id: "1", name: "My Server"},
    %{id: "2", name: "Gaming Hub"}
  ]

  @mock_channels %{
    "1" => ["general", "random", "announcements"],
    "2" => ["general", "off-topic"]
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       servers: @mock_servers,
       current_server: nil,
       channels: [],
       show_create_modal: false,
       show_invite_modal: false,
       server_name: "",
       create_form: to_form(%{"name" => ""}, as: :server)
     )}
  end

  @impl true
  def handle_params(%{"server_id" => server_id}, _uri, socket) do
    server = Enum.find(socket.assigns.servers, &(&1.id == server_id))
    channels = Map.get(@mock_channels, server_id, ["general"])
    {:noreply, assign(socket, current_server: server, channels: channels)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, current_server: nil, channels: [])}
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
    new_id = :erlang.unique_integer([:positive]) |> to_string()
    new_server = %{id: new_id, name: name}
    servers = socket.assigns.servers ++ [new_server]

    {:noreply,
     socket
     |> assign(servers: servers, show_create_modal: false)
     |> push_navigate(to: ~p"/channels/#{new_id}")
     |> put_flash(:info, "Server \"#{name}\" created!")}
  end

  def handle_event("show_invite_modal", _, socket) do
    {:noreply, assign(socket, show_invite_modal: true)}
  end

  def handle_event("hide_invite_modal", _, socket) do
    {:noreply, assign(socket, show_invite_modal: false)}
  end

  # --- Helpers used in the template ---

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

  defp user_initial(email), do: email |> String.first() |> String.upcase()
  defp username(email), do: email |> String.split("@") |> hd()
end
