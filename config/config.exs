# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :discord, :scopes,
  user: [
    default: true,
    module: Discord.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Discord.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :discord,
  ecto_repos: [Discord.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :discord, DiscordWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DiscordWeb.ErrorHTML, json: DiscordWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Discord.PubSub,
  live_view: [signing_salt: "nDZJatKs"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  discord: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  discord: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :discord, Discord.Mailer, adapter: Swoosh.Adapters.Local

config :swoosh, :api_client, Swoosh.ApiClient.Finch
config :swoosh, :finch_name, Discord.Finch

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
