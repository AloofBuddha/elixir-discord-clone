import WebSocket from "ws";
import { performance } from "perf_hooks";
import { existsSync, readFileSync, writeFileSync } from "fs";
import { resolve } from "path";

// --- Config ---
function arg(flag: string, fallback: string): string {
  const idx = process.argv.indexOf(flag);
  return idx !== -1 ? (process.argv[idx + 1] ?? fallback) : fallback;
}

const VUS = parseInt(arg("--vus", process.env.VUS ?? "100"));
const DURATION_S = parseInt(arg("--duration", process.env.DURATION ?? "30"));
const CHANNELS = parseInt(arg("--channels", process.env.CHANNELS ?? "10"));
const WS_URL = arg("--url", process.env.WS_URL ?? "ws://localhost:4000");
const TAG = arg("--tag", "");
const PING_INTERVAL_MS = 2000;

// Spread connection starts over RAMP_S seconds to avoid a connection storm.
// Default: 1s per 100 VUs, capped at 10s. Warmup begins after ramp completes.
const RAMP_S = parseFloat(arg("--ramp", String(Math.min(10, Math.ceil(VUS / 100)))));
const WARMUP_S = parseInt(arg("--warmup", process.env.WARMUP ?? "5"));

// --- Types ---
type PhxMessage = [string | null, string | null, string, string, Record<string, unknown>];

// --- Metrics ---
const latencies: number[] = [];
const joinTimes: number[] = [];
let messagesReceived = 0;
let pingsSent = 0;
let connectErrors = 0;
let connected = 0;

// --- Helpers ---
function encode(joinRef: string | null, ref: string, topic: string, event: string, payload: object): string {
  return JSON.stringify([joinRef, ref, topic, event, payload]);
}

function percentile(sorted: number[], p: number): number {
  if (sorted.length === 0) return 0;
  const idx = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.max(0, idx)];
}

// Distribute VUs across channels the same way Discord distributes users across channels:
// many channels each with a fraction of total users. Messages only fan out within a channel.
function channelFor(vuId: number): string {
  return `bench:room_${(vuId - 1) % CHANNELS}`;
}

// --- VU ---
async function runVU(id: number, stop: Promise<void>, scriptStart: number): Promise<void> {
  return new Promise((resolve) => {
    const joinRef = String(id);
    const topic = channelFor(id);
    let ref = 0;
    let joined = false;
    const isSender = id % 10 === 0;
    let pingTimer: ReturnType<typeof setInterval> | null = null;
    const connectStart = Date.now();

    const ws = new WebSocket(`${WS_URL}/bench/websocket?vsn=2.0.0`);

    stop.then(() => {
      if (pingTimer) clearInterval(pingTimer);
      if (ws.readyState === WebSocket.OPEN) ws.close();
    });

    ws.on("error", () => { connectErrors++; });
    ws.on("close", resolve);

    ws.on("open", () => {
      connected++;
      ws.send(encode(joinRef, String(++ref), topic, "phx_join", {}));
    });

    ws.on("message", (data) => {
      const [, , , event, payload] = JSON.parse(data.toString()) as PhxMessage;

      if (event === "phx_reply" && !joined) {
        joined = true;
        joinTimes.push(Date.now() - connectStart);

        if (isSender) {
          // Senders wait until ramp + warmup have elapsed from script start,
          // ensuring all VUs have connected before any pings fire
          const measureStart = (RAMP_S + WARMUP_S) * 1000;
          const remainingWarmup = Math.max(0, measureStart - (Date.now() - scriptStart));
          setTimeout(() => {
            pingTimer = setInterval(() => {
              pingsSent++;
              ws.send(encode(joinRef, String(++ref), topic, "ping", {
                sent_at: Date.now(),
                sent_at_hires: performance.now(),
              }));
            }, PING_INTERVAL_MS);
          }, remainingWarmup);
        }
      }

      if (event === "pong") {
        messagesReceived++;
        const hiRes = payload?.sent_at_hires as number | undefined;
        const msRes = payload?.sent_at as number | undefined;
        if (hiRes !== undefined) {
          latencies.push(performance.now() - hiRes);
        } else if (msRes !== undefined) {
          latencies.push(Date.now() - msRes);
        }
      }
    });
  });
}

