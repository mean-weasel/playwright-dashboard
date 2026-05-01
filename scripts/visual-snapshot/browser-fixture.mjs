import { spawn } from "node:child_process";
import http from "node:http";
import path from "node:path";

import { json, waitFor } from "./process.mjs";

const visualPagePort = Number(process.env.VISUAL_SNAPSHOT_PAGE_PORT ?? 17332);
const visualDebugPort = Number(process.env.VISUAL_SNAPSHOT_CDP_PORT ?? 17333);

export async function startExpandedBrowserFixture(tmpRoot) {
  const server = await startVisualPageServer(visualPagePort);
  const pageURL = `http://127.0.0.1:${server.port}/`;
  const debugPort = visualDebugPort;
  const chromePath =
    process.env.CHROME_PATH ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

  const chromeProcess = spawn(chromePath, [
    `--user-data-dir=${path.join(tmpRoot, "chrome-profile")}`,
    `--remote-debugging-port=${debugPort}`,
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-background-networking",
    pageURL,
  ], { stdio: "ignore" });

  await waitFor(async () => {
    const pages = await json(`http://127.0.0.1:${debugPort}/json/list`).catch(() => []);
    return pages.some((page) => page.url === pageURL);
  }, "Chrome CDP page");

  return { chromeProcess, debugPort, server };
}

function startVisualPageServer(port) {
  return new Promise((resolve, reject) => {
    const server = http.createServer((request, response) => {
      response.writeHead(200, { "content-type": "text/html" });
      response.end(visualPage());
    });
    server.on("error", reject);
    server.listen(port, "127.0.0.1", () => {
      resolve({ port: server.address().port, close: () => server.close() });
    });
  });
}

function visualPage() {
  return `<!doctype html>
<html>
  <head>
    <title>Visual Expanded</title>
    <style>
      body {
        margin: 0;
        font: 16px -apple-system, BlinkMacSystemFont, sans-serif;
        background: #f8fafc;
        color: #172033;
      }
      main {
        min-height: 100vh;
        display: grid;
        place-items: center;
      }
      section {
        width: 760px;
        border: 1px solid #d9e2ec;
        background: white;
        padding: 48px;
      }
      h1 { margin: 0 0 16px; font-size: 42px; }
      p { margin: 0; color: #536171; font-size: 20px; }
    </style>
  </head>
  <body>
    <main>
      <section>
        <h1>Expanded Session Fixture</h1>
        <p>Stable browser content for visual snapshot artifacts.</p>
      </section>
    </main>
  </body>
</html>`;
}
