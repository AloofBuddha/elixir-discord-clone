defmodule Discord.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :content, :text, null: false
      add :channel_id, references(:channels, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      timestamps()
    end

    create index(:messages, [:channel_id])
  end
end
