defmodule DiscordWeb.OAuthController do
  use DiscordWeb, :controller

  alias Discord.Accounts
  alias DiscordWeb.UserAuth

  def request(conn, %{"provider" => provider}) do
    config = provider_config(provider, conn)
    strategy = config[:strategy]

    case strategy.authorize_url(config) do
      {:ok, %{url: url, session_params: session_params}} ->
        conn
        |> put_session(:oauth_session_params, session_params)
        |> redirect(external: url)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not connect to #{provider}. Please try again.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def callback(conn, %{"provider" => provider} = params) do
    session_params = get_session(conn, :oauth_session_params)
    config = provider_config(provider, conn) |> Keyword.put(:session_params, session_params)
    strategy = config[:strategy]

    with {:ok, %{user: userinfo}} <- strategy.callback(config, params),
         {:ok, user} <- Accounts.find_or_create_from_oauth(provider, userinfo) do
      conn
      |> delete_session(:oauth_session_params)
      |> put_flash(:info, "Welcome!")
      |> UserAuth.log_in_user(user, %{})
    else
      {:error, _reason} ->
        conn
        |> put_flash(:error, "Authentication failed. Please try again.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  defp provider_config("google", conn) do
    google = Application.get_env(:discord, :google_oauth, [])

    [
      strategy: Assent.Strategy.Google,
      client_id: google[:client_id],
      client_secret: google[:client_secret],
      redirect_uri: url(conn, ~p"/auth/google/callback"),
      http_adapter: {Assent.HTTPAdapter.Httpc, transport_opts: [cacerts: :certifi.cacerts()]}
    ]
  end
end
