import Foundation

// Value types of the undo journal (`Executor`): the receipt of a job and files that stayed in place.

/// A file (or entry) that stayed in place or was not returned, with a short German reason.
public struct FileReason: Sendable, Hashable {
    public var name: String               // e.g. "Rechnung.pdf"
    public var why: String                // e.g. "Darauf habe ich keinen Zugriff." ("I have no access to that.")
    public init(name: String, why: String) { self.name = name; self.why = why }
}

public struct JobReceipt: Sendable, Identifiable, Hashable {
    public var id: UUID
    public var summary: String            // e.g. "46 Dateien geordnet" (46 files sorted)
    public var detail: String             // e.g. "In 4 Ordnern · 1 bleibt liegen" (in 4 folders, 1 stays)
    public var revealURL: URL?
    /// Text after "Rückgängig" (undo); `nil` = files ("wieder an ihrem alten Platz", back in their old place).
    public var undoDetail: String?
    /// App in which something was entered (to open it from the notice).
    public var integration: Integration?
    /// Files that stayed in place, each with a reason (empty if everything worked).
    public var stayed: [FileReason]
    /// When the job ran (set in the history).
    public var date: Date?
    public init(id: UUID, summary: String, detail: String, revealURL: URL?, undoDetail: String? = nil, integration: Integration? = nil,
                stayed: [FileReason] = [], date: Date? = nil) {
        self.id = id; self.summary = summary; self.detail = detail; self.revealURL = revealURL; self.undoDetail = undoDetail; self.integration = integration
        self.stayed = stayed; self.date = date
    }
}