// --- Main ---
async function main() {
  const vusPerChannel = Math.floor(VUS / CHANNELS);
  const senders = Math.ceil(VUS / 10);
  const sendersPerChannel = Math.ceil(senders / CHANNELS);
  const pingsPerSender = Math.floor((DURATION_S * 1000) / PING_INTERVAL_MS);
  // Each ping fans out only to VUs in the same channel
  const expectedMessages = senders * pingsPerSender * vusPerChannel;

  console.log("\nPhoenix Channel Fan-out Benchmark");
  console.log(`  Target:            ${WS_URL}`);
  console.log(`  VUs:               ${VUS}  across ${CHANNELS} channels (~${vusPerChannel} per channel)`);
  console.log(`  Senders:           ${senders} total (~${sendersPerChannel} per channel)`);
  console.log(`  Ramp:              ${RAMP_S}s  (connections staggered, ~${Math.round(VUS / RAMP_S)}/s)`);
  console.log(`  Warmup:            ${WARMUP_S}s  (after ramp, before pings start)`);
  console.log(`  Duration:          ${DURATION_S}s  (measurement window)`);
  if (TAG) console.log(`  Tag:               ${TAG}`);
  console.log(`  Expected messages: ~${expectedMessages}\n`);

  let triggerStop!: () => void;
  const stop = new Promise<void>((res) => { triggerStop = res; });

  const scriptStart = Date.now();
  const rampDelayMs = (RAMP_S * 1000) / VUS;

  // Stagger connection starts over RAMP_S seconds — prevents connection storm,
  // more closely matches real user behaviour
  const vus = Array.from({ length: VUS }, (_, i) =>
    new Promise<void>(r => setTimeout(r, i * rampDelayMs))
      .then(() => runVU(i + 1, stop, scriptStart))
  );

  await new Promise((resolve) => setTimeout(resolve, (RAMP_S + WARMUP_S + DURATION_S) * 1000));
  triggerStop();
  await Promise.all(vus);

  latencies.sort((a, b) => a - b);
  const avg = latencies.length ? latencies.reduce((a, b) => a + b, 0) / latencies.length : 0;
  const deliveryRate = pingsSent > 0 ? messagesReceived / (pingsSent * vusPerChannel) : 0;
  const throughput = messagesReceived / DURATION_S;
  const avgJoin = joinTimes.length ? joinTimes.reduce((a, b) => a + b, 0) / joinTimes.length : 0;

  console.log("Results");
  console.log(`  Connected:         ${connected} / ${VUS}`);
  console.log(`  Connect errors:    ${connectErrors}`);
  console.log(`  Pings sent:        ${pingsSent}`);
  console.log(`  Messages received: ${messagesReceived}  (expected ~${expectedMessages})`);
  console.log(`  Delivery rate:     ${(deliveryRate * 100).toFixed(1)}%`);
  console.log(`  Throughput:        ${throughput.toFixed(1)} msg/s`);
  console.log(`  Join time avg:     ${avgJoin.toFixed(0)}ms`);
  if (latencies.length) {
    console.log("  Latency (ms):");
    console.log(`    avg: ${avg.toFixed(3)}`);
    console.log(`    p50: ${percentile(latencies, 50).toFixed(3)}`);
    console.log(`    p95: ${percentile(latencies, 95).toFixed(3)}`);
    console.log(`    p99: ${percentile(latencies, 99).toFixed(3)}`);
    console.log(`    max: ${latencies[latencies.length - 1].toFixed(3)}`);
  } else {
    console.log("  Latency: no data");
  }

  const result = {
    timestamp: new Date().toISOString(),
    tag: TAG || null,
    config: { url: WS_URL, vus: VUS, channels: CHANNELS, vusPerChannel, duration: DURATION_S, warmup: WARMUP_S },
    results: {
      connected,
      connectErrors,
      pingsSent,
      messagesReceived,
      deliveryRate: parseFloat((deliveryRate * 100).toFixed(1)),
      throughputMsgPerSec: parseFloat(throughput.toFixed(1)),
      joinTimeAvgMs: parseFloat(avgJoin.toFixed(0)),
      latency: latencies.length ? {
        avg: parseFloat(avg.toFixed(3)),
        p50: parseFloat(percentile(latencies, 50).toFixed(3)),
        p95: parseFloat(percentile(latencies, 95).toFixed(3)),
        p99: parseFloat(percentile(latencies, 99).toFixed(3)),
        max: parseFloat(latencies[latencies.length - 1].toFixed(3)),
      } : null,
    },
  };

  const resultsFile = resolve(__dirname, "results.json");
  const existing = existsSync(resultsFile) ? JSON.parse(readFileSync(resultsFile, "utf-8")) : [];
  existing.push(result);
  writeFileSync(resultsFile, JSON.stringify(existing, null, 2));
  console.log(`\nSaved to results.json (${existing.length} total runs)`);
}

main().catch(console.error);
