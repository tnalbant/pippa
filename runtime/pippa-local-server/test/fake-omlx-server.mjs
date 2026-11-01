// Stand-in for oMLX (no model, no Python): started as `<python3> -c … serve --base-path <dir> --headless`, it reads host,
// port and key from <dir>/settings.json like oMLX does and serves on them. With a key, every request needs `Bearer <key>`:
// /health (503 for $FAKE_OMLX_LOAD_MS, then 200), /v1/models (the folders in <dir>/models), and a one-word streamed
// /v1/chat/completions for a real `pi -p`. Each start appends {args, env, pid} to $FAKE_OMLX_LOG.
import { appendFileSync, readdirSync, readFileSync } from "node:fs";
import { createServer } from "node:http";
import { join } from "node:path";

const args = process.argv.slice(2);
const base = args[args.indexOf("--base-path") + 1];
const settings = JSON.parse(readFileSync(join(base, "settings.json"), "utf8"));
const key = settings.auth?.api_key ?? "";
if (process.env.FAKE_OMLX_LOG) {
	appendFileSync(process.env.FAKE_OMLX_LOG, JSON.stringify({ args, env: process.env, cwd: process.cwd(), pid: process.pid }) + "\n");
}
const readyAt = Date.now() + (Number(process.env.FAKE_OMLX_LOAD_MS) || 300);
const json = (res, status, body) => res.writeHead(status, { "Content-Type": "application/json" }).end(JSON.stringify(body));

createServer((req, res) => {
	if (key && req.headers.authorization !== `Bearer ${key}`) return json(res, 401, { error: "unauthorized" });
	if (req.url === "/health") {
		const ready = Date.now() >= readyAt;
		return json(res, ready ? 200 : 503, ready ? { status: "healthy" } : { status: "starting" });
	}
	if (req.url === "/v1/models") {
		let ids = [];
		try {
			ids = readdirSync(join(base, "models"), { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name);
		} catch {}
		return json(res, 200, { object: "list", data: ids.map((id) => ({ id, object: "model", owned_by: "omlx" })) });
	}
	if (req.method === "POST" && req.url === "/v1/chat/completions") {
		req.resume();
		req.on("end", () => {
			res.writeHead(200, { "Content-Type": "text/event-stream" });
			const chunk = (delta, finish = null) =>
				`data: ${JSON.stringify({ id: "x", object: "chat.completion.chunk", created: 0, model: "fake", choices: [{ index: 0, delta, finish_reason: finish }] })}\n\n`;
			res.end(chunk({ role: "assistant", content: "pong" }) + chunk({}, "stop") + "data: [DONE]\n\n");
		});
		return;
	}
	json(res, 404, { error: "not found" });
}).listen(settings.server.port, settings.server.host);
process.on("SIGTERM", () => process.exit(0));
