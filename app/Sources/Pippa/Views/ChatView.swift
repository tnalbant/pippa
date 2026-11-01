import AppKit
import PippaCore
import SwiftUI
import UniformTypeIdentifiers

/// The one window: conversations on the left, the chat on the right.
struct ChatView: View {
    @ObservedObject var chat: ChatModel
    @ObservedObject var setup: SetupModel
    private let searchState = State(initialValue: "")
    private let dropState = State(initialValue: false)

    var body: some View {
        NavigationSplitView {
            Sidebar(chat: chat, search: searchState.projectedValue)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } detail: {
            VStack(spacing: 0) {
                if let conversation = chat.current, !conversation.messages.isEmpty {
                    Transcript(chat: chat, setup: setup, conversation: conversation)
                } else {
                    Welcome(chat: chat, setup: setup)
                }
                Composer(chat: chat, setup: setup)
            }
            .background(Color(nsColor: Theme.chatTint))
            .overlay { if dropState.wrappedValue { DropOverlay() } }
            .onDrop(of: [.fileURL], isTargeted: dropState.projectedValue) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in AppActions.attach([url]) }
                    }
                }
                return true
            }
            .navigationTitle(chat.current?.title ?? "Pippa")
        }
    }
}

// MARK: Sidebar

private struct Sidebar: View {
    @ObservedObject var chat: ChatModel
    var search: Binding<String>

    var body: some View {
        List(selection: Binding(get: { chat.currentID }, set: { if let id = $0 { chat.select(id) } })) {
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { conversation in
                        Text(conversation.title.isEmpty ? T("New conversation", table: "App") : conversation.title)
                            .lineLimit(1)
                            .padding(.vertical, 2)
                            .tag(conversation.id)
                            .contextMenu {
                                Button(T("Delete", table: "App"), role: .destructive) { chat.delete(conversation.id) }
                            }
                    }
                }
            }
        }
        .searchable(text: search, placement: .sidebar, prompt: T("Search", table: "App"))
        .overlay {
            if groups.isEmpty {
                Text(search.wrappedValue.isEmpty ? T("Your conversations appear here.", table: "App") : T("Nothing found", table: "App"))
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24)
            }
        }
        .toolbar {
            ToolbarItem {
                Button { chat.newConversation() } label: { Label(T("New Conversation", table: "App"), systemImage: "square.and.pencil") }
                    .disabled(chat.isAnswering)
                    .help(T("New Conversation", table: "App") + " (⌘N)")
            }
        }
    }

    private var groups: [(title: String, items: [Conversation])] {
        let query = search.wrappedValue.trimmingCharacters(in: .whitespaces)
        let found = query.isEmpty ? chat.conversations : chat.conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(query)
                || conversation.messages.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func title(_ date: Date) -> String {
            if calendar.isDateInToday(date) { return T("Today", table: "App") }
            if calendar.isDateInYesterday(date) { return T("Yesterday", table: "App") }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: today).day ?? 0
            if days < 7 { return T("Previous 7 Days", table: "App") }
            if days < 30 { return T("Previous 30 Days", table: "App") }
            return T("Older", table: "App")
        }
        var result: [(title: String, items: [Conversation])] = []
        for conversation in found {
            let name = title(conversation.updated)
            if result.last?.title == name { result[result.count - 1].items.append(conversation) } else { result.append((name, [conversation])) }
        }
        return result
    }
}

// MARK: Empty state

private struct Welcome: View {
    @ObservedObject var chat: ChatModel
    @ObservedObject var setup: SetupModel
    private let suggestions: [(symbol: String, text: String)] = [
        ("calendar", T("What’s on my calendar this week?", table: "App")),
        ("doc.text.magnifyingglass", T("Find my lease and tell me the notice period", table: "App")),
        ("envelope", T("Which mails still need an answer from me?", table: "App")),
        ("folder", T("What’s new in my Downloads folder?", table: "App")),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                VStack(spacing: 6) {
                    Text(T("What can I do for you?", table: "App")).font(.title.weight(.semibold))
                    Text(T("Ask, or drop files here. I work on your Mac with Mail, Calendar, Reminders, Photos and your files.", table: "App"))
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                }
                if setup.needsAttention {
                    SetupCard(setup: setup).frame(maxWidth: 480)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(suggestions, id: \.text) { suggestion in
                            SuggestionButton(symbol: suggestion.symbol, text: suggestion.text) {
                                chat.draft = suggestion.text
                                if setup.canAnswer { chat.send() }
                            }
                        }
                    }
                    .frame(maxWidth: 540)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center)
        }
    }
}

