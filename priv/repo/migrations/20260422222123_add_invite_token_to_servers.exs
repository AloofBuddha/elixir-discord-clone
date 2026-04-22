defmodule Discord.Repo.Migrations.AddInviteTokenToServers do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add :invite_token, :string
    end

    create unique_index(:servers, [:invite_token])
  end
end
