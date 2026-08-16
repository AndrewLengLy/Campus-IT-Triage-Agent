import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join } from "node:path";
import { chromium } from "playwright";

const root = join(import.meta.dirname, "../../docs/demo");
const types = { ".html": "text/html", ".svg": "image/svg+xml", ".mp4": "video/mp4" };

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

const browser = await chromium.launch({ headless: true });
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
await page.waitForSelector("body[data-demo-complete='true']", { timeout: 120000 });
await page.waitForTimeout(800);
const video = page.video();
await context.close();
const videoPath = await video.path();
await browser.close();
server.close();
console.log(videoPath);