private struct SuggestionButton: View {
    var symbol: String
    var text: String
    var action: () -> Void
    private let hoverState = State(initialValue: false)

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol).font(.body.weight(.medium)).foregroundStyle(Theme.accent).frame(width: 20)
                Text(text).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(hoverState.wrappedValue ? Theme.fill2 : Theme.chatCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.chatBorder))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoverState.wrappedValue = $0 }
    }
}

// MARK: Transcript

private struct Transcript: View {
    @ObservedObject var chat: ChatModel
    @ObservedObject var setup: SetupModel
    var conversation: Conversation

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if setup.needsAttention { SetupCard(setup: setup) }
                    ForEach(conversation.messages) { message in
                        MessageView(chat: chat, message: message,
                                    live: chat.isAnswering && message.id == conversation.messages.last?.id,
                                    isLast: message.id == conversation.messages.last?.id)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 12)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: conversation.id) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: conversation.messages.last) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
    }
}

private struct MessageView: View {
    @ObservedObject var chat: ChatModel
    var message: ChatMessage
    /// The answer that is coming in right now.
    var live: Bool
    var isLast: Bool
    private let hoverState = State(initialValue: false)

    var body: some View {
        switch message.role {
        case .user: user
        case .assistant: assistant
        }
    }

    private var user: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(message.files, id: \.self) { path in FileChip(url: URL(fileURLWithPath: path)) }
            if !message.text.isEmpty {
                Text(message.text).textSelection(.enabled).lineSpacing(2)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Theme.chatUser, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 90)
    }

    private var assistant: some View {
        VStack(alignment: .leading, spacing: 12) {
            if live || !message.steps.isEmpty || !(message.thinking ?? "").isEmpty {
                WorkView(message: message, live: live, started: chat.answerStarted)
            }
            if !message.text.isEmpty { MarkdownText(text: message.text) }
            // Text came, but Pippa is still at it (more tools, more thinking): keep showing that she works.
            if live && !message.text.isEmpty && message.steps.allSatisfy(\.done) {
                LiveLine(started: chat.answerStarted, label: T("Working…", table: "App"))
            }
            if !message.cards.isEmpty { ResultCardsView(cards: message.cards) }
            ForEach(Array(message.receipts.enumerated()), id: \.offset) { _, receipt in ReceiptRow(receipt: receipt) }
            if let error = message.error {
                ErrorBox(text: error, retry: isLast && !chat.isAnswering ? { chat.retry() } : nil)
            }
            if !live && !message.text.isEmpty {
                CopyButton(text: message.text).opacity(hoverState.wrappedValue ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hoverState.wrappedValue = $0 }
    }
}

/// What Pippa did on the way to the answer. While it works: the steps as they happen and a live "Thinking … 12 s".
/// Afterwards: one quiet line ("3 steps") that opens the steps and the model's thinking.
private struct WorkView: View {
    var message: ChatMessage
    var live: Bool
    var started: Date?
    private let openState = State(initialValue: false)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if live {
                steps
                if message.text.isEmpty && message.steps.allSatisfy(\.done) {
                    LiveLine(started: started, label: T("Thinking…", table: "App")) {
                        if !(message.thinking ?? "").isEmpty {
                            Button(openState.wrappedValue ? T("Hide", table: "App") : T("Show", table: "App")) { openState.wrappedValue.toggle() }
                                .buttonStyle(.link).font(.callout)
                        }
                    }
                }
                if openState.wrappedValue { thinkingText }
            } else {
                Button { withAnimation(.easeOut(duration: 0.15)) { openState.wrappedValue.toggle() } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(openState.wrappedValue ? 90 : 0))
                        Text(summary)
                        if message.steps.contains(where: \.failed) {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.need)
                        }
                    }
                    .font(.callout).foregroundStyle(.secondary).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if openState.wrappedValue {
                    steps.padding(.leading, 4)
                    thinkingText
                }
            }
        }
    }

    private var summary: String {
        let count = message.steps.count
        if count == 0 { return T("Thought it through", table: "App") }
        return count == 1 ? T("1 step", table: "App") : T("%lld steps", table: "App", count)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(message.steps) { step in
                HStack(spacing: 7) {
                    Group {
                        if !step.done && live { ProgressView().controlSize(.mini) }
                        else { Image(systemName: step.failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(step.failed ? Theme.bad : Theme.ok.opacity(0.8)) }
                    }
                    .frame(width: 14)
                    Text(step.label).lineLimit(1).truncationMode(.middle)
                }
                .font(.callout).foregroundStyle(.secondary)
            }
        }
    }


    @ViewBuilder private var thinkingText: some View {
        if let thinking = message.thinking?.trimmingCharacters(in: .whitespacesAndNewlines), !thinking.isEmpty {
            Text(thinking)
                .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                .lineLimit(live ? 6 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.chatBorder).frame(width: 2) }
        }
    }
}

