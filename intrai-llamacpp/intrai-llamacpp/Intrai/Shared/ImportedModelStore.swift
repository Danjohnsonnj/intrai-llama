import Foundation

/// Copies user-selected `.gguf` files into app-managed storage so inference can read
/// a stable path after the document picker's security scope ends.
public enum ImportedModelStore {
    /// Verifies the source file exists, is readable, and has non-zero size before copy or load.
    public static func preflightSource(at url: URL) throws {
        let path = url.path
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            throw IntraiError.modelLoadFailed(reason: "Model file not found.")
        }
        guard fm.isReadableFile(atPath: path) else {
            throw IntraiError.modelLoadFailed(
                reason: "Cannot read the model file. Try moving it to On My iPhone, then import again."
            )
        }
        let attributes = try fm.attributesOfItem(atPath: path)
        let size = attributes[.size] as? UInt64 ?? 0
        guard size > 0 else {
            throw IntraiError.modelLoadFailed(reason: "Model file is empty.")
        }
    }

    /// Copies `sourceURL` into Application Support/Models, replacing any existing file with the same name.
    public static func copyToAppModelsDirectory(from sourceURL: URL) throws -> URL {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw IntraiError.modelLoadFailed(reason: "Could not access app storage for models.")
        }
        let modelsDirectory = appSupport.appendingPathComponent("Models", isDirectory: true)
        try fm.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let fileName = sourceURL.lastPathComponent
        guard !fileName.isEmpty, fileName.lowercased().hasSuffix(".gguf") else {
            throw IntraiError.modelLoadFailed(reason: "Invalid model file name.")
        }

        let destinationURL = modelsDirectory.appendingPathComponent(fileName)
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try fm.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }
}
