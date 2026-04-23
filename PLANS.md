# Plans

Milestones, in order. Check off as shipped.

---

## [x] Milestone 1 — Project foundation + auth

- Phoenix 1.8.5 + LiveView, PostgreSQL, deployed on Fly.io
- Auth: email/password, magic link, Google OAuth (via assent)
- Real email in prod via Resend; dev mailbox at /dev/mailbox
- Local secrets via dotenvy (.env)

## [x] Milestone 2 — Servers + channels

- Users can create and join servers (invite link system with unique tokens)
- Servers have text channels; defaults to #general on creation
- UI: server rail, channel sidebar, real-time message list

## [x] Milestone 3 — Real-time messaging

- Send and receive messages in a channel
- Live updates via Phoenix PubSub + LiveView (no page refresh)
- Messages persisted to PostgreSQL
- Two-user real-time flow tested and verified in integration tests

## [x] Milestone 4 — UX + quality of life

- Display names and avatars pulled from Google OAuth, refreshed on each login
- Display name field in user settings for password-registered users
- Removed non-functional UI (DM pane, broken invite button)
- /channels redirects to first server; empty state shows Create Server pane

## [ ] Milestone 5 — Single-machine benchmark ceiling

**Goal:** find the point where one Fly machine saturates, and document it.

**Why this matters:** Discord runs 400–500 Elixir machines handling 11M concurrent users
(~22–27k connections/machine). We want to know where our single machine lands and how
it compares before we scale out.

**What's built:**
- `BenchmarkChannel` + `UserSocket` — isolated Phoenix Channel for load testing, no auth overhead
- TypeScript load test (`bench/load_test.ts`) using the `ws` library with `performance.now()` timing
- Metrics: fan-out latency p50/p95/p99, delivery rate %, throughput msg/s, connection join time
- Warmup period relative to script start (accounts for Fly cold starts)
- Results saved to `bench/results.json` and visualized in `bench/report.html` (Chart.js)

**Workload matches Discord's real pattern:**
- VUs distributed across N channels (`--channels` flag, default 10)
- Messages fan out only within a channel — not a single global broadcast
- 10% of VUs are senders; 90% are passive receivers
- Channel sizes approximate real Discord servers (small: 10–50, medium: 100–500, large: 1000+)

**To run:**
```bash
# Single run
cd bench && npm run bench -- --url wss://discord-clone-lingering-frog-1488.fly.dev --vus 1000 --duration 30

# Full ramp-up: 100 → 500 → 1000 → 2500 → 5000 VUs, then opens report
npm run rampup:prod

# Higher ceiling (upgrade Fly machine first)
npm run rampup -- --url wss://discord-clone-lingering-frog-1488.fly.dev --max-vus 25000
```

**Status:** in progress — need to run the ramp-up and find the saturation point.

## [ ] Milestone 6 — Horizontal scaling with libcluster

**Goal:** show that adding Fly machines scales linearly, matching Discord's architecture.

**The story:** Node.js needs Redis + manual sharding to scale horizontally. Phoenix PubSub
on BEAM works across nodes transparently — add `libcluster`, deploy two machines, and the
same benchmark numbers should roughly double with no application code changes.

**Plan:**
- Add `libcluster` with Fly DNS-based node discovery (`Cluster.Strategy.DNSPoll`)
- Verify PubSub fan-out works across nodes (channel subscriber on node A receives message
  sent by node B)
- Run same ramp-up against 2-machine cluster, compare with single-node results
- Scale to N machines and plot throughput vs machine count
- Target: approach Discord's cluster-level numbers (11M+ concurrent connections across N nodes)

**Discord reference numbers (public engineering blog):**
- 2017: 5M concurrent users on Elixir cluster
- 2020: 11M concurrent users, ~26k events/sec
- 2022: 19M peak concurrent users, 4B messages/day
- Largest single server: 16M+ members, 2M concurrent (Midjourney)
- Architecture: each guild is a GenServer process; fan-out via Manifold library to remote nodes