/// "Thinking … 12 s": a spinner, what Pippa is doing and how long the answer has been running.
private struct LiveLine<Trailing: View>: View {
    var started: Date?
    var label: String
    @ViewBuilder var trailing: Trailing

    init(started: Date?, label: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.started = started; self.label = label; self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.mini).frame(width: 14)
            Text(label)
            if let started {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = Int(context.date.timeIntervalSince(started))
                    if seconds >= 3 { Text(T("%lld s", table: "App", seconds)).monospacedDigit() }
                }
            }
            trailing
        }
        .font(.callout).foregroundStyle(.secondary)
    }
}

private struct ErrorBox: View {
    var text: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.bad)
            Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 8)
            if let retry { Button(T("Try Again", table: "App"), action: retry).controlSize(.small) }
        }
        .padding(12)
        .background(Theme.badTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct CopyButton: View {
    var text: String
    private let copiedState = State(initialValue: false)

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copiedState.wrappedValue = true
            Task { try? await Task.sleep(for: .seconds(1.5)); copiedState.wrappedValue = false }
        } label: {
            Label(copiedState.wrappedValue ? T("Copied", table: "App") : T("Copy", table: "App"),
                  systemImage: copiedState.wrappedValue ? "checkmark" : "doc.on.doc")
                .font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
    }
}

/// What a writing tool did: added to Calendar, a reminder, a Mail draft.
private struct ReceiptRow: View {
    var receipt: PippaMCPWriteReceipt
    private var done: Bool { receipt.outcome == "done" }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(done ? Theme.ok : Theme.need)
                .frame(width: 32, height: 32)
                .background(done ? Theme.okTint : Theme.needTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                if !receipt.name.isEmpty { Text(receipt.name).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if receipt.action == "mailDraft", done {
                Button(T("Open Mail", table: "App")) { Task { await PippaMCPService.showMail() } }.controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Theme.chatCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.chatBorder))
    }

    private var symbol: String {
        switch receipt.action {
        case "calendarAdd": return "calendar.badge.plus"
        case "reminderAdd": return "checklist"
        case "mailDraft": return "envelope"
        default: return "checkmark"
        }
    }

    private var title: String {
        switch receipt.action {
        case "calendarAdd": return done ? T("Added to Calendar", table: "App") : T("Not added to Calendar", table: "App")
        case "reminderAdd": return done ? T("Reminder added", table: "App") : T("No reminder added", table: "App")
        case "mailDraft": return done ? T("Draft in Mail, not sent", table: "App") : T("No Mail draft", table: "App")
        default: return receipt.name
        }
    }
}

// MARK: Composer

private struct Composer: View {
    @ObservedObject var chat: ChatModel
    @ObservedObject var setup: SetupModel
    @FocusState private var focused: Bool

