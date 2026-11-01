import Foundation

/// A mail as files Pippa can read: the message as .eml and each real attachment as its own file, in Pippa's cache (never
/// next to a person's own file). Signature logos and icons shown inside the text are left out. `InboxCleanup` removes
/// the folders after 30 days, like every other copy in the inbox.
public enum MailFiling {
    /// Pippa's copies of shown and read mails (the app's `Inbox` uses the same folder).
    public static var inbox: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Pippa/Inbox", isDirectory: true)
    }

    /// Writes the attachments of `eml` into `folder` and returns their files in message order. A file already there with
    /// the same size is reused, so reading the same mail twice writes nothing new. Empty and inline parts are skipped.
    public static func saveAttachments(of eml: URL, into folder: URL) -> [URL] {
        guard let data = try? Data(contentsOf: eml) else { return [] }
        let parts = MailParser.parse(data).files.filter { !$0.inline && !$0.data.isEmpty }
        guard !parts.isEmpty, (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return [] }
        var taken: Set<String> = [eml.lastPathComponent.lowercased()]
        var saved: [URL] = []
        for part in parts {
            let url = folder.appendingPathComponent(uniqueName(part.name, taken: &taken))
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            if size != part.data.count {
                guard (try? part.data.write(to: url, options: .atomic)) != nil else { continue }
            }
            saved.append(url)
        }
        return saved
    }

    /// Where the attachments of `eml` go: beside it when it is already Pippa's copy, otherwise a folder of the inbox named
    /// after the file's path and modification date (a person's .eml in Documents stays untouched).
    public static func attachmentFolder(for eml: URL) -> URL {
        let path = eml.standardizedFileURL.path
        if path.hasPrefix(inbox.standardizedFileURL.path + "/") { return eml.deletingLastPathComponent() }
        let modified = (try? eml.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return inbox.appendingPathComponent("attachments-" + stableHash(path + "|" + String(modified)), isDirectory: true)
    }

    /// A mail read from Mail as files: the .eml (Mail's original message when it gave one) and its attachments, in one
    /// folder per message under `root`, so reading the same mail again reuses them.
    public static func file(_ mail: MailMessage, root: URL = inbox) throws -> (eml: URL, attachments: [URL]) {
        let identity = mail.messageID ?? (mail.subject + "|" + mail.sender + "|" + String(mail.date?.timeIntervalSince1970 ?? 0))
        let folder = root.appendingPathComponent("mail-" + stableHash(identity), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let eml = folder.appendingPathComponent(mail.fileName)
        let text = mail.emlText
        if (try? String(contentsOf: eml, encoding: .utf8)) != text { try text.write(to: eml, atomically: true, encoding: .utf8) }
        return (eml, saveAttachments(of: eml, into: folder))
    }

    /// File name from the attachment's own name; "Anhang" when it has none, " 2", " 3" … when two share a name.
    static func uniqueName(_ raw: String, taken: inout Set<String>) -> String {
        let clean = Naming.sanitize(raw, maxLength: 120)
        let name = clean.isEmpty ? "Anhang" : clean
        let ext = (name as NSString).pathExtension, base = (name as NSString).deletingPathExtension
        var candidate = name, n = 2
        while taken.contains(candidate.lowercased()) {
            candidate = base + " \(n)" + (ext.isEmpty ? "" : "." + ext); n += 1
        }
        taken.insert(candidate.lowercased())
        return candidate
    }

    /// FNV-1a over the UTF-8 bytes: the same text always gives the same folder name, across launches.
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(format: "%016llx", hash)
    }
}
