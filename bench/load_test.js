/**
 * Phoenix Channel fan-out load test
 *
 * Each VU connects to bench:lobby. ~10% of VUs send a ping every 2s.
 * Two latency metrics are tracked:
 *
 *   roundtrip_ms   — sender's own round-trip using performance.now() (sub-ms precision).
 *                    Meaningful even on localhost.
 *
 *   fanout_ms      — wall-clock delivery latency for non-sender VUs using Date.now().
 *                    Floors to 0ms on localhost; meaningful in production (latency > 1ms).
 *
 * Usage:
 *   # Basic run (100 VUs, 30s) with live dashboard at http://localhost:5665
 *   K6_WEB_DASHBOARD=true K6_WEB_DASHBOARD_EXPORT=bench/report.html \
 *     k6 run bench/load_test.js
 *
 *   # Stress test
 *   K6_WEB_DASHBOARD=true K6_WEB_DASHBOARD_EXPORT=bench/report.html \
 *     k6 run --vus 1000 --duration 60s bench/load_test.js
 *
 *   # Against production
 *   K6_WEB_DASHBOARD=true K6_WEB_DASHBOARD_EXPORT=bench/report.html \
 *     WS_URL=wss://your-app.fly.dev \
 *     k6 run --vus 1000 --duration 60s bench/load_test.js
 */

import ws from "k6/ws";
import { check, sleep } from "k6";
import { Trend, Counter } from "k6/metrics";

const roundtripMs = new Trend("roundtrip_ms", true);
const fanoutMs = new Trend("fanout_ms", true);
const messagesReceived = new Counter("messages_received");
const connectErrors = new Counter("connect_errors");

const WS_URL = __ENV.WS_URL || "ws://localhost:4000";
const isSender = () => __VU % 10 === 0;

export const options = {
  vus: 100,
  duration: "30s",
  thresholds: {
    roundtrip_ms: ["p(50)<10", "p(95)<50", "p(99)<200"],
    fanout_ms: ["p(95)<500"],
    connect_errors: ["count<10"],
  },
  ext: {
    dashboard: {
      export: "bench/report.html",
    },
  },
};

// Phoenix Channel v2 wire format: [join_ref, ref, topic, event, payload]
function encode(joinRef, ref, topic, event, payload) {
  return JSON.stringify([joinRef, ref, topic, event, payload]);
}

export default function () {
  const topic = "bench:lobby";
  const joinRef = String(__VU);
  let ref = 0;
  let joined = false;

  // Track send times for round-trip measurement (sender VU only)
  const pending = {};

  const res = ws.connect(`${WS_URL}/bench/websocket?vsn=2.0.0`, {}, (socket) => {
    socket.on("open", () => {
      socket.send(encode(joinRef, String(++ref), topic, "phx_join", {}));
    });

    socket.on("message", (raw) => {
      const [, msgRef, , event, payload] = JSON.parse(raw);

      if (event === "phx_reply" && !joined) {
        joined = true;
      }

      if (event === "pong") {
        messagesReceived.add(1);

        // Sub-ms round-trip: sender checks its own pending map
        if (pending[msgRef]) {
          roundtripMs.add(performance.now() - pending[msgRef]);
          delete pending[msgRef];
        } else if (payload.sent_at) {
          // Wall-clock fan-out latency for non-sender VUs
          fanoutMs.add(Date.now() - payload.sent_at);
        }
      }

      // Phoenix heartbeat — server sends these; echo back to keep connection alive
      if (event === "heartbeat") {
        socket.send(encode(null, String(++ref), "phoenix", "heartbeat", {}));
      }
    });

    socket.on("error", () => {
      connectErrors.add(1);
      socket.close();
    });

    // Sender VUs: start pinging after join settles
    if (isSender()) {
      socket.setTimeout(() => {
        const interval = socket.setInterval(() => {
          if (!joined) return;
          const pingRef = String(++ref);
          pending[pingRef] = performance.now();
          socket.send(
            encode(null, pingRef, topic, "ping", { sent_at: Date.now() })
          );
        }, 2000);

        socket.setTimeout(() => socket.clearInterval(interval), 25000);
      }, 500);
    }

    socket.setTimeout(() => socket.close(), 28000);
  });

  check(res, { "ws connected": (r) => r && r.status === 101 });
  sleep(1);
}
