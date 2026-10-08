import SwiftUI
import UniformTypeIdentifiers
import HARCore

enum RequestFilter: String, CaseIterable {
    case all = "Все", errors = "Ошибки", success = "Успешные"

    func includes(_ entry: HAREntry) -> Bool {
        switch self {
        case .all: return true
        case .errors: return entry.response.status == 0 || entry.response.status >= 400
        case .success: return (200..<400).contains(entry.response.status)
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: FileStore
    @State private var search = ""
    @State private var filter: RequestFilter = .all
    @State private var selection: UUID?
    @State private var isDropTarget = false
    @State private var detailTab = RequestDetailView.DetailTab.overview
    @AppStorage("sidebarCompact") private var isSidebarCompact = false
    private let accent = Color(red: 0.06, green: 0.55, blue: 0.58)

    private var entries: [HAREntry] { store.archive?.entries ?? [] }
    private var filteredEntries: [HAREntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            filter.includes(entry) && (query.isEmpty ||
                entry.request.url.localizedCaseInsensitiveContains(query) ||
                entry.request.method.localizedCaseInsensitiveContains(query) ||
                String(entry.response.status).contains(query) ||
                (entry.response.content?.mimeType ?? "").localizedCaseInsensitiveContains(query))
        }
    }
    private var selectedEntry: HAREntry? { entries.first { $0.id == selection } }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                toolbar
                Divider()
                if store.archive != nil {
                    workspace
                } else {
                    welcome
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 12).strokeBorder(accent, lineWidth: 3)
                    .padding(6).allowsHitTesting(false)
            }
            if store.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Читаем HAR-файл…").font(.headline)
                }
                .padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget, perform: acceptDrop)
        .alert("Не удалось открыть файл", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onReceive(store.$archive) { archive in
            search = ""
            filter = .all
            selection = archive?.entries.first?.id
        }
        .onChange(of: search) { _ in updateSelection() }
        .onChange(of: filter) { _ in updateSelection() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 29)).foregroundStyle(accent)
                if !isSidebarCompact {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HAR Lens").font(.system(size: 19, weight: .bold, design: .rounded))
                        Text("Сеть в деталях").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 8)

            Button(action: store.chooseFile) {
                if isSidebarCompact {
                    Image(systemName: "folder.badge.plus").frame(maxWidth: .infinity)
                } else {
                    Label("Открыть HAR", systemImage: "folder.badge.plus").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .help("Выбрать HAR-файл (⌘O)")
            .accessibilityLabel("Открыть HAR")

            if let url = store.fileURL {
                VStack(alignment: .leading, spacing: 8) {
                    if isSidebarCompact {
                        Image(systemName: "doc.text").foregroundStyle(accent)
                            .accessibilityLabel("Открыт \(url.lastPathComponent)")
                    } else {
                        Label("ОТКРЫТ СЕЙЧАС", systemImage: "doc.text")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        Text(url.lastPathComponent).font(.headline).lineLimit(2)
                        Text("\(entries.count) запросов").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(isSidebarCompact ? 9 : 12)
                .frame(maxWidth: .infinity, alignment: isSidebarCompact ? .center : .leading)
                .help(url.path)
                .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .contextMenu {
                    Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }

            HStack {
                if !isSidebarCompact {
                    Text("НЕДАВНИЕ ФАЙЛЫ").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                if !store.recentURLs.isEmpty {
                    Button { store.clearHistory() } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Очистить историю файлов")
                        .accessibilityLabel("Очистить историю файлов")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    if store.recentURLs.isEmpty {
                        if isSidebarCompact {
                            Image(systemName: "clock").foregroundStyle(.secondary)
                                .help("Здесь появятся открытые файлы")
                        } else {
                            Text("Здесь появятся открытые файлы")
                                .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                    }
                    ForEach(store.recentURLs, id: \.path) { url in
                        Button { store.open(url) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "doc.text").foregroundStyle(accent)
                                if !isSidebarCompact {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                            .font(.system(size: 12, weight: .medium))
                                        Text(url.deletingLastPathComponent().lastPathComponent)
                                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            .padding(9).frame(maxWidth: .infinity, alignment: isSidebarCompact ? .center : .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help(url.path)
                        .accessibilityLabel("Открыть \(url.lastPathComponent)")
                        .background(store.fileURL == url ? accent.opacity(0.08) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            Spacer(minLength: 0)
            if isSidebarCompact {
                Image(systemName: "lock.shield").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).help("Всё остаётся на вашем Mac")
            } else {
                Label("Всё остаётся на вашем Mac", systemImage: "lock.shield")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(isSidebarCompact ? 10 : 16).frame(width: isSidebarCompact ? 60 : 196)
        .background(.ultraThinMaterial)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button { isSidebarCompact.toggle() } label: { Image(systemName: "sidebar.left") }
                .help(isSidebarCompact ? "Развернуть боковую панель" : "Свернуть боковую панель")
                .accessibilityLabel(isSidebarCompact ? "Развернуть боковую панель" : "Свернуть боковую панель")
            VStack(alignment: .leading, spacing: 3) {
                Text(store.fileURL?.lastPathComponent ?? "Добро пожаловать")
                    .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(store.fileURL == nil ? "Понятный просмотр HTTP-архивов" : "HTTP-архив · только чтение")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                if store.recentURLs.isEmpty { Text("Нет недавних файлов") }
                ForEach(store.recentURLs, id: \.path) { url in
                    Button(url.lastPathComponent) { store.open(url) }
                }
            } label: { Image(systemName: "clock.arrow.circlepath") }
                .menuStyle(.borderlessButton).fixedSize().help("Недавние файлы")
                .accessibilityLabel("Недавние файлы")
            Button(action: store.chooseFile) { Label("Открыть", systemImage: "folder") }
                .controlSize(.large)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(accent.opacity(0.10)).frame(width: 104, height: 104)
                Image(systemName: "waveform.path.ecg").font(.system(size: 46, weight: .light))
                    .foregroundStyle(accent)
            }
            VStack(spacing: 10) {
                Text("Посмотрите, что происходит в сети")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("Откройте HAR-файл, чтобы изучить запросы,\nответы и время загрузки.")
                    .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button("Выбрать HAR-файл", action: store.chooseFile)
                .buttonStyle(.borderedProminent).controlSize(.large)
            Label("Или перетащите файл .har в это окно", systemImage: "arrow.down.doc")
                .foregroundStyle(.secondary).font(.callout)
            Spacer()
            HStack(spacing: 34) {
                welcomeFeature("Запросы и ответы", "arrow.left.arrow.right")
                welcomeFeature("Время загрузки", "stopwatch")
                welcomeFeature("Работает офлайн", "lock.shield")
            }
            .padding(.bottom, 35)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(28)
    }

    private func welcomeFeature(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                metric("Запросов", "\(entries.count)", "arrow.left.arrow.right", accent)
                metric("Ошибок", "\(entries.filter { RequestFilter.errors.includes($0) }.count)",
                       "exclamationmark.circle", .orange)
                metric("Размер ответов", byteCount(totalResponseBytes(entries)),
                       "tray.and.arrow.down", .blue)
            }
            .padding(18)
            HSplitView {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Поиск URL, метода, статуса…", text: $search)
                            .textFieldStyle(.plain).accessibilityLabel("Поиск запросов")
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                                .accessibilityLabel("Очистить поиск")
                        }
                    }
                    .padding(9).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 14).padding(.top, 12)
                    HStack {
                        Picker("Показать", selection: $filter) {
                            ForEach(RequestFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented).frame(maxWidth: 280)
                        Spacer()
                        Text("\(filteredEntries.count) из \(entries.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(14)
                    requestTable
                }
                .frame(minWidth: 420, idealWidth: 610)
                VStack(spacing: 0) {
                    if let entry = selectedEntry {
                        RequestDetailView(entry: entry, tab: $detailTab)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "cursorarrow.click.2").font(.largeTitle).foregroundStyle(.tertiary)
                            Text("Выберите запрос").font(.headline)
                            Text("Его подробности появятся здесь").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 330, idealWidth: 390)
            }
            Divider()
            HStack {
                Label("Локальный файл", systemImage: "internaldrive")
                Spacer()
                Text("⌘O — открыть файл · Перетащите HAR в окно")
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 9)
        }
    }

    private var requestTable: some View {
        Table(filteredEntries, selection: $selection) {
            TableColumn("Метод") { entry in
                Text(entry.request.method).font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(entry.request.method == "GET" ? accent : .indigo)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background((entry.request.method == "GET" ? accent : .indigo).opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 4))
            }.width(60)
            TableColumn("Запрос") { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(requestPath(entry.request.url)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(URL(string: entry.request.url)?.host ?? entry.request.url)
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }.padding(.vertical, 4).help(entry.request.url)
            }.width(min: 145, ideal: 235)
            TableColumn("Статус") { entry in
                Text(entry.response.status == 0 ? "Сбой" : String(entry.response.status))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(statusColor(entry.response.status))
            }.width(52)
            TableColumn("Время") { entry in
                Text(milliseconds(entry.time)).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }.width(76)
        }
        .overlay {
            if filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: entries.isEmpty ? "tray" : "magnifyingglass").font(.title2)
                    Text(entries.isEmpty ? "В этом архиве нет запросов" : "Ничего не найдено").font(.headline)
                    if !entries.isEmpty { Text("Измените поиск или фильтр").font(.caption) }
                }.foregroundStyle(.secondary).allowsHitTesting(false)
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(color)
                .frame(width: 36, height: 36).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(value).font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
    }

    private func updateSelection() {
        if !filteredEntries.contains(where: { $0.id == selection }) { selection = filteredEntries.first?.id }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else if let value = item as? URL { url = value }
            else { url = nil }
            Task { @MainActor in
                if let url { store.open(url) }
                else { store.errorMessage = "Не удалось получить файл. Выберите его через «Открыть»." }
            }
        }
        return true
    }
}

func milliseconds(_ value: Double?) -> String {
    guard let value, value >= 0, value.isFinite else { return "—" }
    return value >= 1000 ? String(format: "%.2f с", value / 1000) : String(format: "%.0f мс", value)
}

func totalResponseBytes(_ entries: [HAREntry]) -> Int? {
    var total = 0
    for entry in entries {
        let size = max(0, entry.response.content?.size ?? 0)
        let addition = total.addingReportingOverflow(size)
        guard !addition.overflow else { return nil }
        total = addition.partialValue
    }
    return total
}

func byteCount(_ value: Int?) -> String {
    guard let value, value >= 0 else { return "—" }
    return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
}

func statusColor(_ value: Int) -> Color {
    if value == 0 || value >= 400 { return .red }
    if value >= 300 { return .orange }
    return Color(red: 0.06, green: 0.55, blue: 0.40)
}

private func requestPath(_ string: String) -> String {
    guard let url = URLComponents(string: string) else { return string }
    let path = url.percentEncodedPath.isEmpty ? "/" : url.percentEncodedPath
    return path + (url.percentEncodedQuery.map { "?" + $0 } ?? "")
}
