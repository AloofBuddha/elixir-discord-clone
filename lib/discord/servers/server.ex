defmodule Discord.Servers.Server do
  use Ecto.Schema
  import Ecto.Changeset

  schema "servers" do
    field :name, :string
    field :invite_token, :string
    belongs_to :owner, Discord.Accounts.User
    has_many :channels, Discord.Servers.Channel
    has_many :memberships, Discord.Servers.Membership
    timestamps()
  end

  def changeset(server, attrs) do
    server
    |> cast(attrs, [:name, :owner_id, :invite_token])
    |> validate_required([:name, :owner_id])
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:invite_token)
  end
end
