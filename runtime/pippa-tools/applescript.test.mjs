import assert from "node:assert/strict";
import { test } from "node:test";
import { appsOf, applescriptTool, classify, explain, HELP } from "./applescript.ts";

const textOf = (r) => r.content.map((c) => c.text).join("");

test("reads run at once: inbox list, note text, Finder selection, the help recipes themselves", () => {
	for (const script of [
		'tell application "Mail" to return subject of messages 1 thru 5 of inbox',
		'tell application "Notes" to return plaintext of (first note whose name is "Einkauf")',
		HELP.mail.split("\n-- ")[0], HELP.finder.split("\n-- ")[0], HELP.calendar.split("\n-- ")[0],
	]) assert.deepEqual(classify(script), { kind: "read" }, script);
});

test("changes ask first: properties, moving, making, deleting", () => {
	for (const script of [
		'tell application "Mail" to set read status of (first message of inbox) to true',
		'tell application "Mail" to move (first message of inbox) to mailbox "Archiv" of account "iCloud"',
		'tell application "Notes" to make new note with properties {name:"x", body:"y"}',
		'tell application "Finder" to delete (POSIX file "/tmp/x" as alias)',
		'tell application "Mail"\n tell (first message of inbox) to set flagged status to true\nend tell',
	]) assert.deepEqual(classify(script), { kind: "change" }, script);
});

test("never: sending, shell, emptying the Trash, typing or clicking, page JavaScript", () => {
	for (const script of [
		'tell application "Mail" to send (first outgoing message)',
		'do shell script "rm -rf ~"',
		'tell application "Finder" to empty the trash',
		'tell application "System Events" to keystroke "a"',
		'tell application "Safari" to do JavaScript "1" in front document',
	]) assert.equal(classify(script).kind, "forbidden", script);
});

test("apps named for the card, errors made actionable", () => {
	assert.deepEqual(appsOf('tell application "Mail"\n tell application id "com.apple.Notes"\n end tell\nend tell'), ["Mail", "Notes"]);
	assert.match(explain("execution error: Not authorized to send Apple events to Mail. (-1743)"), /System Settings › Privacy & Security › Automation/);
	assert.match(explain("execution error: Can’t get mailbox \"X\". (-1728)"), /exact name/);
});

test("a change runs only after the person's OK; a no stops it; a read never asks; help costs no run", async () => {
	const ran = [];
	const tool = applescriptTool({ run: async (script) => { ran.push(script); return { ok: true, out: "ok", err: "" }; }, env: {} });
	const asked = [];
	const ctx = (answer) => ({ hasUI: true, ui: { confirm: async (title, message) => { asked.push([title, message]); return answer; } } });
	const change = 'tell application "Mail" to set read status of (first message of inbox) to true';
	const declined = await tool.execute("1", { script: change, purpose: "Mark the newest mail as read." }, undefined, undefined, ctx(false));
	assert.equal(declined.isError, true);
	assert.equal(ran.length, 0);
	assert.deepEqual(asked[0], ["May Pippa change something in Mail?", "Mark the newest mail as read."]);
	const approved = await tool.execute("2", { script: change, purpose: "x" }, undefined, undefined, ctx(true));
	assert.equal(approved.isError, false);
	assert.equal(approved.details.changed, true);
	const read = await tool.execute("3", { script: 'tell application "Mail" to return name of every mailbox' }, undefined, undefined, ctx(false));
	assert.equal(read.isError, false);
	assert.equal(asked.length, 2, "a read is never asked about");
	const help = await tool.execute("4", { help: "Mail" }, undefined, undefined, ctx(false));
	assert.match(textOf(help), /messages 1 thru 10 of inbox/);
	assert.equal(ran.length, 2);
});

test("without anyone to ask, in draft-only tasks, and for forbidden scripts nothing runs", async () => {
	const ran = [];
	const run = async (script) => { ran.push(script); return { ok: true, out: "", err: "" }; };
	const change = 'tell application "Notes" to make new note';
	assert.equal((await applescriptTool({ run, env: {} }).execute("1", { script: change }, undefined, undefined, {})).isError, true);
	const draft = applescriptTool({ run, env: { PIPPA_ACTION_POLICY: "draftOnly" } });
	assert.equal((await draft.execute("2", { script: 'tell application "Mail" to return 1' }, undefined, undefined, {})).isError, true);
	const sent = await applescriptTool({ run, env: {} }).execute("3", { script: 'tell application "Mail" to send m' }, undefined, undefined,
		{ hasUI: true, ui: { confirm: async () => true } });
	assert.match(textOf(sent), /never sends/);
	assert.equal(ran.length, 0);
});
