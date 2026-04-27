import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
public final class ChatViewModel {
    private let sessionRepository: SessionRepository
    private let messageRepository: MessageRepository
    private let inferenceEngine: InferenceEngine
    private let metricsRecorder: MetricsRecorder

    public private(set) var sessions: [ChatSessionRecord] = []
    public private(set) var messages: [ChatMessageRecord] = []
    public var selectedSessionID: UUID?
    public var draftMessage = ""
    public private(set) var isGenerating = false
    public private(set) var isLoadingModel = false
    public private(set) var isRestoringModel = false
    public private(set) var modelLoaded = false
    public private(set) var loadedModelName: String?
    public private(set) var errorMessage: String?
    public private(set) var lastFailedPrompt: String?
    public private(set) var lastGenerationMetrics: GenerationMetrics?
    public private(set) var recentGenerationMetrics: [GenerationMetrics] = []
    public private(set) var generationPhase: GenerationPhase = .idle
    public private(set) var liveGenerationSnapshot = GenerationMonitoringSnapshot(
        phase: .idle,
        elapsedMs: 0,
        streamedCharacterCount: 0,
        approxCharsPerSecond: nil
    )
    public private(set) var latestMonitoringHealth: MonitoringHealthState = .healthy
    public private(set) var tokenBudgetResult: TokenBudgetResult?
    public private(set) var contextNotice: String?
    public private(set) var contextNoticeDetails: String?
    public private(set) var isShowingContextNoticeDetails = false
    public private(set) var contextFidelityState: ContextFidelityState = .normal

    private var generationTask: Task<Void, Never>?
    private var activeAssistantMessageID: UUID?
    private var activeGenerationPromptID: UUID?
    private var activeGenerationSessionID: UUID?
    private var cancellationRequested = false
    private var activeGenerationInputTokens: Int?
    private var activeContextUtilization: Double?
    private var activeCompactionApplied = false
    private var rollingHistorySummaries: [UUID: String] = [:]
    private let recentMetricsWindowSize = 10
    private let pinnedRecentMessageCount = 12

    public init(
        sessionRepository: SessionRepository,
        messageRepository: MessageRepository,
        inferenceEngine: InferenceEngine,
        metricsRecorder: MetricsRecorder = ConsoleMetricsRecorder()
    ) {
        self.sessionRepository = sessionRepository
        self.messageRepository = messageRepository
        self.inferenceEngine = inferenceEngine
        self.metricsRecorder = metricsRecorder
    }

    public func bootstrap() async {
        await refreshSessions()
        guard let selectedSessionID else { return }
        await loadMessages(for: selectedSessionID)
    }

    public func refreshSessions() async {
        do {
            sessions = try await sessionRepository.listSessions()
            if selectedSessionID == nil {
                selectedSessionID = sessions.first?.id
            }
        } catch {
            setError("Failed to load sessions: \(error.localizedDescription)")
        }
    }

    public func loadMessages(for sessionID: UUID) async {
        selectedSessionID = sessionID
        do {
            messages = try await messageRepository.listMessages(sessionID: sessionID)
        } catch {
            setError("Failed to load messages: \(error.localizedDescription)")
        }
    }

    public func createSession() async {
        do {
            let session = try await sessionRepository.createSession(title: nil)
            await refreshSessions()
            await loadMessages(for: session.id)
        } catch {
            setError("Failed to create session: \(error.localizedDescription)")
        }
    }

    public func renameSession(id: UUID, title: String) async {
        do {
            try await sessionRepository.renameSession(id: id, title: title)
            await refreshSessions()
        } catch {
            setError("Failed to rename session: \(error.localizedDescription)")
        }
    }

    public func deleteSession(id: UUID) async {
        do {
            try await sessionRepository.deleteSession(id: id)
            if selectedSessionID == id {
                selectedSessionID = nil
                messages = []
            }
            await refreshSessions()
            if let firstSession = sessions.first {
                await loadMessages(for: firstSession.id)
            }
        } catch {
            setError("Failed to delete session: \(error.localizedDescription)")
        }
    }

