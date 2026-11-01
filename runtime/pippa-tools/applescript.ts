/**
 * `applescript`: Pippa's everyday way into the Mac's apps (Mail, Finder, Calendar, Notes, Reminders, Contacts, Safari,
 * Numbers, Pages, Music …), with the Automation permissions the person gave Pippa. It runs `osascript` outside the bash
 * sandbox (shell.ts keeps refusing app control there) and is the one place where scripts may drive apps.
 *
 * - Reading runs at once: list the inbox, read a note, look at Finder's selection, the front Safari tab.
 * - A script that changes something (make, set a property, move, delete, duplicate, save, mark, open …) runs only after
 *   the person's OK, one card per script, worded from the model's own `purpose`.
 * - Never, not even after an OK: sending (Mail, Messages), `do shell script` (it would leave the sandbox), emptying the
 *   Trash, keystrokes or clicks through System Events, and JavaScript in web pages.
 *
 * The classification is a guard against mistakes and hostile document text, not a parser: a script it cannot tell
 * apart counts as a change and is asked about. `help` returns short recipes per app as a tool result, so they cost
 * prompt tokens only when used (never in the fixed prefix).
 */
import { spawn } from "node:child_process";
import { actionPolicy } from "./pippa-policy.ts";

const OSASCRIPT = "/usr/bin/osascript";
const OUTPUT_LIMIT = 6000;

/** Never run, whatever the person answers. */
const FORBIDDEN: [RegExp, string][] = [
	[/\bsend\b/i, "Pippa never sends mail or messages. Create a draft with mcp__pippa__mail_draft instead."],
	[/\bdo\s+shell\s+script\b/i, "do shell script is not available here. Use bash for commands."],
	[/\bempty\b[^\n]*\btrash\b|\bempty\s+the\s+trash\b/i, "Pippa never empties the Trash."],
	[/\b(keystroke|key\s+code|click)\b/i, "Pippa does not type or click for the person. Use the app's own AppleScript commands."],
	[/\bdo\s+javascript\b/i, "Running JavaScript in web pages is not available."],
	[/\b(restart|shut\s+down|log\s+out)\b/i, "Pippa does not restart, shut down or log out the Mac."],
];

/** Verbs that change something in an app. */
const CHANGE_VERBS = /\b(make|move|delete|duplicate|save|close|quit|import|export|reply|forward|redirect|print|open|activate|launch|eject|mount|reveal|select|create|add|remove|rename|archive|bounce|play|pause|synchronize|check\s+for\s+new\s+mail)\b/i;
/** `set <property> of …`, `set <two words> to …` (a property such as `read status`), or a one-word property of an app object. */
const CHANGE_SET = /\bset\s+(?:the\s+)?(?:\w+\s+){0,2}\w+\s+of\b|\bset\s+(?:the\s+)?\w+\s+\w+\s+to\b|\bset\s+(?:the\s+)?(name|subject|content|body|flagged|completed|visible|bounds|location|summary|description|status|url|label|comment|index|selected|junk\s+mail\s+status|read\s+status|due\s+date|start\s+date|end\s+date|allday\s+event|priority|note|notes|title|value|formula)\s+to\b/i;

export type Verdict = { kind: "read" } | { kind: "change" } | { kind: "forbidden"; reason: string };

/** What a script does, judged from its text. Comments and string contents still count: unsure means "change". */
export function classify(script: string): Verdict {
	for (const [pattern, reason] of FORBIDDEN) if (pattern.test(script)) return { kind: "forbidden", reason };
	// Building a result in a local variable changes no app: `set end of out to …`, `set time of today to 0`.
	const local = script.replace(/\bset\s+(?:the\s+)?(end|beginning|rest|time|day|month|year|hours|minutes|seconds)\s+of\s+\w+\s+to\b/gi, "");
	if (CHANGE_VERBS.test(local) || CHANGE_SET.test(local)) return { kind: "change" };
	return { kind: "read" };
}

