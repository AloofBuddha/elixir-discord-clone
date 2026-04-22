defmodule Discord.Repo do
  use Ecto.Repo,
    otp_app: :discord,
    adapter: Ecto.Adapters.Postgres
end
