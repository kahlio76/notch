import AppKit
import Combine
import NotchCore

enum Surface: Equatable { case idle, wings, peek, widgets, request, done }
enum ControlSlider: Equatable { case volume, brightness }

struct Track: Equatable {
    var id: String
    var name: String
    var artist: String
    var album: String
    var duration: Double
    var artURL: String
}

struct WeatherNow: Equatable {
    var city: String
    var temperature: Int
    var high: Int
    var low: Int
    var symbol: String
    var label: String
}

struct Peek: Equatable {
    var symbol: String?
    var icon: NSImage?
    var title: String
    var detail: String
}

struct ApprovalRequest: Identifiable {
    let id: UUID
    let sessionID: String
    let summary: String
    let project: String
    /// Set when Claude is asking multiple-choice questions rather than for permission.
    var questions: [ClaudeQuestion] = []
    let respond: (Bool) -> Void
    var answer: ([String: String]) -> Void = { _ in }
    /// Hands the prompt back to Claude's own window.
    let cancel: () -> Void
}

struct DoneBanner: Equatable {
    var title: String
    var detail: String
    var project: String
}

struct ClaudeSession {
    var project: String
    var startedAt: Date?
    var files: Set<String> = []
    var lastEvent = Date()
    var working: Bool { startedAt != nil }
}

/// All state the notch draws. Touched only on the main thread.
final class NotchStore: ObservableObject {
    static let panelWidth: CGFloat = 620

    @Published var notchWidth: CGFloat = 185
    @Published var notchHeight: CGFloat = 32
    @Published var hovering = false
    /// The mouse has rested on the notch but hasn't stayed long enough to open it.
    @Published var nudged = false
    @Published var pinnedApps: [String] = []
    @Published var activeSlider: ControlSlider?
    @Published var volume: Float = 0
    @Published var brightness: Float = 0

    @Published var peek: Peek?
    private var peekQueue: [Peek] = []

    @Published var track: Track?
    @Published var isPlaying = false
    @Published var artwork: NSImage?
    @Published var musicNeedsPermission = false
    @Published var spotifyRunning = false
    @Published var lyrics: [LyricLine] = []
    var positionAnchor: (position: Double, at: Date) = (0, Date())

    @Published var weather: WeatherNow?

    @Published var requests: [ApprovalRequest] = []
    @Published var done: DoneBanner?
    @Published var sessions: [String: ClaudeSession] = [:]
    /// Progress through the front request's questions.
    @Published var questionStep = 0
    @Published var picked: Set<Int> = []
    private var answers: [String: String] = [:]
    private var frontShownAt = Date.distantPast
    private var doneTimer: Timer?

    var claudeWorking: Bool { sessions.values.contains { $0.working } }
    var position: Double {
        positionAnchor.position + (isPlaying ? Date().timeIntervalSince(positionAnchor.at) : 0)
    }

    var surface: Surface {
        if !requests.isEmpty { return .request }
        if hovering { return .widgets }
        if done != nil { return .done }
        if peek != nil { return .peek }
        if claudeWorking || (track != nil && isPlaying) { return .wings }
        return .idle
    }

    var surfaceSize: CGSize {
        let nudge: CGFloat = nudged ? 1 : 0
        switch surface {
        case .idle: return CGSize(width: notchWidth + 12 * nudge, height: notchHeight + 8 * nudge)
        case .wings: return CGSize(width: notchWidth + 84 + 12 * nudge, height: notchHeight + 8 * nudge)
        case .peek: return CGSize(width: max(notchWidth + 40, 240) + 12 * nudge, height: notchHeight + 34 + 8 * nudge)
        case .widgets:
            let slider: CGFloat = activeSlider == nil ? 0 : 32
            let lyricsArea: CGFloat = track == nil ? 0 : 50
            return CGSize(width: Self.panelWidth, height: notchHeight + 8 + 104 + slider + lyricsArea + 14)
        case .request:
            guard let question = currentQuestion else { return CGSize(width: Self.panelWidth, height: notchHeight + 118) }
            let rows = CGFloat((question.options.count + 1) / 2)
            return CGSize(width: Self.panelWidth, height: notchHeight + 92 + rows * 46)
        case .done: return CGSize(width: Self.panelWidth, height: notchHeight + 76)
        }
    }

    var isPanel: Bool { [.widgets, .request, .done].contains(surface) }
    /// How far the shape flares out where it meets the top of the screen.
    var topRadius: CGFloat { isPanel ? 19 : 6 }
    var bottomRadius: CGFloat { isPanel ? 24 : 14 }

