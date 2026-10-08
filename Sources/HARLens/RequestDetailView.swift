import SwiftUI
import HARCore

struct RequestDetailView: View {
    let entry: HAREntry
    @Binding var tab: DetailTab

    enum DetailTab: String, CaseIterable {
        case overview = "Обзор", request = "Запрос", response = "Ответ", timing = "Время"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(entry.request.method).font(.system(size: 12, weight: .bold, design: .monospaced))
                    Text(entry.response.status == 0 ? "Сбой запроса" : "\(entry.response.status) \(entry.response.statusText ?? "")")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(statusColor(entry.response.status).opacity(0.09), in: Capsule())
                        .foregroundStyle(statusColor(entry.response.status))
                    Spacer()
                    Button { copy(entry.request.url) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).help("Скопировать URL")
                        .accessibilityLabel("Скопировать URL")
                }
                Text(entry.request.url).font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Picker("Подробности", selection: $tab) {
                    ForEach(DetailTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }.padding(18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch tab {
                    case .overview: overview
                    case .request: request
                    case .response: response
                    case .timing: timing
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("СВОДКА", symbol: "info.circle") {
                rows([
                    ("Метод", entry.request.method),
                    ("Статус", entry.response.status == 0 ? "Нет HTTP-ответа" : String(entry.response.status)),
                    ("Протокол", entry.response.httpVersion ?? entry.request.httpVersion ?? "—"),
                    ("Время", milliseconds(entry.time)),
                    ("Размер ответа", byteCount(entry.response.content?.size)),
                    ("Передано", byteCount(entry.response.transferSize ?? entry.response.bodySize)),
                    ("Тип содержимого", entry.response.content?.mimeType ?? "—"),
                    ("Начало", entry.startedDateTime ?? "—"),
                    ("IP сервера", entry.serverIPAddress ?? "—")
                ])
                if let redirect = entry.response.redirectURL, !redirect.isEmpty {
                    rows([("Перенаправление", redirect)])
                }
                if let comment = entry.comment, !comment.isEmpty {
                    Text(comment).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            fields("ЗАГОЛОВКИ ЗАПРОСА", entry.request.headers)
            fields("ЗАГОЛОВКИ ОТВЕТА", entry.response.headers)
        }
    }

    private var request: some View {
        VStack(alignment: .leading, spacing: 22) {
            fields("ЗАГОЛОВКИ", entry.request.headers)
            fields("ПАРАМЕТРЫ URL", entry.request.queryString)
            cookies(entry.request.cookies)
            if let post = entry.request.postData {
                if let params = post.params, !params.isEmpty {
                    section("ПАРАМЕТРЫ ФОРМЫ", symbol: "list.bullet.rectangle") {
                        rows(params.map { ($0.name, $0.value ?? $0.fileName ?? "—") })
                    }
                }
                bodySection(post.displayText, mimeType: post.mimeType)
            } else {
                bodySection("Тело запроса не сохранено в HAR.", mimeType: nil)
            }
        }
    }

    private var response: some View {
        VStack(alignment: .leading, spacing: 22) {
            fields("ЗАГОЛОВКИ", entry.response.headers)
            cookies(entry.response.cookies)
            bodySection(entry.response.content?.displayText ?? "Тело ответа не сохранено в HAR.",
                        mimeType: entry.response.content?.mimeType)
        }
    }

    private var timing: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("ВРЕМЯ ЗАПРОСА", symbol: "stopwatch") {
                Text(milliseconds(entry.time)).font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Длительность, записанная в HAR").font(.caption).foregroundStyle(.secondary)
            }
            section("ЭТАПЫ", symbol: "chart.bar.xaxis") {
                if let timings = entry.timings {
                    let phases: [(String, Double?, Color)] = [
                        ("Ожидание соединения", timings.blocked, .gray),
                        ("DNS", timings.dns, .purple),
                        ("Соединение", timings.connect, .orange),
                        ("Отправка", timings.send, .blue),
                        ("Ожидание ответа", timings.wait, .teal),
                        ("Получение", timings.receive, .green)
                    ]
                    let total = max(phases.reduce(0) { $0 + max(0, $1.1 ?? 0) }, 1)
                    ForEach(Array(phases.enumerated()), id: \.offset) { _, phase in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(phase.0).font(.callout)
                                Spacer()
                                Text(milliseconds(phase.1)).font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(phase.2.opacity(0.08))
                                    Capsule().fill(phase.2.opacity(0.7))
                                        .frame(width: geometry.size.width * min(max(0, phase.1 ?? 0) / total, 1))
                                }
                            }.frame(height: 6)
                        }.padding(.bottom, 8)
                    }
                    if let ssl = timings.ssl, ssl >= 0 {
                        rows([("TLS / SSL", milliseconds(ssl))])
                        Text("TLS / SSL входит во время соединения.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("«—» означает, что время этапа не записано.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Подробные тайминги не сохранены в HAR.").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func fields(_ title: String, _ fields: [HARField]?) -> some View {
        section(title, symbol: "list.bullet.rectangle") {
            if let fields, !fields.isEmpty {
                rows(fields.map { ($0.name, $0.value) })
            } else {
                Text("Нет сохранённых данных").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func cookies(_ cookies: [HARCookie]?) -> some View {
        section("COOKIES", symbol: "circle.grid.2x2") {
            if let cookies, !cookies.isEmpty {
                ForEach(Array(cookies.enumerated()), id: \.offset) { _, cookie in
                    VStack(alignment: .leading, spacing: 6) {
                        rows([(cookie.name, cookie.value)])
                        Text([cookie.domain, cookie.path, cookie.expires].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                        if cookie.httpOnly == true || cookie.secure == true {
                            Text([cookie.httpOnly == true ? "HttpOnly" : nil,
                                  cookie.secure == true ? "Secure" : nil].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
            } else { Text("Нет сохранённых cookies").font(.callout).foregroundStyle(.secondary) }
        }
    }

    private func bodySection(_ text: String, mimeType: String?) -> some View {
        section("ТЕЛО", symbol: "curlybraces") {
            HStack {
                Text(mimeType ?? "Содержимое HAR").font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button { copy(text) } label: { Label("Копировать", systemImage: "doc.on.doc") }
                    .controlSize(.small).help("Скопировать отображаемое тело")
            }
            ScrollView(.horizontal) {
                Text(text).font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled).fixedSize(horizontal: true, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func section<Content: View>(_ title: String, symbol: String,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rows(_ values: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.0).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    Text(row.1).font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
