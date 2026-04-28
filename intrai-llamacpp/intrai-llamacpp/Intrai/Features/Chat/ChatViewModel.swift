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
    private var activeGenerationPath: GenerationPath = .cold
    private var activePreflightDurationMs: Double?
    private var activePromptAssemblyDurationMs: Double?
    private var activeTokenEvaluationDurationMs: Double?
    private var activeEngineQueueDurationMs: Double?
    private var activeDecodeToFirstChunkMs: Double?
    private var activeForcedRecapCompactionApplied = false
    private var activeRecapIntentMatched = false
    private var activePreflightHistoryTruncatedForSafety = false
    private var autoRenamedSessionIDs: Set<UUID> = []
    private var rollingHistorySummaries: [UUID: String] = [:]
    private let recentMetricsWindowSize = 10
    private let pinnedRecentMessageCount = 12
    private let streamingFlushIntervalMs: Double = 80
    private let streamingFlushChunkThreshold = 48
    private let maxPreflightPromptChars = 64_000
    private let maxSummaryChars = 8_000
    private let maxHistoryCharsInPrompt = 28_000
    private let maxSingleMessageCharsInPrompt = 1_200
    private let maxCompactionIterations = 8
    private let streamingReloadIntervalMs: Double = 300
    private let forcedRecapTailMessageCount = 8
    private let forcedRecapPromptChars = 18_000
    private let forcedRecapMessageCountThreshold = 160
    private let forcedRecapHistoryCharsThreshold = 36_000
    private let recapIntentPhrases = [
        "summarize this chat",
        "what were we talking about",
        "where were we",
        "recap",
        "catch me up",
        "summarize our conversation"
    ]
    private let autoTitlePrefix = "✦ "
    private let autoTitleMaxWords = 10
    private let autoTitleLeadingPhrasePatterns = [
        "^can you\\s+",
        "^could you\\s+",
        "^would you\\s+",
        "^please\\s+",
        "^i need\\s+",
        "^help me\\s+",
        "^tell me\\s+",
        "^show me\\s+"
    ]
    private let autoTitleTrimWords: Set<String> = [
        "please", "thanks", "thank", "hey", "hi", "hello"
    ]
    private let adaptiveSlowSampleWindow = 8
    private let adaptiveSlowMinimumSamples = 3

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

    public func refreshSessions(autoSelectFirstIfNone: Bool = true) async {
        do {
            sessions = try await sessionRepository.listSessions()
            if let selected = selectedSessionID, !sessions.contains(where: { $0.id == selected }) {
                selectedSessionID = nil
                messages = []
            }
            if selectedSessionID == nil, autoSelectFirstIfNone {
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
            await refreshSessions(autoSelectFirstIfNone: false)
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
        guard !isGenerating else {
            setError("Generation already in progress. Cancel before sending a new message.")
            return
        }
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

            let preflightStartedAt = Date()
            let preflight = try await preparePromptWithinBudget(sessionID: sessionID, userInput: text)
            activePreflightDurationMs = Date().timeIntervalSince(preflightStartedAt) * 1000
            tokenBudgetResult = preflight.budget
            contextNotice = preflight.notice
            contextNoticeDetails = preflight.noticeDetails
            if messages.count > 400 {
                let largeThreadNote = "Large chat detected. Older history may be aggressively compacted for memory safety."
                if let contextNoticeDetails, !contextNoticeDetails.isEmpty {
                    self.contextNoticeDetails = contextNoticeDetails + " " + largeThreadNote
                } else {
                    self.contextNoticeDetails = largeThreadNote
                }
            }
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
            activePromptAssemblyDurationMs = preflight.promptAssemblyDurationMs
            activeTokenEvaluationDurationMs = preflight.tokenEvaluationDurationMs
            activeForcedRecapCompactionApplied = preflight.forcedRecapCompactionApplied
            activeRecapIntentMatched = preflight.recapIntentMatched
            activePreflightHistoryTruncatedForSafety = preflight.preflightHistoryTruncatedForSafety
            activeGenerationPath = await inferenceEngine.generationPathForNextRequest()
            activeEngineQueueDurationMs = nil
            activeDecodeToFirstChunkMs = nil
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
                var pendingAssistantBuffer = ""
                var lastBufferFlushAt = startedAt
                var lastMessagesReloadAt = startedAt

                do {
                    let decodeRequestAt = Date()
                    var streamedAssistantText = ""
                    for try await chunk in await self.inferenceEngine.generateStream(
                        prompt: preflight.prompt,
                        options: options
                    ) {
                        guard let assistantID = self.activeAssistantMessageID else {
                            continue
                        }
                        streamedAssistantText += chunk
                        pendingAssistantBuffer += chunk
                        streamedCharacterCount += chunk.count
                        if firstTokenAt == nil {
                            let firstChunkAt = Date()
                            firstTokenAt = firstChunkAt
                            self.generationPhase = .streaming
                            self.activeEngineQueueDurationMs = firstChunkAt.timeIntervalSince(decodeRequestAt) * 1000
                            self.activeDecodeToFirstChunkMs = firstChunkAt.timeIntervalSince(decodeRequestAt) * 1000
                        }
                        let elapsedMs = max(1, Date().timeIntervalSince(startedAt) * 1000)
                        let shouldFlush = pendingAssistantBuffer.count >= self.streamingFlushChunkThreshold ||
                            (elapsedMs - (lastBufferFlushAt.timeIntervalSince(startedAt) * 1000)) >= self.streamingFlushIntervalMs
                        if shouldFlush, !pendingAssistantBuffer.isEmpty {
                            try await self.messageRepository.appendAssistantChunk(
                                messageID: assistantID,
                                chunk: pendingAssistantBuffer
                            )
                            pendingAssistantBuffer = ""
                            lastBufferFlushAt = Date()
                            let reloadElapsedMs = Date().timeIntervalSince(lastMessagesReloadAt) * 1000
                            if reloadElapsedMs >= self.streamingReloadIntervalMs, let session = self.selectedSessionID {
                                await self.loadMessages(for: session)
                                lastMessagesReloadAt = Date()
                            }
                        }
                        self.liveGenerationSnapshot = GenerationMonitoringSnapshot(
                            phase: self.generationPhase,
                            elapsedMs: elapsedMs,
                            streamedCharacterCount: streamedCharacterCount,
                            approxCharsPerSecond: Double(streamedCharacterCount) / (elapsedMs / 1000)
                        )
                    }

                    if let assistantID = self.activeAssistantMessageID {
                        if !pendingAssistantBuffer.isEmpty {
                            try await self.messageRepository.appendAssistantChunk(
                                messageID: assistantID,
                                chunk: pendingAssistantBuffer
                            )
                            pendingAssistantBuffer = ""
                        }
                        try await self.messageRepository.markMessageComplete(messageID: assistantID)
                        try await self.attemptAutoRenameSessionAfterFirstCompletedTurn(
                            sessionID: sessionID,
                            userInput: text,
                            assistantOutput: streamedAssistantText
                        )
                    }
                } catch {
                    generationFailed = true
                    if Task.isCancelled {
                        wasCancelled = true
                    }
                    if let assistantID = self.activeAssistantMessageID, !pendingAssistantBuffer.isEmpty {
                        do {
                            try await self.messageRepository.appendAssistantChunk(
                                messageID: assistantID,
                                chunk: pendingAssistantBuffer
                            )
                        } catch {
                            // Keep the original generation error as the primary failure signal.
                        }
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
                self.activePreflightDurationMs = nil
                self.activePromptAssemblyDurationMs = nil
                self.activeTokenEvaluationDurationMs = nil
                self.activeEngineQueueDurationMs = nil
                self.activeDecodeToFirstChunkMs = nil
                self.activeForcedRecapCompactionApplied = false
                self.activeRecapIntentMatched = false
                self.activePreflightHistoryTruncatedForSafety = false
                self.activeGenerationPath = .cold

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
        guard isGenerating else {
            return
        }
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
        activePreflightDurationMs = nil
        activePromptAssemblyDurationMs = nil
        activeTokenEvaluationDurationMs = nil
        activeEngineQueueDurationMs = nil
        activeDecodeToFirstChunkMs = nil
        activeForcedRecapCompactionApplied = false
        activeRecapIntentMatched = false
        activePreflightHistoryTruncatedForSafety = false
        activeGenerationPath = .cold
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
    ) async throws -> (
        prompt: String,
        budget: TokenBudgetResult,
        compactionApplied: Bool,
        notice: String?,
        noticeDetails: String?,
        promptAssemblyDurationMs: Double,
        tokenEvaluationDurationMs: Double,
        forcedRecapCompactionApplied: Bool,
        recapIntentMatched: Bool,
        preflightHistoryTruncatedForSafety: Bool
    ) {
        let contextWindow = await inferenceEngine.currentContextLimit()
        let policy = tokenPolicy(for: loadedModelName, contextWindow: contextWindow)

        var summary = rollingHistorySummaries[sessionID]
        var candidateMessages = messages.filter { $0.sessionID == sessionID && $0.status != .pending }
        let pinnedRecentCount = pinnedRecentMessageCount
        var compactionApplied = false
        var compactionIteration = 0
        var promptAssemblyDurationMs: Double = 0
        var tokenEvaluationDurationMs: Double = 0
        let recapIntentMatched = matchesRecapIntent(userInput)
        let forcedRecapCompactionApplied = shouldForceRecapCompaction(
            userInput: userInput,
            candidateMessages: candidateMessages
        )
        var preflightHistoryTruncatedForSafety = false

        if forcedRecapCompactionApplied {
            let promptAssemblyStart = Date()
            let recapPromptResult = composeRecapSafetyPrompt(
                summary: summary,
                history: candidateMessages,
                userInput: userInput
            )
            let prompt = recapPromptResult.prompt
            preflightHistoryTruncatedForSafety = recapPromptResult.historyTruncatedForSafety
            promptAssemblyDurationMs += Date().timeIntervalSince(promptAssemblyStart) * 1000
            if prompt.count > maxPreflightPromptChars {
                throw IntraiError.contextLimitReached(
                    reason: "Context still too large for recap. Start a new chat or summarize the latest turns."
                )
            }
            let tokenEvalStart = Date()
            let estimatedTokens = try await inferenceEngine.estimateTokenCount(for: prompt)
            tokenEvaluationDurationMs += Date().timeIntervalSince(tokenEvalStart) * 1000
            let budget = policy.evaluate(contextWindow: contextWindow, estimatedInputTokens: estimatedTokens)
            if budget.estimatedInputTokens > budget.inputBudget {
                throw IntraiError.contextLimitReached(
                    reason: "Context still too large for recap. Start a new chat or summarize the latest turns."
                )
            }
            return (
                prompt: prompt,
                budget: budget,
                compactionApplied: true,
                notice: "History compacted for recap stability",
                noticeDetails: "Older turns were aggressively compacted to prevent memory pressure while generating a recap.",
                promptAssemblyDurationMs: promptAssemblyDurationMs,
                tokenEvaluationDurationMs: tokenEvaluationDurationMs,
                forcedRecapCompactionApplied: true,
                recapIntentMatched: recapIntentMatched,
                preflightHistoryTruncatedForSafety: preflightHistoryTruncatedForSafety
            )
        }

        while true {
            compactionIteration += 1
            if compactionIteration > maxCompactionIterations {
                throw IntraiError.contextLimitReached(
                    reason: "Context full after compaction attempts. Start a new chat or shorten your message."
                )
            }
            let promptAssemblyStart = Date()
            let prompt = composePrompt(
                summary: summary,
                history: candidateMessages,
                userInput: userInput
            )
            promptAssemblyDurationMs += Date().timeIntervalSince(promptAssemblyStart) * 1000
            if prompt.count > maxPreflightPromptChars {
                let compactableCount = max(0, candidateMessages.count - pinnedRecentCount)
                guard compactableCount > 1 else {
                    throw IntraiError.contextLimitReached(
                        reason: "Context full after compaction attempts. Start a new chat or shorten your message."
                    )
                }
                let chunkCount = max(4, compactableCount / 2)
                let toCompact = Array(candidateMessages.prefix(chunkCount))
                let compactedSummary = summarize(messages: toCompact)
                summary = mergedSummary(existing: summary, addition: compactedSummary)
                if let summary {
                    self.rollingHistorySummaries[sessionID] = String(summary.suffix(maxSummaryChars))
                }
                candidateMessages.removeFirst(chunkCount)
                compactionApplied = true
                continue
            }
            let tokenEvalStart = Date()
            let estimatedTokens = try await inferenceEngine.estimateTokenCount(for: prompt)
            tokenEvaluationDurationMs += Date().timeIntervalSince(tokenEvalStart) * 1000
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
                    noticeDetails: contextNoticeDetailText(for: budget, compactionApplied: compactionApplied),
                    promptAssemblyDurationMs: promptAssemblyDurationMs,
                    tokenEvaluationDurationMs: tokenEvaluationDurationMs,
                    forcedRecapCompactionApplied: false,
                    recapIntentMatched: recapIntentMatched,
                    preflightHistoryTruncatedForSafety: preflightHistoryTruncatedForSafety
                )
            }

            let compactableCount = max(0, candidateMessages.count - pinnedRecentCount)
            guard compactableCount > 1 else {
                throw IntraiError.contextLimitReached(
                    reason: "Context full. Start a new chat or shorten your message."
                )
            }

            let chunkCount = prompt.count > 48_000
                ? max(4, compactableCount / 2)
                : max(2, compactableCount / 3)
            let toCompact = Array(candidateMessages.prefix(chunkCount))
            let compactedSummary = summarize(messages: toCompact)
            summary = mergedSummary(existing: summary, addition: compactedSummary)
            if let summary {
                self.rollingHistorySummaries[sessionID] = String(summary.suffix(maxSummaryChars))
            }
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

    private func normalizedPrompt(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchesRecapIntent(_ userInput: String) -> Bool {
        let normalized = normalizedPrompt(userInput)
        return recapIntentPhrases.contains(where: { normalized.contains($0) })
    }

    private func shouldForceRecapCompaction(userInput: String, candidateMessages: [ChatMessageRecord]) -> Bool {
        if matchesRecapIntent(userInput) {
            return true
        }
        if candidateMessages.count >= forcedRecapMessageCountThreshold {
            return true
        }
        let aggregateChars = candidateMessages.reduce(0) { partial, message in
            partial + message.content.count
        }
        return aggregateChars >= forcedRecapHistoryCharsThreshold
    }

    private func composeRecapSafetyPrompt(
        summary: String?,
        history: [ChatMessageRecord],
        userInput: String
    ) -> (prompt: String, historyTruncatedForSafety: Bool) {
        let boundedSummary = summary.map { String($0.suffix(maxSummaryChars)) }
        let tailMessages = Array(history.suffix(forcedRecapTailMessageCount))
        var sections: [String] = ["You are Intrai, a concise local assistant."]
        if let boundedSummary, !boundedSummary.isEmpty {
            sections.append("Conversation summary:\n\(boundedSummary)")
        }
        if !tailMessages.isEmpty {
            var lines = ["[Earlier conversation omitted for recap stability]"]
            lines.append(contentsOf: tailMessages.map { message in
                let role = message.role == .user ? "User" : "Assistant"
                let compact = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let clipped = compact.count > maxSingleMessageCharsInPrompt
                    ? String(compact.prefix(maxSingleMessageCharsInPrompt))
                    : compact
                return "\(role): \(clipped)"
            })
            sections.append("Recent conversation:\n\(lines.joined(separator: "\n"))")
        }
        sections.append("User: \(userInput)")
        sections.append("Assistant:")
        let prompt = sections.joined(separator: "\n\n")
        let boundedPrompt = prompt.count > forcedRecapPromptChars
            ? String(prompt.suffix(forcedRecapPromptChars))
            : prompt
        let truncated = tailMessages.count < history.count || boundedPrompt.count < prompt.count
        return (boundedPrompt, truncated)
    }

    private func composePrompt(summary: String?, history: [ChatMessageRecord], userInput: String) -> String {
        var sections: [String] = []

        sections.append("You are Intrai, a concise local assistant.")
        if let summary, !summary.isEmpty {
            sections.append("Conversation summary:\n\(String(summary.suffix(maxSummaryChars)))")
        }

        if !history.isEmpty {
            var selectedHistory: [(role: MessageRole, content: String)] = []
            var historyChars = 0
            for message in history.reversed() {
                let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let clipped = trimmed.count > maxSingleMessageCharsInPrompt
                    ? String(trimmed.prefix(maxSingleMessageCharsInPrompt))
                    : trimmed
                let entryLength = clipped.count + 16
                if historyChars + entryLength > maxHistoryCharsInPrompt {
                    break
                }
                historyChars += entryLength
                selectedHistory.append((role: message.role, content: clipped))
            }
            selectedHistory.reverse()

            var renderedHistoryLines: [String] = []
            if selectedHistory.count < history.count {
                renderedHistoryLines.append("[Earlier conversation omitted for memory safety]")
            }
            let renderedHistory = selectedHistory.map { entry in
                let role = entry.role == .user ? "User" : "Assistant"
                return "\(role): \(entry.content)"
            }
            renderedHistoryLines.append(contentsOf: renderedHistory)
            sections.append("Recent conversation:\n\(renderedHistoryLines.joined(separator: "\n"))")
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
            let clipped = compact.count > 160 ? String(compact.prefix(160)) + "…" : compact
            return "- \(role): \(clipped)"
        }
        return String(lines.joined(separator: "\n").suffix(maxSummaryChars / 2))
    }

    private func mergedSummary(existing: String?, addition: String) -> String {
        let merged: String
        if let existing, !existing.isEmpty {
            merged = existing + "\n" + addition
        } else {
            merged = addition
        }
        return String(merged.suffix(maxSummaryChars))
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

    private func attemptAutoRenameSessionAfterFirstCompletedTurn(
        sessionID: UUID,
        userInput: String,
        assistantOutput: String
    ) async throws {
        guard !autoRenamedSessionIDs.contains(sessionID) else { return }
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        guard Self.isEligibleForAutoRename(sessionTitle: session.title) else { return }

        let sessionMessages = try await messageRepository.listMessages(sessionID: sessionID)
        let completedUserCount = sessionMessages.filter { $0.role == .user && $0.status == .complete }.count
        let completedAssistantCount = sessionMessages.filter { $0.role == .assistant && $0.status == .complete }.count
        guard completedUserCount == 1, completedAssistantCount == 1 else { return }

        let autoTitle = Self.autoTitleFromFirstTurn(
            userText: userInput,
            assistantText: assistantOutput,
            prefix: autoTitlePrefix,
            maxWords: autoTitleMaxWords,
            leadingPhrasePatterns: autoTitleLeadingPhrasePatterns,
            trimWords: autoTitleTrimWords
        )
        guard autoTitle != session.title else {
            autoRenamedSessionIDs.insert(sessionID)
            return
        }
        try await sessionRepository.renameSession(id: sessionID, title: autoTitle)
        autoRenamedSessionIDs.insert(sessionID)
    }

    static func isEligibleForAutoRename(sessionTitle: String) -> Bool {
        let normalized = sessionTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized == "new chat"
    }

    static func autoTitleFromFirstTurn(
        userText: String,
        assistantText: String,
        prefix: String = "✦ ",
        maxWords: Int = 5,
        leadingPhrasePatterns: [String] = [],
        trimWords: Set<String> = []
    ) -> String {
        let primaryWords = cleanedTitleWords(
            from: userText,
            leadingPhrasePatterns: leadingPhrasePatterns,
            trimWords: trimWords
        )
        let fallbackWords = cleanedTitleWords(
            from: assistantText,
            leadingPhrasePatterns: leadingPhrasePatterns,
            trimWords: trimWords
        )
        let sourceWords = primaryWords.count >= 2 ? primaryWords : (primaryWords + fallbackWords)
        let limitedWords = Array(sourceWords.prefix(max(1, maxWords)))
        if limitedWords.isEmpty {
            return prefix + "New chat"
        }
        return prefix + naturalizeTitleWords(limitedWords)
    }

    private static func cleanedTitleWords(
        from text: String,
        leadingPhrasePatterns: [String],
        trimWords: Set<String>
    ) -> [String] {
        var normalized = text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9'\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in leadingPhrasePatterns {
            normalized = normalized.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        guard !normalized.isEmpty else { return [] }
        var words = normalized.split(separator: " ").map(String.init)
        while let first = words.first, trimWords.contains(first) {
            words.removeFirst()
        }
        while let last = words.last, trimWords.contains(last) {
            words.removeLast()
        }
        return words.filter { !$0.isEmpty }
    }

    private static func naturalizeTitleWords(_ words: [String]) -> String {
        guard !words.isEmpty else { return "New chat" }
        let sentence = words.joined(separator: " ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
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
        let loweredMessage = error.localizedDescription.lowercased()
        if loweredMessage.contains("memory") || loweredMessage.contains("terminated") {
            self.setError("Generation stopped due to memory pressure. Try summarizing the last 10 turns or start a new chat.")
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
            generationPath: activeGenerationPath,
            preflightDurationMs: activePreflightDurationMs,
            promptAssemblyDurationMs: activePromptAssemblyDurationMs,
            tokenEvaluationDurationMs: activeTokenEvaluationDurationMs,
            engineQueueDurationMs: activeEngineQueueDurationMs,
            decodeToFirstChunkMs: activeDecodeToFirstChunkMs,
            forcedRecapCompactionApplied: activeForcedRecapCompactionApplied,
            recapIntentMatched: activeRecapIntentMatched,
            preflightHistoryTruncatedForSafety: activePreflightHistoryTruncatedForSafety,
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
        if let ttft = metrics.timeToFirstTokenMs, ttft > slowThresholdMs(for: metrics) {
            return .slow
        }
        return .healthy
    }

    private func slowThresholdMs(for metrics: GenerationMetrics) -> Double {
        let fallbackThresholdMs = metrics.generationPath == .cold ? 3500.0 : 2500.0
        let warmCompletions = recentGenerationMetrics
            .filter { $0.endReason == .completed && $0.generationPath == .warm }
            .suffix(adaptiveSlowSampleWindow)
        guard warmCompletions.count >= adaptiveSlowMinimumSamples else {
            return fallbackThresholdMs
        }
        let warmTTFTSamples = warmCompletions.compactMap(\.timeToFirstTokenMs).sorted()
        guard !warmTTFTSamples.isEmpty else {
            return fallbackThresholdMs
        }
        let p90Index = Int(Double(warmTTFTSamples.count - 1) * 0.9)
        let p90 = warmTTFTSamples[p90Index]
        return max(fallbackThresholdMs, p90 * 1.15)
    }
}
