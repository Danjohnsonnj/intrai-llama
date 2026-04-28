import Foundation

/// UserDefaults persistence for the global system prompt and freeform user memory (v1).
public enum GlobalPromptSettingsStore {
    public static let defaultSystemPrompt = "You are Intrai, a concise local assistant."

    /// Maximum characters stored and injected per field (independent of the rest of the preflight budget).
    public static let maxSystemPromptChars = 8_000
    public static let maxUserMemoryChars = 12_000

    private static let systemPromptKey = "intrai.globalSystemPrompt"
    private static let userMemoryKey = "intrai.userMemory"

    public static func load(defaults: UserDefaults = .standard) -> (systemPrompt: String, userMemory: String) {
        let system: String
        if defaults.object(forKey: systemPromptKey) == nil {
            system = defaultSystemPrompt
        } else {
            system = clampedSystemPrompt(defaults.string(forKey: systemPromptKey) ?? "")
        }
        let memory: String
        if defaults.object(forKey: userMemoryKey) == nil {
            memory = ""
        } else {
            memory = clampedUserMemoryString(defaults.string(forKey: userMemoryKey) ?? "")
        }
        return (system, memory)
    }

    public static func save(systemPrompt: String, userMemory: String, defaults: UserDefaults = .standard) {
        let s = clampedSystemPrompt(systemPrompt)
        let m = clampedUserMemoryString(userMemory)
        defaults.set(s, forKey: systemPromptKey)
        defaults.set(m, forKey: userMemoryKey)
    }

    public static func clampedSystemPrompt(_ text: String) -> String {
        String(text.prefix(maxSystemPromptChars))
    }

    /// Trims, clamps length; use for storage and for prompt assembly.
    public static func clampedUserMemoryString(_ text: String) -> String {
        String(text.prefix(maxUserMemoryChars))
    }

    /// The system instruction block for the model. Empty or whitespace-only stored value resolves to the default.
    public static func effectiveSystemPromptForPrompt(stored: String) -> String {
        let t = String(stored.prefix(maxSystemPromptChars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            return defaultSystemPrompt
        }
        return t
    }

    /// Non-empty, clamped `User memory:` body, or `nil` to omit the section.
    public static func userMemoryBodyForPromptIfAny(stored: String) -> String? {
        let t = String(stored.prefix(maxUserMemoryChars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Top sections for prompt assembly, in order: system line(s), then optional `User memory:` block.
    public static func promptLeadSections(storedSystemPrompt: String, storedUserMemory: String) -> [String] {
        let system = effectiveSystemPromptForPrompt(stored: storedSystemPrompt)
        var parts: [String] = [system]
        if let mem = userMemoryBodyForPromptIfAny(stored: storedUserMemory) {
            parts.append("User memory:\n\(mem)")
        }
        return parts
    }
}
