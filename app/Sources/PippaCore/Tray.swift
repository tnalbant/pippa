import Foundation

// The tray at the pill ("Tray"): given things and finished results, remembered across restarts.
// Pure and without AppKit: rules as functions over `TrayState`, storage as one JSON file.

/// A thing in the tray: given (the person's file, reference only) or result (Pippa's file in the cache).
public struct TrayItem: Codable, Sendable, Identifiable, Hashable {
    public enum Role: String, Codable, Sendable { case given, result }
    public var id: UUID
    public var role: Role
    public var url: URL
    /// Security-scoped bookmark; nil for Pippa's own copies (Inbox, Results).
    public var bookmark: Data?
    public var name: String
    /// "Downloads", "Mail", "Schreibtisch" – never a path.
    public var origin: String?
    public var addedAt: Date
    public var touchedAt: Date?
    /// Result → job in the journal (undo).
    public var receipt: UUID?
    /// Result → given things that were merged into it (come back on undo).
    public var sources: [UUID]
    /// Result → which tool made it.
    public var tool: ToolID?
    /// Result-specific caveat, retained when another result is shown or the app restarts.
    public var note: String?

    public init(id: UUID = UUID(), role: Role, url: URL, bookmark: Data? = nil, name: String? = nil, origin: String? = nil,
                addedAt: Date = Date(), receipt: UUID? = nil, sources: [UUID] = [], tool: ToolID? = nil, note: String? = nil) {
        self.id = id; self.role = role; self.url = url; self.bookmark = bookmark
        self.name = name ?? url.lastPathComponent
        self.origin = origin; self.addedAt = addedAt; self.touchedAt = nil
        self.receipt = receipt; self.sources = sources; self.tool = tool; self.note = note
    }

}
