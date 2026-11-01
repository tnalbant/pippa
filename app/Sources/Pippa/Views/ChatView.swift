import AppKit
import PippaCore
import SwiftUI
import UniformTypeIdentifiers

/// The one window: conversations on the left, the chat on the right.
struct ChatView: View {
    @ObservedObject var chat: ChatModel
    @ObservedObject var setup: SetupModel

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { chat.currentID }, set: { if let id = $0 { chat.select(id) } })) {
                ForEach(chat.conversations) { conversation in
                    Text(conversation.title.isEmpty ? T("New conversation", table: "App") : conversation.title)
                        .lineLimit(1)
                        .tag(conversation.id)
                        .contextMenu {
                            Button(T("Delete", table: "App"), role: .destructive) { chat.delete(conversation.id) }
                        }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .toolbar {
                ToolbarItem {
                    Button { chat.newConversation() } label: { Label(T("New Conversation", table: "App"), systemImage: "square.and.pencil") }
                        .disabled(chat.isAnswering)
                }
            }
        } detail: {
            VStack(spacing: 0) {
                Transcript(chat: chat, setup: setup)
                Composer(chat: chat, enabled: setup.canAnswer)
            }
            .background(Color(nsColor: Theme.chatTint))
        }
    }
}

private struct Transcript: View {
    @ObservedObject var chat: ChatModel
    @ObservedObject var setup: SetupModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if !setup.canAnswer { SetupCard(setup: setup) }
                    if let conversation = chat.current {
                        ForEach(conversation.messages) { message in
                            MessageView(message: message, answering: chat.isAnswering && message.id == conversation.messages.last?.id)
                                .id(message.id)
                        }
                    } else if setup.canAnswer {
                        Welcome(chat: chat)
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: chat.current?.messages.last) { _, last in
                if let last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}

private struct Welcome: View {
    @ObservedObject var chat: ChatModel
    private let examples = [
        T("What’s on my calendar this week?", table: "App"),
        T("Find my lease and tell me the notice period", table: "App"),
        T("Turn these photos into one PDF", table: "App"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("What can I do for you?", table: "App")).font(.title2.weight(.semibold))
            Text(T("Ask, or drop files here. I work on your Mac with Mail, Calendar, Reminders, Photos and your files.", table: "App"))
                .foregroundStyle(.secondary)
            ForEach(examples, id: \.self) { example in
                Button(example) { chat.draft = example }.buttonStyle(.link)
            }
        }
        .padding(.top, 40)
    }
}

private struct MessageView: View {
    var message: ChatMessage
    var answering: Bool

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                if !message.text.isEmpty {
                    Text(message.text).textSelection(.enabled)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.chatUser, in: RoundedRectangle(cornerRadius: 12))
                }
                ForEach(message.files, id: \.self) { path in
                    Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "doc").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant:
            VStack(alignment: .leading, spacing: 10) {
                if !message.steps.isEmpty { StepsView(steps: message.steps) }
                if !message.text.isEmpty {
                    Text(Self.markdown(message.text)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                } else if answering {
                    ProgressView().controlSize(.small)
                }
                if !message.cards.isEmpty { ResultCardsView(cards: message.cards) }
                ForEach(Array(message.receipts.enumerated()), id: \.offset) { _, receipt in ReceiptRow(receipt: receipt) }
                if let error = message.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.bad).font(.callout)
                }
            }
        }
    }

    static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// What Pi did while answering, one quiet line per step.
private struct StepsView: View {
    var steps: [ChatStep]
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(steps) { step in
                HStack(spacing: 6) {
                    Image(systemName: step.failed ? "xmark.circle" : step.done ? "checkmark.circle" : "circle.dotted")
                        .foregroundStyle(step.failed ? Theme.bad : .secondary)
                    Text(step.label).lineLimit(1).truncationMode(.middle)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// What a writing tool did: added to Calendar, a reminder, a Mail draft.
private struct ReceiptRow: View {
    var receipt: PippaMCPWriteReceipt
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: receipt.outcome == "done" ? "checkmark.seal" : "exclamationmark.circle")
                .foregroundStyle(receipt.outcome == "done" ? Theme.ok : Theme.need)
            Text(title).font(.callout)
            if receipt.action == "mailDraft", receipt.outcome == "done" {
                Button(T("Open Mail", table: "App")) { Task { await PippaMCPService.showMail() } }.buttonStyle(.link)
            }
        }
        .padding(10)
        .background(Theme.chatCard, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.chatBorder))
    }

    private var title: String {
        let done = receipt.outcome == "done"
        switch receipt.action {
        case "calendarAdd": return done ? T("Added to Calendar: %@", table: "App", receipt.name) : T("Not added to Calendar", table: "App")
        case "reminderAdd": return done ? T("Reminder added: %@", table: "App", receipt.name) : T("No reminder added", table: "App")
        case "mailDraft": return done ? T("Draft in Mail: %@", table: "App", receipt.name) : T("No Mail draft", table: "App")
        default: return receipt.name
        }
    }
}

private struct Composer: View {
    @ObservedObject var chat: ChatModel
    var enabled: Bool
    private let targetedState = State(initialValue: false)
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !chat.attachments.isEmpty || chat.frontApp != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let app = chat.frontApp {
                            Chip(title: app, systemImage: "macwindow") { chat.frontApp = nil }
                        }
                        ForEach(chat.attachments, id: \.self) { url in
                            Chip(title: url.lastPathComponent, systemImage: "doc") { chat.attachments.removeAll { $0 == url } }
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button { addFiles() } label: { Image(systemName: "paperclip") }
                    .buttonStyle(.borderless).help(T("Add Files…", table: "App"))
                TextField(T("Ask Pippa", table: "App"), text: $chat.draft, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...8).focused($focused)
                    .onSubmit { chat.send() }
                if chat.isAnswering {
                    Button { chat.stop() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                        .buttonStyle(.borderless).help(T("Stop", table: "App"))
                } else {
                    Button { chat.send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .buttonStyle(.borderless).keyboardShortcut(.return, modifiers: .command)
                        .disabled(!enabled || (chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chat.attachments.isEmpty))
                }
            }
            .padding(10)
            .background(Theme.chatCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(targetedState.wrappedValue ? Theme.accent : Theme.chatBorder, lineWidth: targetedState.wrappedValue ? 2 : 1))
        }
        .padding(.horizontal, 20).padding(.bottom, 16).padding(.top, 6)
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
        .onDrop(of: [.fileURL], isTargeted: targetedState.projectedValue) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in if !chat.attachments.contains(url) { chat.attachments.append(url) } }
                }
            }
            return true
        }
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

private struct Chip: View {
    var title: String
    var systemImage: String
    var remove: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title).lineLimit(1).truncationMode(.middle).frame(maxWidth: 180)
            Button(action: remove) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.accentTint, in: Capsule())
    }
}
