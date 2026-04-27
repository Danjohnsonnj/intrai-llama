//
//  intrai_llamacppTests.swift
//  intrai-llamacppTests
//
//  Created by Daniel Johnson on 4/26/26.
//

import Foundation
import Testing
@testable import intrai_llamacpp

@MainActor
struct intrai_llamacppTests {

    @Test func tokenBudgetPolicyMarksWarningAndBlockedThresholds() async throws {
        let policy = TokenBudgetPolicy(
            maxOutputTokens: 512,
            safetyMargin: 128,
            warningThreshold: 0.80,
            compactionThreshold: 0.90,
            blockThreshold: 0.98
        )

        let warning = policy.evaluate(contextWindow: 4096, estimatedInputTokens: 2_900)
        #expect(warning.pressure == .warning)

        let blocked = policy.evaluate(contextWindow: 4096, estimatedInputTokens: 3_500)
        #expect(blocked.pressure == .blocked)
    }

    @Test func tokenBudgetPolicyComputesInputBudgetFromContext() async throws {
        let policy = TokenBudgetPolicy(maxOutputTokens: 320, safetyMargin: 160)
        let result = policy.evaluate(contextWindow: 2048, estimatedInputTokens: 512)
        #expect(result.inputBudget == 1568)
        #expect(result.maxOutputTokens == 320)
        #expect(result.safetyMargin == 160)
    }

    @Test func tokenBudgetPolicyMarksCompactingAtThreshold() async throws {
        let policy = TokenBudgetPolicy(
            maxOutputTokens: 512,
            safetyMargin: 192,
            warningThreshold: 0.80,
            compactionThreshold: 0.90,
            blockThreshold: 0.98
        )

        let compacting = policy.evaluate(contextWindow: 4096, estimatedInputTokens: 3_050)
        #expect(compacting.pressure == .compacting)
    }

    @Test func generationMetricsTracksEndReason() async throws {
        let metrics = GenerationMetrics(
            promptID: UUID(),
            sessionID: UUID(),
            startedAt: Date(),
            timeToFirstTokenMs: 120,
            generationDurationMs: 1_600,
            streamedCharacterCount: 950,
            inputTokenEstimate: 880,
            contextUtilization: 0.91,
            compactionApplied: true,
            generationPath: .warm,
            preflightDurationMs: 15,
            promptAssemblyDurationMs: 4,
            tokenEvaluationDurationMs: 9,
            engineQueueDurationMs: 60,
            decodeToFirstChunkMs: 60,
            forcedRecapCompactionApplied: false,
            recapIntentMatched: false,
            preflightHistoryTruncatedForSafety: false,
            wasCancelled: false,
            generationFailed: false,
            endReason: .completed
        )

        #expect(metrics.endReason == GenerationEndReason.completed)
        #expect(metrics.compactionApplied)
        #expect(metrics.generationPath == .warm)
    }

    @Test func intraiErrorContextLimitMessageIsExposed() async throws {
        let error = IntraiError.contextLimitReached(reason: "Context full")
        #expect(error.localizedDescription == "Context full")
    }

    @Test func autoTitleFromFirstTurnUsesPrefixAndWordLimit() async throws {
        let title = ChatViewModel.autoTitleFromFirstTurn(
            userText: "Can you help me compare q4 and q6 quantization choices for speed?",
            assistantText: "",
            leadingPhrasePatterns: ["^can you\\s+", "^help me\\s+"],
            trimWords: ["for"]
        )
        #expect(title.hasPrefix("✦ "))
        let wordsAfterPrefix = title.replacingOccurrences(of: "✦ ", with: "").split(separator: " ")
        #expect(wordsAfterPrefix.count <= 5)
    }

    @Test func autoTitleFromFirstTurnFallsBackWhenInputIsEmpty() async throws {
        let title = ChatViewModel.autoTitleFromFirstTurn(
            userText: "",
            assistantText: ""
        )
        #expect(title == "✦ New chat")
    }

    @Test func autoRenameEligibilityOnlyAllowsDefaultTitle() async throws {
        #expect(ChatViewModel.isEligibleForAutoRename(sessionTitle: "New Chat"))
        #expect(!ChatViewModel.isEligibleForAutoRename(sessionTitle: "✦ previous summary"))
        #expect(!ChatViewModel.isEligibleForAutoRename(sessionTitle: "Custom topic"))
    }

}
