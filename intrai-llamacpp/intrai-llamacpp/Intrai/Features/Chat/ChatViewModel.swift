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
    public private(set) var modelLoaded = false
    public private(set) var loadedModelName: String?
    public private(set) var errorMessage: String?
    public private(set) var lastFailedPrompt: String?
    public private(set) var lastGenerationMetrics: GenerationMetrics?

    private var generationTask: Task<Void, Never>?
    private var activeAssistantMessageID: UUID?
    private var activeGenerationPromptID: UUID?
    private var activeGenerationSessionID: UUID?
    private var cancellationRequested = false

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

        do {
            try ImportedModelStore.preflightSource(at: pickedModelURL)
            let localModelURL = try ImportedModelStore.copyToAppModelsDirectory(from: pickedModelURL)
            try await inferenceEngine.loadModel(from: localModelURL)
            modelLoaded = true
            loadedModelName = localModelURL.lastPathComponent
            clearError()
        } catch let error as IntraiError {
            modelLoaded = false
            setError("Failed to load model: \(error.localizedDescription)")
        } catch {
            modelLoaded = false
            setError("Failed to load model: \(error.localizedDescription)")
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

        do {
            let sessionID = try await ensureSessionID()
            let userMessage = try await messageRepository.appendUserMessage(sessionID: sessionID, content: text)
            let assistantMessage = try await messageRepository.appendAssistantPlaceholder(sessionID: sessionID)
            activeAssistantMessageID = assistantMessage.id
            activeGenerationPromptID = userMessage.id
            activeGenerationSessionID = sessionID

            await loadMessages(for: sessionID)
            clearError()
            isGenerating = true
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
                        prompt: text,
                        options: GenerationOptions()
                    ) {
                        guard let assistantID = self.activeAssistantMessageID else {
                            continue
                        }
                        try await self.messageRepository.appendAssistantChunk(messageID: assistantID, chunk: chunk)
                        streamedCharacterCount += chunk.count
                        if firstTokenAt == nil {
                            firstTokenAt = Date()
                        }
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
                await self.recordMetrics(
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    firstTokenAt: firstTokenAt,
                    streamedCharacterCount: streamedCharacterCount,
                    wasCancelled: wasCancelled,
                    generationFailed: generationFailed
                )

                self.isGenerating = false
                self.generationTask = nil
                self.activeAssistantMessageID = nil
                self.activeGenerationPromptID = nil
                self.activeGenerationSessionID = nil
                self.cancellationRequested = false

                if let session = self.selectedSessionID {
                    await self.loadMessages(for: session)
                    await self.refreshSessions()
                }
            }
        } catch {
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
        activeAssistantMessageID = nil
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
        generationFailed: Bool
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
            wasCancelled: wasCancelled,
            generationFailed: generationFailed
        )

        await metricsRecorder.recordGeneration(metrics)
        lastGenerationMetrics = metrics
    }
}