    public func loadModel(from pickedModelURL: URL) async {
        guard pickedModelURL.pathExtension.lowercased() == "gguf" else {
            setError("Invalid model type. Please select a .gguf model file.")
            return
        }

        let didStartSecurityScope = pickedModelURL.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                pickedModelURL.stopAccessingSecurityScopedResource()
            }
        }
        isLoadingModel = true
        defer { isLoadingModel = false }

        do {
            try ImportedModelStore.preflightSource(at: pickedModelURL)
            let localModelURL = try ImportedModelStore.copyToAppModelsDirectory(from: pickedModelURL)
            try await inferenceEngine.loadModel(from: localModelURL)
            modelLoaded = true
            loadedModelName = localModelURL.lastPathComponent
            ImportedModelStore.setLastLoadedModelName(localModelURL.lastPathComponent)
            clearError()
        } catch let error as IntraiError {
            modelLoaded = false
            setError("Failed to load model: \(error.localizedDescription)")
        } catch {
            modelLoaded = false
            setError("Failed to load model: \(error.localizedDescription)")
        }
    }

    public func restoreLastModelIfAvailable() async {
        guard let fileName = ImportedModelStore.lastLoadedModelName() else {
            return
        }

        isRestoringModel = true
        defer { isRestoringModel = false }

        let modelURL: URL
        do {
            modelURL = try ImportedModelStore.modelURL(fileName: fileName)
        } catch {
            ImportedModelStore.clearLastLoadedModelName()
            modelLoaded = false
            loadedModelName = nil
            return
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: modelURL.path), fileManager.isReadableFile(atPath: modelURL.path) else {
            ImportedModelStore.clearLastLoadedModelName()
            modelLoaded = false
            loadedModelName = nil
            return
        }

        do {
            try ImportedModelStore.preflightSource(at: modelURL)
            try await inferenceEngine.loadModel(from: modelURL)
            modelLoaded = true
            loadedModelName = fileName
            clearError()
        } catch let error as IntraiError {
            ImportedModelStore.clearLastLoadedModelName()
            modelLoaded = false
            loadedModelName = nil
            setError("Failed to restore previous model: \(error.localizedDescription)")
        } catch {
            ImportedModelStore.clearLastLoadedModelName()
            modelLoaded = false
            loadedModelName = nil
            setError("Failed to restore previous model: \(error.localizedDescription)")
        }
    }

    public func sendDraftMessage() async {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draftMessage = ""
        await sendPrompt(text)
    }

    public func sendPrompt(_ text: String) async {
        guard modelLoaded else {
            setError("Load a model before sending messages.")
            return
        }
        generationPhase = .preparing

        do {
            let sessionID = try await ensureSessionID()
            if selectedSessionID != sessionID {
                await loadMessages(for: sessionID)
            }

            let preflight = try await preparePromptWithinBudget(sessionID: sessionID, userInput: text)
            tokenBudgetResult = preflight.budget
            contextNotice = preflight.notice
            contextNoticeDetails = preflight.noticeDetails
            isShowingContextNoticeDetails = false

            let options = GenerationOptions(
                maxTokens: preflight.budget.maxOutputTokens,
                temperature: 0.7
            )
            let userMessage = try await messageRepository.appendUserMessage(sessionID: sessionID, content: text)
            let assistantMessage = try await messageRepository.appendAssistantPlaceholder(sessionID: sessionID)
            activeAssistantMessageID = assistantMessage.id
            activeGenerationPromptID = userMessage.id
            activeGenerationSessionID = sessionID
            activeGenerationInputTokens = preflight.budget.estimatedInputTokens
            activeContextUtilization = preflight.budget.utilization
            activeCompactionApplied = preflight.compactionApplied
            contextFidelityState = fidelityState(for: preflight.budget, compactionApplied: preflight.compactionApplied)

            await loadMessages(for: sessionID)
            clearError()
            isGenerating = true
            generationPhase = .waitingForFirstToken
            liveGenerationSnapshot = GenerationMonitoringSnapshot(
                phase: .waitingForFirstToken,
                elapsedMs: 0,
                streamedCharacterCount: 0,
                approxCharsPerSecond: nil
            )
            lastFailedPrompt = nil
            cancellationRequested = false

            generationTask?.cancel()
            generationTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let startedAt = Date()
                var firstTokenAt: Date?
                var streamedCharacterCount = 0
                var wasCancelled = false
                var generationFailed = false

                do {
                    for try await chunk in await self.inferenceEngine.generateStream(
                        prompt: preflight.prompt,
                        options: options
                    ) {
                        guard let assistantID = self.activeAssistantMessageID else {
                            continue
                        }
                        try await self.messageRepository.appendAssistantChunk(messageID: assistantID, chunk: chunk)
                        streamedCharacterCount += chunk.count
                        if firstTokenAt == nil {
                            firstTokenAt = Date()
                            self.generationPhase = .streaming
                        }
                        let elapsedMs = max(1, Date().timeIntervalSince(startedAt) * 1000)
                        self.liveGenerationSnapshot = GenerationMonitoringSnapshot(
                            phase: self.generationPhase,
                            elapsedMs: elapsedMs,
                            streamedCharacterCount: streamedCharacterCount,
                            approxCharsPerSecond: Double(streamedCharacterCount) / (elapsedMs / 1000)
                        )
                        if let session = self.selectedSessionID {
                            await self.loadMessages(for: session)
                        }
                    }

                    if let assistantID = self.activeAssistantMessageID {
                        try await self.messageRepository.markMessageComplete(messageID: assistantID)
                    }
                } catch {
                    generationFailed = true
                    if Task.isCancelled {
                        wasCancelled = true
                    }
                    await self.handleGenerationFailure(prompt: text, error: error)
                }

                wasCancelled = wasCancelled || self.cancellationRequested

                let finishedAt = Date()
                let endReason = self.resolveEndReason(
                    generationFailed: generationFailed,
                    wasCancelled: wasCancelled
                )
                await self.recordMetrics(
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    firstTokenAt: firstTokenAt,
                    streamedCharacterCount: streamedCharacterCount,
                    wasCancelled: wasCancelled,
                    generationFailed: generationFailed,
                    endReason: endReason
                )

                self.isGenerating = false
                self.generationPhase = .idle
                self.liveGenerationSnapshot = GenerationMonitoringSnapshot(
                    phase: .idle,
                    elapsedMs: finishedAt.timeIntervalSince(startedAt) * 1000,
                    streamedCharacterCount: streamedCharacterCount,
                    approxCharsPerSecond: self.liveGenerationSnapshot.approxCharsPerSecond
                )
                self.generationTask = nil
                self.activeAssistantMessageID = nil
                self.activeGenerationPromptID = nil
                self.activeGenerationSessionID = nil
                self.cancellationRequested = false
                self.activeGenerationInputTokens = nil
                self.activeContextUtilization = nil
                self.activeCompactionApplied = false

                if let session = self.selectedSessionID {
                    await self.loadMessages(for: session)
                    await self.refreshSessions()
                }
            }
        } catch {
            generationPhase = .idle
            setError("Failed to send message: \(error.localizedDescription)")
        }
    }

    public func cancelGeneration() async {
        cancellationRequested = true
        generationTask?.cancel()
        await inferenceEngine.cancelGeneration()

        if let assistantID = activeAssistantMessageID {
            do {
                try await messageRepository.markMessageCancelled(messageID: assistantID)
            } catch {
                setError("Failed to cancel generation cleanly: \(error.localizedDescription)")
            }
        }

        isGenerating = false
        generationPhase = .idle
        activeAssistantMessageID = nil
        activeGenerationInputTokens = nil
        activeContextUtilization = nil
        activeCompactionApplied = false
        if let sessionID = selectedSessionID {
            await loadMessages(for: sessionID)
        }
    }

    public func retryLastFailedPrompt() async {
        guard let prompt = lastFailedPrompt else { return }
        await sendPrompt(prompt)
    }

    public func reportUserFacingError(_ message: String) {
        setError(message)
    }

    public func clearError() {
        errorMessage = nil
    }

    public func toggleContextNoticeDetails() {
        guard contextNoticeDetails != nil else { return }
        isShowingContextNoticeDetails.toggle()
    }

    public func markdownTranscriptForSelectedSession() -> String? {
        guard !messages.isEmpty else { return nil }

        let fallbackTitle = "Chat Transcript"
        let sessionTitle = sessions.first(where: { $0.id == selectedSessionID })?.title ?? fallbackTitle
        let now = ISO8601DateFormatter().string(from: Date())

        var sections: [String] = [
            "# \(sessionTitle)",
            "_Exported: \(now)_"
        ]

        for message in messages {
            let roleHeading = message.role == .user ? "## User" : "## Assistant"
            let body = message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "_No content_"
                : message.content

            sections.append(roleHeading)
            sections.append(body)

            if message.status == .failed {
                sections.append("> Status: failed")
            } else if message.status == .cancelled {
                sections.append("> Status: cancelled")
            }
        }

        return sections.joined(separator: "\n\n")
    }

    private func preparePromptWithinBudget(
        sessionID: UUID,
        userInput: String
    ) async throws -> (prompt: String, budget: TokenBudgetResult, compactionApplied: Bool, notice: String?, noticeDetails: String?) {
        let contextWindow = await inferenceEngine.currentContextLimit()
        let policy = tokenPolicy(for: loadedModelName, contextWindow: contextWindow)

        var summary = rollingHistorySummaries[sessionID]
        var candidateMessages = messages.filter { $0.sessionID == sessionID && $0.status != .pending }
        let pinnedRecentCount = pinnedRecentMessageCount
        var compactionApplied = false

        while true {
            let prompt = composePrompt(
                summary: summary,
                history: candidateMessages,
                userInput: userInput
            )
            let estimatedTokens = try await inferenceEngine.estimateTokenCount(for: prompt)
            let budget = policy.evaluate(contextWindow: contextWindow, estimatedInputTokens: estimatedTokens)

            if budget.estimatedInputTokens <= budget.inputBudget {
                if let summary {
                    rollingHistorySummaries[sessionID] = summary
                }
                return (
                    prompt: prompt,
                    budget: budget,
                    compactionApplied: compactionApplied,
                    notice: contextNoticeText(for: budget, compactionApplied: compactionApplied),
                    noticeDetails: contextNoticeDetailText(for: budget, compactionApplied: compactionApplied)
                )
            }

            let compactableCount = max(0, candidateMessages.count - pinnedRecentCount)
            guard compactableCount > 1 else {
                throw IntraiError.contextLimitReached(
                    reason: "Context full. Start a new chat or shorten your message."
                )
            }

            let chunkCount = max(2, compactableCount / 3)
            let toCompact = Array(candidateMessages.prefix(chunkCount))
            let compactedSummary = summarize(messages: toCompact)
            summary = mergedSummary(existing: summary, addition: compactedSummary)
            candidateMessages.removeFirst(chunkCount)
            compactionApplied = true
        }
    }

    private func tokenPolicy(for modelName: String?, contextWindow: Int) -> TokenBudgetPolicy {
        let lowered = (modelName ?? "").lowercased()
        if lowered.contains("70b") || lowered.contains("34b") {
            return TokenBudgetPolicy(maxOutputTokens: 320, safetyMargin: 256)
        }
        if lowered.contains("14b") || lowered.contains("13b") {
            return TokenBudgetPolicy(maxOutputTokens: 384, safetyMargin: 224)
        }
        if contextWindow <= 2048 {
            return TokenBudgetPolicy(maxOutputTokens: 256, safetyMargin: 160)
        }
        return TokenBudgetPolicy()
    }

    private func composePrompt(summary: String?, history: [ChatMessageRecord], userInput: String) -> String {
        var sections: [String] = []

        sections.append("You are Intrai, a concise local assistant.")
        if let summary, !summary.isEmpty {
            sections.append("Conversation summary:\n\(summary)")
        }

        if !history.isEmpty {
            let renderedHistory = history.map { message in
                let role = message.role == .user ? "User" : "Assistant"
                return "\(role): \(message.content)"
            }.joined(separator: "\n")
            sections.append("Recent conversation:\n\(renderedHistory)")
        }

        sections.append("User: \(userInput)")
        sections.append("Assistant:")
        return sections.joined(separator: "\n\n")
    }

    private func summarize(messages: [ChatMessageRecord]) -> String {
        let lines = messages.map { message -> String in
            let role = message.role == .user ? "User" : "Assistant"
            let compact = message.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            let clipped = compact.count > 220 ? String(compact.prefix(220)) + "…" : compact
            return "- \(role): \(clipped)"
        }
        return lines.joined(separator: "\n")
    }

    private func mergedSummary(existing: String?, addition: String) -> String {
        guard let existing, !existing.isEmpty else { return addition }
        return existing + "\n" + addition
    }

    private func contextNoticeText(for budget: TokenBudgetResult, compactionApplied: Bool) -> String? {
        if compactionApplied {
            return "History compacted to preserve response quality"
        }
        switch budget.pressure {
        case .warning:
            return "Context near limit"
        case .compacting:
            return "Context high"
        case .blocked:
            return "Context full"
        case .normal:
            return nil
        }
    }

    private func contextNoticeDetailText(for budget: TokenBudgetResult, compactionApplied: Bool) -> String? {
        guard contextNoticeText(for: budget, compactionApplied: compactionApplied) != nil else {
            return nil
        }
        let percent = Int((budget.utilization * 100).rounded())
        let base = "\(budget.estimatedInputTokens)/\(budget.inputBudget) prompt tokens used (\(percent)%)."
        if compactionApplied {
            return base + " Older turns were summarized; recent turns remain verbatim."
        }
        return "\(budget.estimatedInputTokens)/\(budget.inputBudget) prompt tokens used (\(percent)%)."
    }

    private func ensureSessionID() async throws -> UUID {
        if let selectedSessionID {
            return selectedSessionID
        }

        let session = try await sessionRepository.createSession(title: nil)
        await refreshSessions()
        selectedSessionID = session.id
        return session.id
    }

    private func handleGenerationFailure(prompt: String, error: Error) async {
        if let assistantID = activeAssistantMessageID {
            do {
                try await messageRepository.markMessageFailed(
                    messageID: assistantID,
                    reason: error.localizedDescription
                )
            } catch {
                // Preserve original generation error signal if status write fails.
            }
        }

        self.lastFailedPrompt = prompt
        if let intraiError = error as? IntraiError {
            switch intraiError {
            case .contextLimitReached(let reason):
                self.setError("Generation stopped: \(reason)")
                self.contextFidelityState = .blocked
            default:
                self.setError("Generation failed: \(intraiError.localizedDescription)")
            }
            return
        }
        self.setError("Generation failed: \(error.localizedDescription)")
    }

    private func setError(_ message: String) {
        errorMessage = message
    }

    private func recordMetrics(
        startedAt: Date,
        finishedAt: Date,
        firstTokenAt: Date?,
        streamedCharacterCount: Int,
        wasCancelled: Bool,
        generationFailed: Bool,
        endReason: GenerationEndReason
    ) async {
        guard let promptID = activeGenerationPromptID, let sessionID = activeGenerationSessionID else {
            return
        }

        let generationDurationMs = finishedAt.timeIntervalSince(startedAt) * 1000
        let timeToFirstTokenMs = firstTokenAt.map { $0.timeIntervalSince(startedAt) * 1000 }

        let metrics = GenerationMetrics(
            promptID: promptID,
            sessionID: sessionID,
            startedAt: startedAt,
            timeToFirstTokenMs: timeToFirstTokenMs,
            generationDurationMs: generationDurationMs,
            streamedCharacterCount: streamedCharacterCount,
            inputTokenEstimate: activeGenerationInputTokens,
            contextUtilization: activeContextUtilization,
            compactionApplied: activeCompactionApplied,
            wasCancelled: wasCancelled,
            generationFailed: generationFailed,
            endReason: endReason
        )

        await metricsRecorder.recordGeneration(metrics)
        lastGenerationMetrics = metrics
        recentGenerationMetrics.append(metrics)
        if recentGenerationMetrics.count > recentMetricsWindowSize {
            recentGenerationMetrics.removeFirst(recentGenerationMetrics.count - recentMetricsWindowSize)
        }
        latestMonitoringHealth = classifyMonitoringHealth(from: metrics)
    }

    private func resolveEndReason(generationFailed: Bool, wasCancelled: Bool) -> GenerationEndReason {
        if wasCancelled {
            return .cancelled
        }
        if generationFailed {
            if let errorMessage, errorMessage.localizedCaseInsensitiveContains("context") {
                return .contextLimited
            }
            return .failed
        }
        return .completed
    }

    private func fidelityState(for budget: TokenBudgetResult, compactionApplied: Bool) -> ContextFidelityState {
        if compactionApplied {
            return .compactedSummaryActive
        }
        switch budget.pressure {
        case .warning:
            return .nearLimit
        case .blocked:
            return .blocked
        case .normal, .compacting:
            return .normal
        }
    }

    private func classifyMonitoringHealth(from metrics: GenerationMetrics) -> MonitoringHealthState {
        switch metrics.endReason {
        case .cancelled:
            return .cancelled
        case .failed:
            return .failed
        case .contextLimited:
            return .contextLimited
        case .completed:
            break
        }

        if metrics.compactionApplied {
            return .compacted
        }
        if let ttft = metrics.timeToFirstTokenMs, ttft > 2500 {
            return .slow
        }
        return .healthy
    }
}
