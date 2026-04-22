defmodule Discord.Repo.Migrations.CreateChannels do
  use Ecto.Migration

  def change do
    create table(:channels) do
      add :name, :string, null: false
      add :server_id, references(:servers, on_delete: :delete_all), null: false
      timestamps()
    end

    create index(:channels, [:server_id])
  end
end
