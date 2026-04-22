defmodule Discord.Servers.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :content, :string
    belongs_to :channel, Discord.Servers.Channel
    belongs_to :user, Discord.Accounts.User
    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:content, :channel_id, :user_id])
    |> validate_required([:content, :channel_id, :user_id])
    |> validate_length(:content, min: 1, max: 2000)
  end
end
