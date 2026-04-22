# Plans

Milestones, in order. Check off as shipped.

---

## [x] Milestone 1 — Project foundation + auth

- Phoenix 1.8.5 + LiveView, PostgreSQL, deployed on Fly.io
- Auth: email/password, magic link, Google OAuth (via assent)
- Real email in prod via Resend; dev mailbox at /dev/mailbox
- Local secrets via dotenvy (.env)

## [ ] Milestone 2 — Servers + channels

- Users can create and join servers
- Servers have text channels
- Basic UI: server list sidebar, channel list, empty message area

## [ ] Milestone 3 — Real-time messaging

- Send and receive messages in a channel
- Live updates via Phoenix PubSub + LiveView (no page refresh)
- Messages persisted to PostgreSQL

## [ ] Milestone 4 — Benchmark

- Write a load test (k6 or similar) simulating concurrent users in a channel
- Measure: messages/sec, memory per connection, latency at percentiles
- Compare against a Node.js/Socket.io equivalent baseline
- Document results
