import AppKit
import Combine
import HARCore
import UniformTypeIdentifiers

@MainActor
final class FileStore: ObservableObject {
    @Published private(set) var archive: HARArchive?
    @Published private(set) var fileURL: URL?
    @Published private(set) var recentURLs: [URL] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    private let defaults: UserDefaults
    private var loadTicket = UUID()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recentURLs = (defaults.stringArray(forKey: "recentFiles") ?? []).map { URL(fileURLWithPath: $0) }
    }

    @discardableResult
    func open(_ url: URL) -> Task<Void, Never> {
        let ticket = UUID()
        loadTicket = ticket
        isLoading = true
        errorMessage = nil
        let file = url.standardizedFileURL
        return Task {
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    guard file.isFileURL, file.pathExtension.lowercased() == "har" else {
                        throw FileOpenError.wrongType
                    }
                    let scoped = file.startAccessingSecurityScopedResource()
                    defer { if scoped { file.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: file, options: .mappedIfSafe)
                    return try HARArchive.decode(data)
                }.value
                // A slower previous load must never replace the file selected later.
                guard loadTicket == ticket else { return }
                archive = loaded
                fileURL = file
                recentURLs.removeAll { $0 == file }
                recentURLs.insert(file, at: 0)
                recentURLs = Array(recentURLs.prefix(20))
                defaults.set(recentURLs.map(\.path), forKey: "recentFiles")
            } catch {
                guard loadTicket == ticket else { return }
                let reason: String
                if error is DecodingError {
                    reason = "Файл повреждён или не соответствует формату HAR. В нём должен быть журнал log.entries с HTTP-запросами."
                } else {
                    reason = error.localizedDescription
                }
                errorMessage = "«\(file.lastPathComponent)»\n\(reason)"
            }
            isLoading = false
        }
    }

    func clearHistory() {
        recentURLs = []
        defaults.removeObject(forKey: "recentFiles")
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Открыть HTTP-архив"
        panel.message = "Выберите файл с расширением .har"
        panel.prompt = "Открыть"
        panel.allowedContentTypes = [UTType(importedAs: "com.marvix.harlens.archive")]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
}

private enum FileOpenError: LocalizedError {
    case wrongType
    var errorDescription: String? { "Выберите локальный файл с расширением .har." }
}
