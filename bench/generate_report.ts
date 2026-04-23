import { readFileSync, writeFileSync } from "fs";
import { resolve } from "path";

const resultsFile = resolve(__dirname, "results.json");
const results = JSON.parse(readFileSync(resultsFile, "utf-8")) as Run[];

interface Run {
  timestamp: string;
  tag: string | null;
  config: { url: string; vus: number; duration: number; warmup: number };
  results: {
    connected: number;
    connectErrors: number;
    pingsSent: number;
    messagesReceived: number;
    deliveryRate: number;
    throughputMsgPerSec: number;
    joinTimeAvgMs: number;
    latency: { avg: number; p50: number; p95: number; p99: number; max: number } | null;
  };
}

const sorted = [...results].sort((a, b) => a.config.vus - b.config.vus);
const labels = sorted.map(r => `${r.tag ? r.tag + " / " : ""}${r.config.vus} VUs`);
const p50 = sorted.map(r => r.results.latency?.p50 ?? 0);
const p95 = sorted.map(r => r.results.latency?.p95 ?? 0);
const p99 = sorted.map(r => r.results.latency?.p99 ?? 0);
const delivery = sorted.map(r => r.results.deliveryRate);
const throughput = sorted.map(r => r.results.throughputMsgPerSec);

// Discord reference lines (from public engineering blog posts)
// 11M concurrent users, ~26k events/sec across cluster (2020)
// Their p50 latency is described as "milliseconds" — no exact public number
const discordNotes = [
  "Discord (2020): 11M concurrent users, ~26k events/sec across Elixir cluster",
  "Discord (2022): 19M peak concurrent users, 4B messages/day",
  "Discord largest server (Midjourney): 16M+ members, 2M concurrent online",
];

const tableRows = sorted.map(r => `
  <tr>
    <td>${new Date(r.timestamp).toLocaleString()}</td>
    <td>${r.tag ?? "—"}</td>
    <td>${r.config.vus}</td>
    <td>${r.config.duration}s</td>
    <td>${r.results.connected} / ${r.config.vus}</td>
    <td>${r.results.connectErrors}</td>
    <td>${r.results.deliveryRate}%</td>
    <td>${r.results.throughputMsgPerSec}</td>
    <td>${r.results.joinTimeAvgMs}ms</td>
    <td>${r.results.latency?.p50 ?? "—"}</td>
    <td>${r.results.latency?.p95 ?? "—"}</td>
    <td>${r.results.latency?.p99 ?? "—"}</td>
  </tr>`).join("");

const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>Phoenix Channel Benchmark</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 1100px; margin: 40px auto; padding: 0 20px; background: #0f1117; color: #e0e0e0; }
    h1 { color: #7c83f7; }
    h2 { color: #a0a8ff; margin-top: 40px; font-size: 1rem; text-transform: uppercase; letter-spacing: 0.1em; }
    .charts { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; margin: 24px 0; }
    .chart-box { background: #1a1d2e; border-radius: 8px; padding: 20px; }
    canvas { max-height: 260px; }
    table { width: 100%; border-collapse: collapse; font-size: 0.85rem; margin-top: 16px; }
    th { text-align: left; padding: 8px 12px; background: #1a1d2e; color: #7c83f7; }
    td { padding: 8px 12px; border-bottom: 1px solid #2a2d3e; }
    tr:hover td { background: #1e2130; }
    .note { background: #1a1d2e; border-left: 3px solid #7c83f7; padding: 12px 16px; margin: 8px 0; font-size: 0.85rem; color: #a0a8ff; border-radius: 0 6px 6px 0; }
  </style>
</head>
<body>
  <h1>Phoenix Channel Fan-out Benchmark</h1>

  <h2>Discord Reference</h2>
  ${discordNotes.map(n => `<div class="note">${n}</div>`).join("")}

  <h2>Latency vs Concurrent Users</h2>
  <div class="charts">
    <div class="chart-box">
      <canvas id="latencyChart"></canvas>
    </div>
    <div class="chart-box">
      <canvas id="deliveryChart"></canvas>
    </div>
    <div class="chart-box">
      <canvas id="throughputChart"></canvas>
    </div>
  </div>

  <h2>All Runs</h2>
  <table>
    <thead>
      <tr>
        <th>Time</th><th>Tag</th><th>VUs</th><th>Duration</th>
        <th>Connected</th><th>Errors</th><th>Delivery</th><th>Msg/s</th>
        <th>Join avg</th><th>p50 (ms)</th><th>p95 (ms)</th><th>p99 (ms)</th>
      </tr>
    </thead>
    <tbody>${tableRows}</tbody>
  </table>

  <script>
    const labels = ${JSON.stringify(labels)};
    const color = (hex, a) => hex + Math.round(a * 255).toString(16).padStart(2, "0");

    new Chart(document.getElementById("latencyChart"), {
      type: "line",
      data: {
        labels,
        datasets: [
          { label: "p50", data: ${JSON.stringify(p50)}, borderColor: "#7c83f7", tension: 0.3, fill: false },
          { label: "p95", data: ${JSON.stringify(p95)}, borderColor: "#f7a27c", tension: 0.3, fill: false },
          { label: "p99", data: ${JSON.stringify(p99)}, borderColor: "#f77c7c", tension: 0.3, fill: false },
        ],
      },
      options: { plugins: { title: { display: true, text: "Fan-out Latency (ms)", color: "#e0e0e0" } }, scales: { y: { title: { display: true, text: "ms" } } } },
    });

    new Chart(document.getElementById("deliveryChart"), {
      type: "line",
      data: {
        labels,
        datasets: [{ label: "Delivery Rate %", data: ${JSON.stringify(delivery)}, borderColor: "#7cf7a2", tension: 0.3, fill: false }],
      },
      options: {
        plugins: { title: { display: true, text: "Message Delivery Rate (%)", color: "#e0e0e0" } },
        scales: { y: { min: 0, max: 100, title: { display: true, text: "%" } } },
      },
    });

    new Chart(document.getElementById("throughputChart"), {
      type: "bar",
      data: {
        labels,
        datasets: [{ label: "msg/s", data: ${JSON.stringify(throughput)}, backgroundColor: "#7c83f744" , borderColor: "#7c83f7", borderWidth: 1 }],
      },
      options: { plugins: { title: { display: true, text: "Throughput (messages/sec)", color: "#e0e0e0" } } },
    });
  </script>
</body>
</html>`;

const reportFile = resolve(__dirname, "report.html");
writeFileSync(reportFile, html);
console.log(`Report written to bench/report.html`);
