defmodule Discord.Servers.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  schema "server_memberships" do
    belongs_to :server, Discord.Servers.Server
    belongs_to :user, Discord.Accounts.User
    timestamps()
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:server_id, :user_id])
    |> validate_required([:server_id, :user_id])
    |> unique_constraint([:server_id, :user_id])
  end
end
