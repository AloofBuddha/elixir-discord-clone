defmodule Discord.Repo.Migrations.CreateServers do
  use Ecto.Migration

  def change do
    create table(:servers) do
      add :name, :string, null: false
      add :owner_id, references(:users, on_delete: :delete_all), null: false
      timestamps()
    end

    create index(:servers, [:owner_id])
  end
end
