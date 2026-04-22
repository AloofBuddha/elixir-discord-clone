# Building a Discord Clone in Elixir — A Learning Guide

This document is a running tutorial built alongside the project. Each section maps
to a step in the build, explains the Elixir concepts introduced, and shows the actual
code we wrote with annotations.

---

## Table of Contents

1. [Why Elixir for Discord?](#1-why-elixir-for-discord)
2. [The Elixir Ecosystem (Mix, OTP, BEAM)](#2-the-elixir-ecosystem)
3. [Project Structure](#3-project-structure)
4. [What Happens When You Start the App](#4-what-happens-when-you-start-the-app)
   - [Boot sequence: mix phx.server](#boot-sequence)
   - [What happens on a single HTTP request](#what-happens-on-a-single-http-request)
   - [The full GET / trace, annotated](#the-full-get--trace)
5. [Step 1: Authentication — Ecto Schemas, Changesets, Migrations](#5-step-1-authentication)
   - [Migrations](#migrations)
   - [Schemas](#schemas)
   - [Changesets](#changesets)
   - [Contexts](#contexts)
   - [The Router and Plugs](#the-router-and-plugs)
6. [What's Next](#6-whats-next)

---

## 1. Why Elixir for Discord?

Discord serves ~19 million concurrent users. Their original Go backend was struggling
with the load of maintaining millions of long-lived WebSocket connections. They rewrote
the affected services in Elixir. Here's why that made sense:

### The BEAM Virtual Machine

Elixir compiles to bytecode that runs on the BEAM (Erlang Virtual Machine). BEAM was
built by Ericsson in the 1980s for telephone switches that needed **99.9999999% uptime**
and needed to handle **millions of simultaneous calls**. Its design directly translates
to concurrent web apps.

Key BEAM properties:
- **Lightweight processes**: Each BEAM process costs ~2KB of RAM. An OS thread costs
  ~2MB. You can run millions of BEAM processes on a single machine.
- **Isolated processes**: Processes don't share memory. They communicate via message
  passing. If one crashes, it doesn't take others down.
- **Preemptive scheduling**: The scheduler interrupts long-running processes, so no
  single process can starve others. This gives consistent latency under load.
- **Garbage collection per-process**: Each process has its own tiny heap. GC pauses
  affect only that process, not your whole app.

### What this means for a Discord clone

In our app, each connected user's LiveView session is its own BEAM process. Broadcasting
a message to 100,000 users in a channel is handled by `Phoenix.PubSub`, which fans out
to all subscribed processes efficiently — not a loop you write.

---

## 2. The Elixir Ecosystem

### Mix — The Build Tool

`mix` is Elixir's built-in build tool (like `npm` for Node or `cargo` for Rust).

```bash
mix phx.new .        # Scaffold a new Phoenix project
mix deps.get         # Install dependencies (reads mix.exs, like npm install reads package.json)
mix ecto.migrate     # Run database migrations
mix phx.server       # Start the dev server
mix test             # Run tests
```

Dependencies are declared in `mix.exs`:

```elixir
defp deps do
  [
    {:phoenix, "~> 1.8.5"},       # ~> means "compatible with" (1.8.x)
    {:ecto_sql, "~> 3.13"},       # Database ORM/query layer
    {:postgrex, ">= 0.0.0"},      # PostgreSQL driver
    {:bcrypt_elixir, "~> 3.0"},   # Password hashing
    {:swoosh, "~> 1.4"},          # Email sending
    {:finch, "~> 0.13"},          # HTTP client (Swoosh uses it)
  ]
end
```

### OTP — Open Telecom Platform

OTP is a set of design principles and libraries for building fault-tolerant systems.
The three concepts you'll encounter constantly:

**1. Application** — The top-level container for your running system. Our app starts in
`lib/discord/application.ex`.

**2. Supervisor** — A process whose only job is to watch other processes and restart them
if they crash. This is how Elixir achieves fault tolerance — you design a recovery
strategy, not defensive code.

**3. GenServer** — A generic server process. Holds state, responds to messages. You'll
write these when we build real-time chat.

Our `application.ex` starts a supervision tree:

```elixir
children = [
  DiscordWeb.Telemetry,          # Metrics collection process
  Discord.Repo,                  # Database connection pool process
  {DNSCluster, ...},             # Service discovery process
  {Phoenix.PubSub, name: Discord.PubSub},  # Message broadcast bus
  {Finch, name: Discord.Finch}, # HTTP connection pool
  DiscordWeb.Endpoint,          # Web server process
]

Supervisor.start_link(children, strategy: :one_for_one)
```

`strategy: :one_for_one` means: if any child crashes, restart only that child (not all
of them). Other strategies exist: `:one_for_all` (restart everything) and
`:rest_for_one` (restart the crashed process and all that started after it).

---

## 3. Project Structure

```
discord-clone/
├── lib/
│   ├── discord/              # Domain layer — pure business logic, no web
│   │   ├── application.ex    # OTP Application entry point
│   │   ├── repo.ex           # Ecto Repo (database interface)
│   │   ├── mailer.ex         # Email sending
│   │   └── accounts/         # "Accounts" context (auth domain)
│   │       ├── user.ex           # User schema + changesets
│   │       ├── user_token.ex     # Session/magic-link tokens
│   │       ├── user_notifier.ex  # Emails sent to users
│   │       └── scope.ex          # Auth scope (what the current user can see)
│   └── discord_web/          # Web layer — HTTP, WebSocket, LiveView
│       ├── endpoint.ex       # Entry point for all connections
│       ├── router.ex         # URL → handler mapping
│       ├── user_auth.ex      # Auth plugs (middleware)
│       ├── controllers/      # Traditional HTTP handlers
│       └── components/       # Reusable UI (HEEx templates)
├── priv/
│   └── repo/
│       └── migrations/       # SQL migrations (versioned, committed to git)
├── config/
│   ├── config.exs            # Base config (all environments)
│   ├── dev.exs               # Dev overrides
│   ├── test.exs              # Test overrides
│   └── runtime.exs           # Runtime config (environment variables)
└── mix.exs                   # Project definition + dependencies
```

**The key split**: `discord/` knows nothing about HTTP. `discord_web/` knows nothing
about business rules. This makes both testable in isolation. When we add chat, the
message persistence logic lives in `discord/`, the LiveView UI in `discord_web/`.

---

## 4. What Happens When You Start the App

### Boot sequence

When you run `mix phx.server`, here is the exact sequence of events:

```
mix phx.server
    │
    ▼
1. Mix compiles all .ex files in lib/ → .beam bytecode in _build/
    │
    ▼
2. Mix starts the OTP Application defined in mix.exs:
      mod: {Discord.Application, []}
    │
    ▼
3. Discord.Application.start/2 is called
   (lib/discord/application.ex)
    │
    ▼
4. A top-level Supervisor is started with these children, IN ORDER:
    │
    ├── DiscordWeb.Telemetry        — starts metrics collection
    ├── Discord.Repo                — opens a pool of DB connections (default: 10)
    ├── DNSCluster                  — service discovery (for multi-node clusters)
    ├── Phoenix.PubSub              — starts the message broadcast bus
    ├── Finch                       — opens HTTP connection pools (for email sending)
    └── DiscordWeb.Endpoint         — starts the web server on port 4000
    │
    ▼
5. Bandit (the HTTP server) begins accepting TCP connections on 127.0.0.1:4000
    │
    ▼
6. In dev: two watchers also start as external OS processes:
    ├── esbuild (watches assets/js/)
    └── tailwind (watches assets/css/)
```

All of steps 4–6 happen in under a second. Each child is itself a process (or a tree
of processes). If `Discord.Repo` crashes (e.g., DB goes down), the supervisor restarts
it. The other processes keep running.

Here is `application.ex` with annotations:

```elixir
defmodule Discord.Application do
  use Application   # Tells OTP: this module IS the application entry point

  @impl true        # @impl marks this as implementing a behaviour callback
  def start(_type, _args) do
    children = [
      DiscordWeb.Telemetry,
      Discord.Repo,
      {DNSCluster, query: Application.get_env(:discord, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Discord.PubSub},
      {Finch, name: Discord.Finch},
      DiscordWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Discord.Supervisor]
    #                  ^
    #                  If one child crashes, restart only that child.
    #                  The others keep running.
    Supervisor.start_link(children, opts)
  end
end
```

**Why does order matter?**
`Discord.Repo` must start before `DiscordWeb.Endpoint` because when the first request
comes in, the endpoint will need the Repo to be available. `Phoenix.PubSub` must start
before the Endpoint because LiveView uses PubSub internally.

---

### What happens on a single HTTP request

Once the server is running, every HTTP request follows this path:

```
Browser sends: GET / HTTP/1.1
    │
    ▼
Bandit (TCP layer) accepts the connection, spawns a new process for it
    │
    ▼
DiscordWeb.Endpoint  (lib/discord_web/endpoint.ex)
— runs each plug in sequence:
    │
    ├── Plug.Static          — check if this is a static file (JS/CSS/images)
    │                          if yes, serve it and stop here
    ├── Phoenix.LiveReloader — (dev only) inject live-reload JS into pages
    ├── Phoenix.CodeReloader — (dev only) recompile changed files before serving
    ├── Plug.RequestId       — attach a unique ID to this request for logging
    ├── Plug.Telemetry       — emit a "request started" metric event
    ├── Plug.Parsers         — parse the request body (JSON, form data, multipart)
    ├── Plug.MethodOverride  — allow PUT/PATCH/DELETE via POST + hidden field
    ├── Plug.Head            — respond to HEAD requests like GET but no body
    ├── Plug.Session         — decrypt and load session data from cookie
    └── DiscordWeb.Router    — decide what to do with this request
    │
    ▼
DiscordWeb.Router  (lib/discord_web/router.ex)
— matches the path against route definitions
— runs the :browser pipeline:
    │
    ├── :accepts             — only accept "html" content type
    ├── :fetch_session       — make session data accessible
    ├── :fetch_live_flash    — load flash messages (e.g., "Logged in!")
    ├── :put_root_layout     — wrap response in root.html.heex
    ├── :protect_from_forgery — verify CSRF token on POST/PUT/DELETE
    ├── :put_secure_browser_headers — add X-Frame-Options, CSP, etc.
    └── :fetch_current_scope_for_user — look up current user from session token
    │
    ▼
Route matched: GET "/" → PageController.home/2
    │
    ▼
DiscordWeb.PageController.home(conn, params)
— calls render(conn, :home)
— Phoenix finds lib/discord_web/controllers/page_html/home.html.heex
— renders it inside the root layout
    │
    ▼
Response: 200 OK + HTML body sent back to browser
```

---

### The full GET / trace, annotated

Here is every file touched when you visit `http://localhost:4000/`:

**1. `lib/discord_web/endpoint.ex`** — The front door. Every request enters here.
The plug pipeline is defined at the module level and runs top to bottom.

**2. `lib/discord_web/router.ex`** — Pattern-matches the path and method.
`GET /` matches `get "/", PageController, :home`. The `:browser` pipeline runs first.

**3. `lib/discord_web/user_auth.ex` → `fetch_current_scope_for_user`** — Called as
part of the `:browser` pipeline. Reads the `_discord_key` cookie, extracts the session
token, calls `Discord.Accounts.get_user_by_session_token(token)`, and puts the result
into `conn.assigns.current_scope`. Every controller and template can now read
`@current_scope`.

**4. `lib/discord_web/controllers/page_controller.ex`** — The matched controller.
`home/2` receives `conn` (the full request/response struct) and `params` (URL params).
Calls `render(conn, :home)`.

**5. `lib/discord_web/controllers/page_html.ex`** — Phoenix uses this module to find
the template. The `embed_templates "page_html/*"` call at compile time reads every
`.heex` file in that directory and compiles it into a function.

**6. `lib/discord_web/controllers/page_html/home.html.heex`** — The actual HTML
template. HEEx = HTML + Elixir Expressions. `<%= ... %>` evaluates Elixir, `<.component>`
calls a function component.

**7. `lib/discord_web/components/layouts/root.html.heex`** — The outer shell.
The rendered page content is injected at `<%= @inner_content %>`. This is where
the `<html>`, `<head>`, and global nav live.

---

### Key language concepts visible in this flow

**`conn` — the connection struct**

Everything in Phoenix revolves around `%Plug.Conn{}`. It holds:
- The request (method, path, headers, body, params)
- The response (status, headers, body being built)
- Assigns (a map for passing data: `conn.assigns.current_scope`)
- Session data

Each plug receives `conn`, does something to it, and returns the modified `conn`.
It's immutable data being transformed — no global state, no mutation.

```elixir
# A plug is just a function that takes conn and returns conn
def put_request_id(conn, _opts) do
  request_id = generate_id()
  conn
  |> put_resp_header("x-request-id", request_id)
  |> assign(:request_id, request_id)
end
```

**Pattern matching on function arguments**

You see this everywhere in Elixir. Functions can have multiple clauses:

```elixir
# Only matches if user has a DateTime in authenticated_at
def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
  DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
end

# Catch-all — any other user struct
def sudo_mode?(_user, _minutes), do: false
```

Elixir tries each clause top to bottom and runs the first one that matches.
This is not `if/else` — it's structural matching on the shape and values of data.

**Atoms**

`:browser`, `:html`, `:one_for_one`, `:ok`, `:error` — these are atoms.
In other languages these would be strings or enums. In Elixir, atoms are:
- Stored as integers internally (a global atom table)
- Used everywhere as keys, tags, and status indicators
- Never garbage collected (so never create them dynamically from user input)

---

## 5. Step 1: Authentication

We generated authentication with:

```bash
mix phx.gen.auth Accounts User users
```

This command created the entire auth system. Let's understand what each piece is.

### Migrations

File: `priv/repo/migrations/20260422165718_create_users_auth_tables.exs`

```elixir
defmodule Discord.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    # citext = case-insensitive text — emails are case-insensitive by convention
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:users) do
      add :email, :citext, null: false
      add :hashed_password, :string     # nil when using magic link login
      add :confirmed_at, :utc_datetime  # nil until email confirmed

      timestamps(type: :utc_datetime)   # adds inserted_at and updated_at
    end

    create unique_index(:users, [:email])

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false  # "session", "login", "change:email"
      add :sent_to, :string               # email address the token was sent to
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
```

**Key concepts:**
- The filename timestamp is the migration version. Migrations run in order and are
  tracked in a `schema_migrations` table. Never edit a migration after it's been run.
- `def change` instead of `def up`/`def down` — Ecto can infer the rollback from
  the `change` definition automatically. For complex cases, use `up`/`down`.
- `on_delete: :delete_all` — when a user is deleted, their tokens cascade-delete.
  This is enforced at the database level, not in application code.

Run with: `mix ecto.migrate` | Rollback with: `mix ecto.rollback`

---

### Schemas

File: `lib/discord/accounts/user.ex`

A schema maps a database table to an Elixir struct:

```elixir
defmodule Discord.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    #                         ^-- virtual: not stored in DB, only in memory
    #                                        ^-- redact: omitted from logs/inspect
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
```

After defining this schema, Elixir gives you a struct:

```elixir
%Discord.Accounts.User{
  id: nil,
  email: nil,
  password: nil,       # virtual — exists in memory, not the DB
  hashed_password: nil,
  confirmed_at: nil,
  inserted_at: nil,
  updated_at: nil
}
```

**Elixir structs are just maps with a known shape.** They don't have methods.
Behavior lives in separate functions that take the struct as an argument.

---

### Changesets

This is one of Elixir's best ideas. A **changeset** is a data structure that
represents a *proposed change* to a schema, along with validations and errors.
It's not a change that has happened — it's a change that *might* happen.

```elixir
def email_changeset(user, attrs, opts \\ []) do
  user
  |> cast(attrs, [:email])          # 1. Pull :email out of the attrs map
  |> validate_required([:email])    # 2. Error if email is blank
  |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/)  # 3. Must look like email
  |> validate_length(:email, max: 160)
  |> unsafe_validate_unique(:email, Discord.Repo)  # 4. DB check (not guaranteed)
  |> unique_constraint(:email)                     # 5. DB constraint (guaranteed)
end
```

**The pipe operator `|>`** — this is core Elixir syntax. It passes the result of the
left expression as the first argument to the right function:

```elixir
# These are identical:
validate_required(cast(user, attrs, [:email]), [:email])

user |> cast(attrs, [:email]) |> validate_required([:email])
```

The pipe operator makes data transformation chains readable — you read them top to
bottom like a pipeline.

**Why two uniqueness checks?**

- `unsafe_validate_unique` — queries the DB *before* inserting to give the user a
  friendly error immediately. "Unsafe" because of race conditions (two requests at
  the same millisecond could both pass this check).
- `unique_constraint` — catches the database-level unique index violation and
  converts it to a changeset error instead of crashing.

**Password hashing in the changeset:**

```elixir
defp maybe_hash_password(changeset, opts) do
  hash_password? = Keyword.get(opts, :hash_password, true)
  password = get_change(changeset, :password)

  if hash_password? && password && changeset.valid? do
    changeset
    |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
    |> delete_change(:password)   # Clear plaintext from memory
  else
    changeset
  end
end
```

Notice: hashing only happens if `changeset.valid?` is true. No point hashing if
there are already validation errors. The `opts` pattern (`hash_password: false`) is
used by LiveView forms to validate without hashing on every keystroke.

---

### Contexts

File: `lib/discord/accounts.ex`

A **context** is a module that acts as the public API for a domain of your app.
External code (controllers, LiveViews) calls the context. The context calls schemas,
changesets, and Repo. This is the boundary.

```elixir
defmodule Discord.Accounts do
  alias Discord.Repo
  alias Discord.Accounts.{User, UserToken, UserNotifier}

  # Simple Repo query — find user by email
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  # Compound operation — look up + verify password
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  # Write operation — build changeset, insert if valid
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
    # Returns {:ok, user} or {:error, changeset}
  end
end
```

**Pattern: `{:ok, result}` / `{:error, reason}`**

Functions that can fail return a tagged tuple. Callers pattern-match on the result:

```elixir
case Discord.Accounts.register_user(params) do
  {:ok, user}        -> redirect to login
  {:error, changeset} -> re-render form with errors
end
```

This is Elixir's alternative to exceptions for expected failure cases. Use exceptions
for truly unexpected errors (programmer mistakes), tagged tuples for expected failures
(bad user input, DB constraint violations).

**Guard clauses (`when is_binary(email)`)** — these are compile-time assertions on
function arguments. If you call `get_user_by_email(123)`, Elixir won't match this
function clause and will raise a `FunctionClauseError`. This is intentional — it
catches type errors early.

---

### The Router and Plugs

File: `lib/discord_web/router.ex`

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, html: {DiscordWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers
  plug :fetch_current_scope_for_user   # ← injected by phx.gen.auth
end
```

A **Plug** is a module (or function) that transforms a connection (`%Plug.Conn{}`).
A pipeline is a sequence of plugs applied in order. Every HTTP request passes through
a pipeline before hitting a controller or LiveView.

`fetch_current_scope_for_user` (from `user_auth.ex`) reads the session token, looks up
the user in the database, and assigns them to `conn.assigns.current_scope`. Every
controller and LiveView then has access to the current user without doing another DB lookup.

**Route scopes with auth guards:**

```elixir
# Only accessible when NOT logged in (redirect logged-in users away)
scope "/", DiscordWeb do
  pipe_through [:browser, :redirect_if_user_is_authenticated]

  get "/users/register", UserRegistrationController, :new
  post "/users/register", UserRegistrationController, :create
end

# Only accessible when logged in (redirect anonymous users to login)
scope "/", DiscordWeb do
  pipe_through [:browser, :require_authenticated_user]

  get "/users/settings", UserSettingsController, :edit
end
```

`redirect_if_user_is_authenticated` and `require_authenticated_user` are plugs defined
in `user_auth.ex`. They check `conn.assigns.current_scope` and either call
`next_plug(conn)` to continue or redirect.

---

## 6. What's Next

| Step | Feature | Concepts |
|------|---------|---------|
| **Done** | User auth (register, login, sessions) | Schemas, changesets, migrations, contexts, plugs |
| **Next → 2** | Servers + Channels (CRUD) | More Ecto queries, many-to-many associations, context design |
| 3 | Real-time messaging | Phoenix PubSub, GenServer state |
| 4 | LiveView chat UI | LiveView lifecycle, assigns, handle_event/handle_info |
| 5 | Online presence | Phoenix.Presence |
| 6 | Benchmarking | Tsung/k6, BEAM Observer, `:observer.start()` |
| 7 | Deploy | Mix releases, Fly.io |
