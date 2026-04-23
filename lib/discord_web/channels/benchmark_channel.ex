defmodule DiscordWeb.BenchmarkChannel do
  use Phoenix.Channel

  def join("bench:" <> _room, _payload, socket), do: {:ok, socket}

  # Client sends a ping with a sent_at timestamp; broadcast to all subscribers.
  # Each recipient (including sender) receives the pong and can compute fan-out latency.
  def handle_in("ping", %{"sent_at" => _} = payload, socket) do
    broadcast!(socket, "pong", payload)
    {:noreply, socket}
  end
end
