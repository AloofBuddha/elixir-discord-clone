defmodule Discord.Servers.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  schema "channels" do
    field :name, :string
    belongs_to :server, Discord.Servers.Server
    timestamps()
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name, :server_id])
    |> validate_required([:name, :server_id])
    |> validate_length(:name, min: 1, max: 100)
  end
end