    private var canSend: Bool {
        setup.canAnswer && !(chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chat.attachments.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !chat.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chat.attachments, id: \.self) { url in
                            Chip(title: url.lastPathComponent, icon: NSWorkspace.shared.icon(forFile: url.path), symbol: "doc") {
                                chat.attachments.removeAll { $0 == url }
                            }
                        }
                    }
                }
            }
            TextField(T("Ask Pippa…", table: "App"), text: $chat.draft, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(1...10).focused($focused)
                .onSubmit { if canSend { chat.send() } }
            HStack(spacing: 10) {
                Button { addFiles() } label: { Image(systemName: "paperclip").font(.system(size: 14, weight: .medium)) }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help(T("Add Files…", table: "App"))
                if chat.canMakePDF && !chat.isAnswering {
                    Button { chat.makePDF() } label: { Label(T("One PDF", table: "App"), systemImage: "doc.richtext") }
                        .controlSize(.small).help(T("Make one PDF from these files, right here on your Mac", table: "App"))
                }
                Spacer()
                AIBadge(setup: setup)
                if chat.isAnswering {
                    RoundButton(symbol: "stop.fill", filled: true, tint: Theme.ink) { chat.stop() }
                        .help(T("Stop", table: "App"))
                } else {
                    RoundButton(symbol: "arrow.up", filled: canSend, tint: Theme.accentFill) { chat.send() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!canSend)
                        .help(T("Send", table: "App") + " (↩)")
                }
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
        .background(Theme.chatCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(focused ? Theme.accent.opacity(0.5) : Theme.chatBorder))
        .shadow(color: .black.opacity(0.07), radius: 14, y: 4)
        .padding(.horizontal, 24).padding(.bottom, 18).padding(.top, 6)
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
        .onAppear { focused = true }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !chat.attachments.contains(url) { chat.attachments.append(url) }
    }
}

/// Which AI answers: on this Mac, or the online one chosen in Settings. A click opens Settings.
private struct AIBadge: View {
    @ObservedObject var setup: SetupModel

    var body: some View {
        Button { SettingsWindow.shared.show() } label: {
            HStack(spacing: 4) {
                if case .preparing = setup.state, !setup.usesOnlineAI { ProgressView().controlSize(.mini) }
                else { Image(systemName: setup.usesOnlineAI ? "cloud" : "laptopcomputer") }
                Text(label).lineLimit(1)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(T("Change in Settings", table: "App"))
    }

    private var label: String {
        let settings = InferenceSettings.load(from: PiSession.settingsDirectory)
        if settings.subscriptionModel != nil { return "ChatGPT" }
        if let connection = PiOnlineProvider.activeConnection(settings) { return connection.modelID }
        switch setup.state {
        case .ready: return T("On this Mac", table: "App")
        case .preparing: return T("Getting ready…", table: "App")
        case .downloading: return T("Loading AI…", table: "App")
        default: return T("Not set up", table: "App")
        }
    }
}

private struct RoundButton: View {
    var symbol: String
    var filled: Bool
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(filled ? Color(nsColor: .textBackgroundColor) : Color.secondary)
                .frame(width: 28, height: 28)
                .background(filled ? tint : Theme.fill3, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct Chip: View {
    var title: String
    var icon: NSImage?
    var symbol: String
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) } else { Image(systemName: symbol) }
            Text(title).lineLimit(1).truncationMode(.middle).frame(maxWidth: 200, alignment: .leading)
            Button(action: remove) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.leading, 8).padding(.trailing, 9).padding(.vertical, 5)
        .background(Theme.fill2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A file the person added to a question; a click opens it.
private struct FileChip: View {
    var url: URL
    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
                Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
            }
            .font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.chatCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.chatBorder))
        }
        .buttonStyle(.plain)
    }
}

private struct DropOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.accentTint)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 32, weight: .medium))
                    Text(T("Drop files for Pippa", table: "App")).font(.title3.weight(.semibold))
                }
                .foregroundStyle(Theme.accent)
            }
            .padding(12)
            .allowsHitTesting(false)
    }
}
