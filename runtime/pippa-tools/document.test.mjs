// `read` with documents as text in the same call (document.ts): real PDFKit and textutil on macOS, Pi's own read and
// Pippa's MCP reader as stand-ins.
//
//   node --experimental-strip-types --test runtime/pippa-tools/document.test.mjs
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { documentKind, lines, readTool, DOCUMENT_READER } from "./document.ts";

/** A small, valid PDF with one line of text per page (Helvetica, no fonts embedded). */
function pdf(pages) {
	const objects = ["<< /Type /Catalog /Pages 2 0 R >>", ""];
	const kids = [];
	for (const text of pages) {
		const stream = text ? `BT /F1 18 Tf 72 720 Td (${text}) Tj ET` : "";
		objects.push(`<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`);
		const content = objects.length;
		objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents ${content} 0 R /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> >>`);
		kids.push(`${objects.length} 0 R`);
	}
	objects[1] = `<< /Type /Pages /Kids [${kids.join(" ")}] /Count ${pages.length} >>`;
	let body = "%PDF-1.4\n";
	const offsets = objects.map((object, i) => { const at = body.length; body += `${i + 1} 0 obj\n${object}\nendobj\n`; return at; });
	const xref = body.length;
	body += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n${offsets.map((o) => `${String(o).padStart(10, "0")} 00000 n \n`).join("")}`;
	return body + `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
}

const builtin = { name: "read", description: "Pi's read", execute: async (_id, params) => ({ content: [{ type: "text", text: `pi read ${params.path}` }], details: { pi: true } }) };
const tool = readTool(() => builtin).definition("/");

test("kinds: PDF and Office text locally, spreadsheets and slides through the app, text files stay with Pi", () => {
	assert.equal(documentKind("/x/Rechnung.PDF"), "pdf");
	assert.equal(documentKind("Brief.docx"), "textutil");
	assert.equal(documentKind("a.rtf"), "textutil");
	assert.equal(documentKind("a.odt"), "textutil");
	assert.equal(documentKind("Budget.xlsx"), "app");
	assert.equal(documentKind("Scan.HEIC"), "image");
	assert.equal(documentKind("notizen.md"), undefined);
	assert.equal(documentKind("termine.txt"), undefined);
	assert.equal(lines("a\nb\nc\nd", 2, 2), "b\nc");
	assert.equal(lines("a\nb", undefined, undefined), "a\nb");
	assert.throws(() => lines("a\nb", 5), /beyond the end/);
});

test("read returns a PDF's text with page markers, and a Word or RTF file's text, in the same call", { skip: process.platform !== "darwin" && "macOS only" }, async () => {
	const dir = await mkdtemp(join(tmpdir(), "pippa-read-"));
	try {
		await writeFile(join(dir, "Rechnung.pdf"), pdf(["Rechnung Nr 42 Betrag 84,20 EUR", "Zahlbar bis 31.10.2026"]));
		const result = await tool.execute("r1", { path: "Rechnung.pdf" }, undefined, undefined, { cwd: dir });
		const text = result.content[0].text;
		assert.match(text, /^\[Page 1\]\nRechnung Nr 42 Betrag 84,20 EUR/);
		assert.match(text, /\[Page 2\]\nZahlbar bis 31\.10\.2026/);
		assert.deepEqual(result.details, { pippaDocument: { path: join(dir, "Rechnung.pdf"), via: "pdfkit" } });
		const part = await tool.execute("r2", { path: join(dir, "Rechnung.pdf"), offset: 4, limit: 2 }, undefined, undefined, { cwd: "/" });
		assert.equal(part.content[0].text, "[Page 2]\nZahlbar bis 31.10.2026");
		await writeFile(join(dir, "Brief.txt"), "Sehr geehrte Frau Kraus,\nder Termin steht.\n");
		execFileSync("/usr/bin/textutil", ["-convert", "docx", join(dir, "Brief.txt"), "-output", join(dir, "Brief.docx")]);
		execFileSync("/usr/bin/textutil", ["-convert", "rtf", join(dir, "Brief.txt"), "-output", join(dir, "Brief.rtf")]);
		for (const name of ["Brief.docx", "Brief.rtf"]) {
			const doc = await tool.execute("r3", { path: name }, undefined, undefined, { cwd: dir });
			assert.match(doc.content[0].text, /Sehr geehrte Frau Kraus,\nder Termin steht\./, name);
			assert.equal(doc.details.pippaDocument.via, "textutil");
		}
		await writeFile(join(dir, "kaputt.pdf"), "not a pdf");
		await assert.rejects(tool.execute("r4", { path: "kaputt.pdf" }, undefined, undefined, { cwd: dir }), /not a readable PDF/);
	} finally { await rm(dir, { recursive: true, force: true }); }
});

test("no text layer or no local reader: Pippa's MCP reader in a nested call, or a plain error without the app", async () => {
	const calls = [];
	const app = (outcome) => ({ cwd: "/d", tools: [{ name: DOCUMENT_READER }],
		executeTool: async (name, args) => { calls.push([name, args]); return outcome; } });
	const ok = { isError: false, result: { content: [{ type: "text", text: "[S. 1] Scan text" }] } };
	const scan = readTool(() => builtin, async () => "[Page 1]\n\n[Page 2]\n").definition("/");
	const result = await scan.execute("s1", { path: "Scan.pdf" }, undefined, undefined, app(ok));
	assert.deepEqual(result.content, ok.result.content);
	assert.deepEqual(calls.at(-1), [DOCUMENT_READER, { path: "/d/Scan.pdf" }]);
	assert.equal(result.details.pippaDocument.via, DOCUMENT_READER);
	await scan.execute("s2", { path: "/d/Budget.xlsx" }, undefined, undefined, app(ok));
	assert.deepEqual(calls.at(-1), [DOCUMENT_READER, { path: "/d/Budget.xlsx" }]);
	const failed = { isError: true, result: { content: [{ type: "text", text: "Datei nicht gefunden" }] } };
	await assert.rejects(scan.execute("s3", { path: "/d/Budget.xlsx" }, undefined, undefined, app(failed)), /Datei nicht gefunden/);
	await assert.rejects(scan.execute("s4", { path: "/d/Budget.xlsx" }, undefined, undefined, { cwd: "/d", tools: [] }), /only be read to text inside the Pippa app/);
	await assert.rejects(scan.execute("s5", { path: "/d/Scan.pdf" }, undefined, undefined, { cwd: "/d" }), /no text layer/);
});

test("images: Pi's read when the model sees images, otherwise text recognition in the app; text files stay with Pi", async () => {
	let used = 0;
	const ctx = (input) => ({ cwd: "/d", model: { input }, tools: [{ name: DOCUMENT_READER }],
		executeTool: async () => { used++; return { isError: false, result: { content: [{ type: "text", text: "OCR" }] } }; } });
	assert.deepEqual((await tool.execute("i1", { path: "Foto.jpg" }, undefined, undefined, ctx(["text", "image"]))).details, { pi: true });
	assert.equal((await tool.execute("i2", { path: "Foto.jpg" }, undefined, undefined, ctx(["text"]))).content[0].text, "OCR");
	assert.equal(used, 1);
	assert.deepEqual((await tool.execute("i3", { path: "Foto.jpg" }, undefined, undefined, { cwd: "/d", model: { input: ["text"] } })).details, { pi: true },
		"without the app Pi's read still answers");
	assert.deepEqual((await tool.execute("t1", { path: "notizen.md" }, undefined, undefined, ctx(["text"]))).details, { pi: true });
	assert.equal(used, 1);
});
