defmodule Discord.Accounts.UserIdentity do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_identities" do
    field :provider, :string
    field :uid, :string

    belongs_to :user, Discord.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:provider, :uid, :user_id])
    |> validate_required([:provider, :uid, :user_id])
    |> unique_constraint([:provider, :uid])
  end
end
