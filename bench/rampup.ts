/**
 * Ramp-up benchmark — runs load_test.ts at increasing VU counts then generates report.
 *
 * Usage:
 *   npm run rampup -- --url wss://your-app.fly.dev
 *   npm run rampup -- --url wss://your-app.fly.dev --max-vus 10000
 *   npm run rampup -- --url wss://your-app.fly.dev --max-vus 10000 --channels 50
 */

import { execSync } from "child_process";
import { resolve } from "path";

function arg(flag: string, fallback: string): string {
  const idx = process.argv.indexOf(flag);
  return idx !== -1 ? (process.argv[idx + 1] ?? fallback) : fallback;
}

const url = arg("--url", "ws://localhost:4000");
const channels = arg("--channels", "10");
const duration = arg("--duration", "30");
const warmup = arg("--warmup", "3");
const maxVus = parseInt(arg("--max-vus", "5000"));

// VU levels: each step is roughly 5x the previous, matching Discord's scale story
const ALL_LEVELS = [100, 500, 1000, 2500, 5000, 10000, 25000];
const levels = ALL_LEVELS.filter(v => v <= maxVus);

const loadTest = resolve(__dirname, "load_test.ts");
const generateReport = resolve(__dirname, "generate_report.ts");

console.log("\nRamp-up Benchmark");
console.log(`  Target:   ${url}`);
console.log(`  Channels: ${channels}`);
console.log(`  Levels:   ${levels.join(" → ")} VUs`);
console.log(`  Duration: ${duration}s per level  (warmup: ${warmup}s)`);
console.log(`  Total:    ~${levels.length * (parseInt(warmup) + parseInt(duration))}s\n`);

for (const vus of levels) {
  const vusPerChannel = Math.floor(vus / parseInt(channels));
  console.log(`\n${"─".repeat(60)}`);
  console.log(`  ${vus} VUs  ·  ${channels} channels  ·  ~${vusPerChannel} per channel`);
  console.log("─".repeat(60));

  try {
    // ramp is auto-calculated in load_test.ts based on VU count — no need to pass it
    execSync(
      `tsx "${loadTest}" --url ${url} --vus ${vus} --duration ${duration} --warmup ${warmup} --channels ${channels} --tag "${vus}-vus"`,
      { stdio: "inherit" }
    );
  } catch {
    console.error(`\nRun at ${vus} VUs failed — stopping ramp-up.`);
    break;
  }
}

console.log(`\n${"─".repeat(60)}`);
console.log("Generating report...");
execSync(`tsx "${generateReport}"`, { stdio: "inherit" });
console.log("Open bench/report.html in a browser to view results.");