    // MARK: Peeks

    func show(peek new: Peek) {
        if peek == nil { present(new) } else if peekQueue.count < 2 { peekQueue.append(new) }
    }

    private func present(_ new: Peek) {
        peek = new
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            guard let self else { return }
            self.peek = nil
            if !self.peekQueue.isEmpty { self.present(self.peekQueue.removeFirst()) }
        }
    }

    // MARK: Claude

    func handle(_ event: ClaudeEvent) {
        var session = sessions[event.sessionID] ?? ClaudeSession(project: event.project)
        session.lastEvent = Date()
        switch event.name {
        case "SessionStart":
            sessions[event.sessionID] = session
        case "UserPromptSubmit":
            session.startedAt = Date()
            session.files = []
            sessions[event.sessionID] = session
            cancelRequests(for: event.sessionID)
        case "PostToolUse":
            // Covers sessions that started before the app did.
            if session.startedAt == nil { session.startedAt = Date() }
            if let file = event.changedFile { session.files.insert(file) }
            sessions[event.sessionID] = session
        case "Stop":
            if let started = session.startedAt {
                let count = session.files.count
                let files = count == 0 ? "No files changed" : "\(count) file\(count == 1 ? "" : "s") changed"
                show(done: DoneBanner(title: doneDuration(Date().timeIntervalSince(started)),
                                      detail: files, project: session.project))
            }
            session.startedAt = nil
            sessions[event.sessionID] = session
            cancelRequests(for: event.sessionID)
        case "SessionEnd":
            sessions[event.sessionID] = nil
            cancelRequests(for: event.sessionID)
        default:
            break
        }
    }

    /// A session killed mid-turn never sends Stop, so a quiet one stops counting as working.
    func expireQuietSessions() {
        for (id, session) in sessions where session.working && Date().timeIntervalSince(session.lastEvent) > 900 {
            sessions[id]?.startedAt = nil
        }
    }

    private func show(done banner: DoneBanner) {
        done = banner
        doneTimer?.invalidate()
        doneTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in self?.done = nil }
    }

    func add(_ request: ApprovalRequest) {
        if requests.isEmpty { newFront() }
        requests.append(request)
    }

    func remove(requestID: UUID) {
        let wasFront = requests.first?.id == requestID
        requests.removeAll { $0.id == requestID }
        if wasFront { newFront() }
    }

    private func newFront() {
        frontShownAt = Date()
        questionStep = 0
        picked = []
        answers = [:]
    }

    /// The question on screen, if the front request is asking questions.
    var currentQuestion: ClaudeQuestion? {
        guard let questions = requests.first?.questions, questionStep < questions.count else { return nil }
        return questions[questionStep]
    }

    /// Picks an option. On a multi-select question it toggles instead, and `submitPicks` moves on.
    func choose(option index: Int) {
        guard let question = currentQuestion, index < question.options.count, settled else { return }
        if question.multiSelect {
            if picked.contains(index) { picked.remove(index) } else { picked.insert(index) }
        } else {
            record(question, [question.options[index].label])
        }
    }

    func submitPicks() {
        guard let question = currentQuestion, question.multiSelect, !picked.isEmpty, settled else { return }
        record(question, picked.sorted().map { question.options[$0].label })
    }

    /// Leaves the prompt for Claude's own window, e.g. to type an answer that isn't on the list.
    func passToClaude() {
        guard let front = requests.first, settled else { return }
        front.cancel()
        remove(requestID: front.id)
    }

    private func record(_ question: ClaudeQuestion, _ labels: [String]) {
        guard let front = requests.first else { return }
        answers[question.question] = ClaudeQuestion.answer(labels)
        if questionStep + 1 < front.questions.count {
            questionStep += 1
            picked = []
            // A quick double click shouldn't also answer the next question.
            frontShownAt = Date()
        } else {
            front.answer(answers)
            remove(requestID: front.id)
        }
    }

    private var settled: Bool { Date().timeIntervalSince(frontShownAt) > 0.4 }

    private func cancelRequests(for sessionID: String) {
        for request in requests where request.sessionID == sessionID {
            request.cancel()
            remove(requestID: request.id)
        }
    }

    /// Ignores input in the first moments a card is up, so a click or keypress
    /// meant for something else can't approve a request that just appeared.
    func decide(allow: Bool) {
        guard let front = requests.first, front.questions.isEmpty, settled else { return }
        front.respond(allow)
        remove(requestID: front.id)
    }
}
