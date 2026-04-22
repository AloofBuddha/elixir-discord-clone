defmodule Discord.Repo.Migrations.CreateServerMemberships do
  use Ecto.Migration

  def change do
    create table(:server_memberships) do
      add :server_id, references(:servers, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      timestamps()
    end

    create unique_index(:server_memberships, [:server_id, :user_id])
    create index(:server_memberships, [:user_id])
  end
end
