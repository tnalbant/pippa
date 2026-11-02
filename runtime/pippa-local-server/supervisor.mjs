// Detached keeper of an oMLX server started from the terminal (ensure.mjs spawns it, then it outlives Pi).
//
//   node supervisor.mjs <pippa-local-server.json> <local-server.lock>
//
// 1. Takes the lock (O_EXCL). Someone else holds it (the app, another terminal Pi): exit 0, the caller waits for /health.
// 2. Starts the server with exactly the binary, arguments and environment Pippa wrote; output to the shared log.
// 3. Writes the server's pid into the lock, so the app sees a live server and uses it.
// 4. Server gone for any reason: remove the lock (only if it is still ours) and exit. SIGTERM here stops the server.
// 5. Nothing written to the shared log for `idleStopSeconds` (default 30 min): stop the server. oMLX unloads the
//    model after its own idle timeout (settings.json) and logs every request, so a quiet log means nobody uses it,
//    neither the terminal nor the app; the next request starts a new one.
import { spawn } from "node:child_process";
import { mkdirSync, openSync, statSync, writeSync } from "node:fs";
import { dirname } from "node:path";
import { createLock, loadConfig, removeLockIf, serverEnvironment, sleep, writeLock } from "./common.mjs";

const [configFile, lockFile] = process.argv.slice(2);
if (!configFile || !lockFile) {
	console.error("usage: supervisor.mjs <config> <lock>");
	process.exit(2);
}

const config = loadConfig(configFile);
const lock = { owner: "pi", holder: process.pid, pid: null, port: config.port, startedAt: new Date().toISOString() };
if (!createLock(lockFile, lock)) process.exit(0);

let child;
let stopping = false;
let logFd;

function log(line) {
	try {
		if (logFd !== undefined) writeSync(logFd, `[pippa-local-server] ${new Date().toISOString()} ${line}\n`);
	} catch {}
}

function finish(code) {
	removeLockIf(lockFile, (current) => current.holder === process.pid);
	process.exit(code);
}

const running = () => child && child.exitCode === null && child.signalCode === null;

async function stopServer(reason) {
	if (stopping) return;
	stopping = true;
	log(`stopping the server (${reason})`);
	if (running()) {
		child.kill("SIGTERM");
		for (let i = 0; i < 30 && running(); i++) await sleep(100);
		if (running()) child.kill("SIGKILL");
	}
	finish(0);
}

try {
	mkdirSync(dirname(config.logFile), { recursive: true });
	logFd = openSync(config.logFile, "a", 0o600);
	log(`starting ${config.binary} on 127.0.0.1:${config.port} for the terminal`);
	child = spawn(config.binary, config.arguments, {
		stdio: ["ignore", logFd, logFd],
		env: serverEnvironment(config),
		cwd: config.basePath ?? dirname(config.logFile),
	});
	await new Promise((resolve, reject) => {
		child.once("spawn", resolve);
		child.once("error", reject);
	});
} catch (error) {
	log(`cannot start: ${error.message}`);
	finish(1);
}

writeLock(lockFile, { ...lock, pid: child.pid });
child.on("exit", (code, signal) => {
	if (!stopping) log(`server exited (${signal ?? code})`);
	finish(0);
});
for (const signal of ["SIGTERM", "SIGINT", "SIGHUP"]) process.on(signal, () => stopServer(signal));

const idleMs = config.idleStopSeconds * 1000;
setInterval(() => {
	let last;
	try {
		last = statSync(config.logFile).mtimeMs;
	} catch {
		return;
	}
	if (Date.now() - last > idleMs) stopServer(`idle for ${config.idleStopSeconds} s`);
}, Math.min(60_000, Math.max(250, idleMs / 4)));
