defmodule DiscordWeb.UserSessionHTML do
  use DiscordWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:discord, Discord.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
