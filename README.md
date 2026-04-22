# Discord Clone (Elixir/Phoenix)

A basic Discord clone built with Elixir + Phoenix LiveView. The primary goal is to build a working real-time messaging app and benchmark its performance under load — specifically to see how far the BEAM can be pushed compared to a typical Node.js equivalent.

## What's built

- User auth: email/password, magic link, and Google OAuth
- Deployed on Fly.io

## What's next

- Servers and channels
- Real-time messaging via LiveView + PubSub
- Load benchmarking

## Running locally

```bash
cp .env.example .env   # add Google OAuth credentials
mix setup              # install deps, create and migrate DB
mix phx.server         # http://localhost:4000
```

Dev email is captured at `http://localhost:4000/dev/mailbox`.

## Deployment

Hosted on Fly.io. Migrations run automatically on deploy.

```bash
fly secrets set RESEND_API_KEY=... GOOGLE_CLIENT_ID=... GOOGLE_CLIENT_SECRET=...
fly deploy
```

## Tech stack

- Elixir / Phoenix 1.8 + LiveView
- PostgreSQL
- Swoosh (Resend adapter in prod)
- Assent (Google OAuth)
- Fly.io