/** Apps a script talks to (`tell application "Mail"`), for the question card and the work line. */
export function appsOf(script: string): string[] {
	const names = [...script.matchAll(/\btell\s+application\s+(?:id\s+)?"([^"]+)"/gi)].map((m) => m[1].replace(/^com\.apple\./i, ""));
	return [...new Set(names)];
}

/** osascript's error, made actionable for the model. */
export function explain(stderr: string): string {
	const text = stderr.trim().split("\n").pop() ?? "";
	if (/-1743|Not authorized to send Apple events/i.test(text))
		return `${text}\nPippa has no Automation permission for this app. Tell the person to allow Pippa in System Settings › Privacy & Security › Automation; do not retry.`;
	if (/-600|isn.t running|Application isn.t running/i.test(text)) return `${text}\nThe app is not open. It opens when a script tells it to activate, or the person can open it.`;
	if (/-1728|Can.t get/i.test(text)) return `${text}\nThat object does not exist. Read first (for example a list of names) and use an exact name or index.`;
	if (/syntax error|-2741|-2740/i.test(text)) return `${text}\nThe script has a syntax error. Call applescript with help and the app name for working examples.`;
	return text || "The script failed without a message.";
}

export const HELP: Record<string, string> = {
	mail: `tell application "Mail"
  -- newest 10 in the inbox: subject, sender, date, read status
  set out to {}
  repeat with m in (messages 1 thru 10 of inbox)
    set end of out to (subject of m) & " | " & (sender of m) & " | " & ((date received of m) as string) & " | read: " & (read status of m)
  end repeat
  return out
end tell
-- whole text: content of (first message of inbox whose subject is "…")
-- mailboxes: name of every mailbox of account "…"
-- change (asks first): set read status of m to true · set flagged status of m to true · move m to mailbox "Archiv" of account "…"
-- attachments: use mcp__pippa__mail_read (it saves them as files for read_document)`,
	finder: `tell application "Finder"
  -- selection as paths
  set out to {}
  repeat with f in (selection as alias list)
    set end of out to POSIX path of f
  end repeat
  return out
end tell
-- names in a folder: name of every item of folder (POSIX file "/Users/…/Downloads" as alias)
-- prefer search_files, list_folder, move_files and move_to_trash for files`,
	calendar: `tell application "Calendar"
  set today to current date
  set time of today to 0
  set out to {}
  repeat with c in calendars
    repeat with e in (every event of c whose start date ≥ today and start date < today + 1 * days)
      set end of out to (summary of e) & " | " & ((start date of e) as string)
    end repeat
  end repeat
  return out
end tell
-- prefer mcp__pippa__calendar_read and calendar_add for appointments`,
	notes: `tell application "Notes"
  return name of notes 1 thru 20 of default account
end tell
-- text: plaintext of (first note whose name is "…")
-- new note (asks first): make new note at folder "Notes" of default account with properties {name:"…", body:"…"}`,
	reminders: `tell application "Reminders"
  return name of (reminders of default list whose completed is false)
end tell
-- prefer mcp__pippa__reminders_read and reminder_add`,
	contacts: `tell application "Contacts"
  set p to first person whose name contains "…"
  return {name of p, value of emails of p, value of phones of p}
end tell`,
	safari: `tell application "Safari"
  return {URL of current tab of front window, name of current tab of front window}
end tell
-- all tabs: name of every tab of front window · page text: prefer mcp__pippa__front_read`,
	numbers: `tell application "Numbers"
  tell table 1 of sheet 1 of front document
    return value of every cell of row 1
  end tell
end tell`,
};

function run(script: string, signal?: AbortSignal): Promise<{ ok: boolean; out: string; err: string }> {
	return new Promise((done) => {
		const child = spawn(OSASCRIPT, ["-"], { stdio: ["pipe", "pipe", "pipe"] });
		let out = "", err = "";
		const timer = setTimeout(() => child.kill("SIGKILL"), 60_000);
		const stop = () => child.kill("SIGKILL");
		signal?.addEventListener("abort", stop, { once: true });
		child.stdout.on("data", (d) => { if (out.length < OUTPUT_LIMIT * 2) out += d; });
		child.stderr.on("data", (d) => { if (err.length < 4000) err += d; });
		child.on("error", (e) => { clearTimeout(timer); done({ ok: false, out: "", err: String(e.message) }); });
		child.on("close", (code) => {
			clearTimeout(timer);
			signal?.removeEventListener("abort", stop);
			done({ ok: code === 0, out, err: code === null ? "The script took longer than 60 seconds and was stopped." : err });
		});
		child.stdin.end(script);
	});
}

