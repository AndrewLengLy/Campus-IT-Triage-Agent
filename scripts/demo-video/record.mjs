import { createServer } from "node:http";
import { readFile, rm } from "node:fs/promises";
import { spawn } from "node:child_process";
import { extname, join } from "node:path";
import { chromium } from "playwright";

const root = join(import.meta.dirname, "../../docs/demo");
const out = join(root, "campus-it-app-recording.mp4");
const types = {
  ".html": "text/html",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".mp4": "video/mp4",
};

const server = createServer(async (req, res) => {
  const file = req.url === "/" ? "/app-walkthrough.html" : req.url;
  try {
    const body = await readFile(join(root, decodeURIComponent(file)));
    res.writeHead(200, { "Content-Type": types[extname(file)] || "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end();
  }
});

await new Promise((resolve) => server.listen(8765, resolve));

// CHROMIUM_PATH lets CI / sandboxes point at a preinstalled browser.
const browser = await chromium.launch({
  headless: true,
  executablePath: process.env.CHROMIUM_PATH || undefined,
});
const context = await browser.newContext({
  viewport: { width: 1920, height: 1080 },
  deviceScaleFactor: 1,
  recordVideo: {
    dir: join(root, "recordings"),
    size: { width: 1920, height: 1080 },
  },
});
const page = await context.newPage();
await page.goto("http://127.0.0.1:8765/app-walkthrough.html", { waitUntil: "domcontentloaded" });
await page.waitForSelector("body[data-demo-complete='true']", { timeout: 180000 });
await page.waitForTimeout(800);
const video = page.video();
await context.close();
const webm = await video.path();
await browser.close();
server.close();

// Playwright records VP8/WebM. LinkedIn, GitHub, and QuickTime all want H.264 MP4.
// -movflags +faststart puts the moov atom first so the file streams instead of
// having to download in full before the first frame renders.
const ffmpeg = process.env.FFMPEG_PATH || "ffmpeg";
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
await new Promise((resolve, reject) => {
  const p = spawn(ffmpeg, args, { stdio: ["ignore", "inherit", "inherit"] });
  p.on("error", reject);
  p.on("close", (code) => (code === 0 ? resolve() : reject(new Error("ffmpeg exited " + code))));
});
await rm(join(root, "recordings"), { recursive: true, force: true });
console.log(out);
