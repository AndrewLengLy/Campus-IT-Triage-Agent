/**
 * Record a self-contained HTML walkthrough page to a web-ready MP4.
 *
 *   node record_walkthrough.mjs <page.html> [-o out.mp4] [--seconds 180]
 *
 * The page is served over HTTP rather than opened as file:// so relative
 * assets and fetches behave the way they will in a browser. Recording stops
 * when the page sets its own completion flag:
 *
 *   document.body.dataset.demoComplete = "true"
 *
 * Waiting on that flag rather than a fixed duration is the difference between
 * a clean cut and a video that stops mid-scene on a slower machine.
 *
 * Requires: playwright, and ffmpeg on PATH. CHROMIUM_PATH and FFMPEG_PATH
 * override both so this runs against a preinstalled browser in CI.
 */

import { createServer } from "node:http";
import { readFile, rm, mkdtemp } from "node:fs/promises";
import { spawn } from "node:child_process";
import { tmpdir } from "node:os";
import { extname, join, dirname, basename, resolve } from "node:path";
import { chromium } from "playwright";

const TYPES = {
  ".html": "text/html", ".css": "text/css", ".js": "text/javascript",
  ".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg",
  ".webp": "image/webp", ".woff2": "font/woff2", ".mp4": "video/mp4",
};

const argv = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = argv.indexOf(name);
  return i === -1 ? fallback : argv[i + 1];
};
const pagePath = argv.find((a) => !a.startsWith("-") && a.endsWith(".html"));
if (!pagePath) {
  console.error("usage: node record_walkthrough.mjs <page.html> [-o out.mp4] [--seconds 180]");
  process.exit(2);
}

const page_ = resolve(pagePath);
const root = dirname(page_);
const out = resolve(flag("-o", page_.replace(/\.html$/, ".mp4")));
const budget = Number(flag("--seconds", 180)) * 1000;

// Serve the page's own directory; refuse paths that escape it.
const server = createServer(async (req, res) => {
  const rel = decodeURIComponent(new URL(req.url, "http://x").pathname);
  const file = rel === "/" ? basename(page_) : rel.replace(/^\//, "");
  const target = resolve(root, file);
  if (!target.startsWith(root)) return void res.writeHead(403).end();
  try {
    const body = await readFile(target);
    res.writeHead(200, { "Content-Type": TYPES[extname(target)] || "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404).end();
  }
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const { port } = server.address();

const tmp = await mkdtemp(join(tmpdir(), "walkthrough-"));
const browser = await chromium.launch({
  headless: true,
  executablePath: process.env.CHROMIUM_PATH || undefined,
});
const context = await browser.newContext({
  viewport: { width: 1920, height: 1080 },
  deviceScaleFactor: 1,
  recordVideo: { dir: tmp, size: { width: 1920, height: 1080 } },
});

let webm;
try {
  const page = await context.newPage();
  page.on("pageerror", (e) => console.error("page error:", e.message));
  await page.goto(`http://127.0.0.1:${port}/${basename(page_)}`, {
    waitUntil: "domcontentloaded",
  });
  await page.waitForSelector("body[data-demo-complete='true']", { timeout: budget });
  await page.waitForTimeout(800); // let the last frame settle before cutting
  const video = page.video();
  await context.close(); // flushes the webm; path() is only valid after this
  webm = await video.path();
} finally {
  await browser.close();
  server.close();
}

// Playwright records VP8/WebM. LinkedIn, GitHub, and QuickTime all want H.264.
// -movflags +faststart puts the moov atom ahead of mdat so the file streams
// instead of downloading in full before the first frame renders.
const args = [
  "-y", "-loglevel", "error",
  "-i", webm,
  "-c:v", "libx264",
  "-preset", "slow",
  "-crf", "20",
  "-pix_fmt", "yuv420p",
  "-profile:v", "high",
  "-r", "25",
  "-movflags", "+faststart",
  "-an",
  out,
];
await new Promise((res, rej) => {
  const p = spawn(process.env.FFMPEG_PATH || "ffmpeg", args, {
    stdio: ["ignore", "inherit", "inherit"],
  });
  p.on("error", (e) =>
    rej(new Error(e.code === "ENOENT" ? "ffmpeg not found; set FFMPEG_PATH" : e.message)));
  p.on("close", (c) => (c === 0 ? res() : rej(new Error(`ffmpeg exited ${c}`))));
});
await rm(tmp, { recursive: true, force: true });

console.log(out);
console.log("verify:  ffprobe -v error -show_entries format=duration,bit_rate " +
            "-show_entries stream=width,height,nb_frames,codec_name " + out);