function askText(apps: string[], purpose: string, language: string): { title: string; message: string } {
	const german = language.toLowerCase().startsWith("de");
	const where = apps.length ? apps.join(", ") : german ? "einer App" : "an app";
	return german
		? { title: `Darf Pippa etwas in ${where} ändern?`, message: purpose || "Pippa möchte etwas in einer App ändern." }
		: { title: `May Pippa change something in ${where}?`, message: purpose || "Pippa wants to change something in an app." };
}

export function applescriptTool(deps: { run?: typeof run; env?: Record<string, string | undefined> } = {}) {
	const runScript = deps.run ?? run;
	const env = deps.env ?? process.env;
	return {
		name: "applescript",
		label: "Mac-Apps",
		description: "AppleScript for Mac apps. Reads run; changes ask the person first. Never send. help=app name: examples.",
		// Plain JSON Schema (as tool-scope.mjs): no Pi import, so the tests load this file without a Pi payload.
		parameters: { type: "object", additionalProperties: false, properties: {
			script: { type: "string" },
			purpose: { type: "string", description: "Change in the person's words." },
			help: { type: "string" },
		} },
		annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
		executionMode: "sequential",
		async execute(_id: string, params: any, signal: AbortSignal | undefined, _onUpdate: unknown, ctx: any) {
			const text = (body: string, isError = false, details: Record<string, unknown> = {}) =>
				({ content: [{ type: "text", text: body }], isError, details });
			const help = String(params?.help ?? "").trim().toLowerCase();
			if (help) {
				const key = Object.keys(HELP).find((k) => help.includes(k));
				return text(key ? HELP[key] : `Examples exist for: ${Object.keys(HELP).join(", ")}.`, false, { pippaExecution: "not_dispatched" });
			}
			const script = String(params?.script ?? "").trim();
			if (!script) return text("Give script (AppleScript), or help with an app name.", true, { pippaExecution: "not_dispatched" });
			if (actionPolicy(env) === "draftOnly")
				return text("This task prepares draft text only. Read local context and answer; do not drive apps.", true, { pippaExecution: "not_dispatched" });
			const verdict = classify(script);
			if (verdict.kind === "forbidden") return text(`Not run: ${verdict.reason}`, true, { pippaExecution: "not_dispatched" });
			const apps = appsOf(script);
			if (verdict.kind === "change") {
				if (!ctx?.hasUI || !ctx?.ui?.confirm) return text("Not run: changing an app needs the person's OK, and no one can be asked here.", true, { pippaExecution: "not_dispatched" });
				const { title, message } = askText(apps, String(params?.purpose ?? "").trim(), env.PIPPA_LANGUAGE ?? "");
				if (!(await ctx.ui.confirm(title, message)))
					return text("Not run: the person said no. Do not try again in this answer, and do not work around it.", true, { pippaExecution: "not_dispatched" });
			}
			if (signal?.aborted) return text("Stopped before running the script.", true, { pippaExecution: "not_dispatched" });
			const result = await runScript(script, signal);
			const changed = verdict.kind === "change";
			if (!result.ok) return text(explain(result.err), true, { pippaExecution: changed ? "uncertain" : "attempted", apps, changed });
			const out = result.out.trim();
			const body = out.length > OUTPUT_LIMIT ? out.slice(0, OUTPUT_LIMIT) + "\n… (shortened: ask for less, for example fewer items)" : out;
			return text(body || (changed ? "Done; the app reported nothing back." : "The script returned nothing."), false,
				{ pippaExecution: "attempted", apps, changed });
		},
	};
}
