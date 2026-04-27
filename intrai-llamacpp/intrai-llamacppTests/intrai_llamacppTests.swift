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
            wasCancelled: false,
            generationFailed: false,
            endReason: .completed
        )

        #expect(metrics.endReason == GenerationEndReason.completed)
        #expect(metrics.compactionApplied)
    }

    @Test func intraiErrorContextLimitMessageIsExposed() async throws {
        let error = IntraiError.contextLimitReached(reason: "Context full")
        #expect(error.localizedDescription == "Context full")
    }

}
