#!/usr/bin/env bun
// Dev server for the fetch demo.
//
//   1. packs sample/game/ into sample/game.love
//   2. builds the web bundle into sample/dist/ with the love.js CLI
//   3. serves dist/ with the COOP/COEP headers (needed by the release engine)
//      and the /api endpoints the game calls
//
//   bun run sample              # release engine (SharedArrayBuffer / pthreads)
//   bun run sample --compat     # compatibility engine, works everywhere
//   bun run sample --port 8080
//   bun run sample --no-build   # skip packing + building, just serve dist/

import { spawnSync } from "node:child_process";
import { existsSync, rmSync } from "node:fs";
import { join } from "node:path";
import { packLove } from "./zip.ts";

const root = import.meta.dir;
const cliArgs = process.argv.slice(2);
const compat = cliArgs.includes("--compat");
const noBuild = cliArgs.includes("--no-build");
const portIndex = cliArgs.indexOf("--port");
const port = portIndex >= 0 ? Number(cliArgs[portIndex + 1]) : Number(process.env.PORT ?? 8080);

const repoRoot = join(root, "..");
const gameDir = join(root, "game");
const loveFile = join(root, "game.love");
const distDir = join(root, "dist");
const title = "love.js fetch demo";

if (!noBuild) {
	const packed = packLove(gameDir, loveFile);
	console.log(`packed ${packed.files} files -> sample/game.love (${packed.size} bytes)`);

	rmSync(distDir, { recursive: true, force: true });

	const buildArgs = [join(repoRoot, "index.js"), loveFile, distDir, "-t", title];
	if (compat) buildArgs.push("-c");

	const result = spawnSync(process.execPath, buildArgs, { cwd: repoRoot, stdio: "inherit" });
	if (result.status !== 0) {
		console.error("love.js build failed");
		process.exit(result.status ?? 1);
	}
}

if (!existsSync(join(distDir, "index.html"))) {
	console.error(`missing ${distDir}/index.html — run without --no-build first`);
	process.exit(1);
}

const SECURITY_HEADERS: Record<string, string> = {
	"Cross-Origin-Opener-Policy": "same-origin",
	"Cross-Origin-Embedder-Policy": "require-corp",
	"Cross-Origin-Resource-Policy": "same-origin",
	"Cache-Control": "no-store",
};

const QUOTES = [
	"fetch() is just XHR with better PR.",
	"async/await is a coroutine with a marketing budget.",
	"There is no place like 127.0.0.1.",
	"LÖVE is all you need.",
	"HTTP 500: it's not a bug, it's a demonstration.",
	"A .love file is a zip file wearing a costume.",
];

let counter = 0;

function json(data: unknown, status = 200): Response {
	return new Response(`${JSON.stringify(data, null, 2)}\n`, {
		status,
		headers: {
			"Content-Type": "application/json; charset=utf-8",
			...SECURITY_HEADERS,
		},
	});
}

async function api(request: Request, url: URL): Promise<Response> {
	switch (url.pathname) {
		case "/api/random": {
			counter += 1;
			return json({
				request: counter,
				quote: QUOTES[Math.floor(Math.random() * QUOTES.length)],
				random: Math.random().toFixed(6),
				serverTime: new Date().toISOString(),
			});
		}
		case "/api/time":
			return json({ serverTime: new Date().toISOString() });
		case "/api/echo":
			return json({
				method: request.method,
				body: await request.text(),
				receivedAt: new Date().toISOString(),
			});
		case "/api/fail":
			return json(
				{
					error: "intentional failure",
					hint: "non-2xx responses reach onError, with the real status",
				},
				500,
			);
		default:
			return json({ error: "unknown endpoint", path: url.pathname }, 404);
	}
}

async function serveStatic(pathname: string): Promise<Response> {
	let rel = decodeURIComponent(pathname);
	if (rel.endsWith("/")) {
		rel += "index.html";
	}

	const full = join(distDir, rel);
	if (full !== distDir && !full.startsWith(`${distDir}\\`) && !full.startsWith(`${distDir}/`)) {
		return new Response("forbidden\n", { status: 403, headers: SECURITY_HEADERS });
	}

	const file = Bun.file(full);
	if (!(await file.exists())) {
		return new Response("not found\n", { status: 404, headers: SECURITY_HEADERS });
	}

	return new Response(file, {
		headers: {
			"Content-Type": file.type || "application/octet-stream",
			...SECURITY_HEADERS,
		},
	});
}

const server = Bun.serve({
	port,
	async fetch(request) {
		const url = new URL(request.url);
		if (url.pathname.startsWith("/api/")) {
			return api(request, url);
		}
		return serveStatic(url.pathname);
	},
});

console.log("");
console.log(`love.js fetch demo → http://localhost:${server.port}`);
console.log(`  engine:  ${compat ? "compat" : "release"} ${compat ? "" : "(needs the COOP/COEP headers this server sends)"}`);
console.log(`  api:     http://localhost:${server.port}/api/random`);
console.log("");
console.log("  desktop: LOVEJS_DEMO_API=http://localhost:%d lovec sample/game", server.port);
console.log("");
