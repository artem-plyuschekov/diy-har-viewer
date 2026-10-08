import Foundation

public struct HARArchive: Decodable, Sendable {
    private let log: HARLog
    public var entries: [HAREntry] { log.entries }

    public static func decode(_ data: Data) throws -> HARArchive {
        try JSONDecoder().decode(HARArchive.self, from: data)
    }
}

private struct HARLog: Decodable, Sendable {
    let entries: [HAREntry]
}

public struct HAREntry: Identifiable, Decodable, Sendable {
    public let id = UUID()
    public let startedDateTime: String?
    public let time: Double?
    public let request: HARRequest
    public let response: HARResponse
    public let timings: HARTimings?
    public let serverIPAddress: String?
    public let comment: String?

    private enum CodingKeys: String, CodingKey {
        case startedDateTime, time, request, response, timings, serverIPAddress, comment
    }
}

public struct HARRequest: Decodable, Sendable {
    public let method: String
    public let url: String
    public let httpVersion: String?
    public let headers: [HARField]?
    public let queryString: [HARField]?
    public let cookies: [HARCookie]?
    public let postData: HARPostData?
    public let headersSize: Int?
    public let bodySize: Int?
}

public struct HARResponse: Decodable, Sendable {
    public let status: Int
    public let statusText: String?
    public let httpVersion: String?
    public let headers: [HARField]?
    public let cookies: [HARCookie]?
    public let content: HARContent?
    public let redirectURL: String?
    public let headersSize: Int?
    public let bodySize: Int?
    public let transferSize: Int?

    private enum CodingKeys: String, CodingKey {
        case status, statusText, httpVersion, headers, cookies, content, redirectURL, headersSize, bodySize
        case transferSize = "_transferSize"
    }
}

public struct HARField: Decodable, Sendable {
    public let name: String
    public let value: String
}

public struct HARCookie: Decodable, Sendable {
    public let name: String
    public let value: String
    public let domain: String?
    public let path: String?
    public let expires: String?
    public let httpOnly: Bool?
    public let secure: Bool?
}

public struct HARContent: Decodable, Sendable {
    public let size: Int?
    public let mimeType: String?
    public let text: String?
    public let encoding: String?
    public let compression: Int?

    public var displayText: String {
        displayBody(text, mimeType: mimeType, encoding: encoding)
    }
}

public struct HARPostData: Decodable, Sendable {
    public let mimeType: String?
    public let text: String?
    public let params: [HARPostParam]?

    public var displayText: String {
        if text == nil, let params, !params.isEmpty {
            return params.map { parameter in
                let value = parameter.value ?? parameter.fileName.map { "файл \($0)" } ?? "значение не сохранено"
                return "\(parameter.name): \(value)"
            }.joined(separator: "\n")
        }
        if let text, let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
           let prettyText = prettyJSON(json) {
            return prettyText
        }
        return displayBody(text, mimeType: mimeType)
    }
}

public struct HARPostParam: Decodable, Sendable {
    public let name: String
    public let value: String?
    public let fileName: String?
    public let contentType: String?
}

public struct HARTimings: Decodable, Sendable {
    public let blocked: Double?
    public let dns: Double?
    public let connect: Double?
    public let send: Double?
    public let wait: Double?
    public let receive: Double?
    public let ssl: Double?
}

private func displayBody(_ text: String?, mimeType: String?, encoding: String? = nil) -> String {
    guard let text else { return "Тело не сохранено в HAR." }
    var data = Data(text.utf8)
    if let encoding, !encoding.isEmpty {
        guard encoding.lowercased() == "base64" else {
            return "Неподдерживаемая кодировка тела: \(encoding)."
        }
        guard let decoded = Data(base64Encoded: text) else {
            return "Не удалось декодировать тело Base64."
        }
        data = decoded
    }
    if data.isEmpty { return "" }
    guard isTextualMIME(mimeType) else {
        return "Двоичное содержимое (\(data.count) байт)."
    }
    guard let decodedText = String(data: data, encoding: .utf8),
          !decodedText.unicodeScalars.contains(where: { scalar in
              (scalar.value < 32 && ![9, 10, 13].contains(scalar.value)) || (127...159).contains(scalar.value)
          }) else {
        return "Двоичное содержимое или текст не в UTF-8 (\(data.count) байт)."
    }
    if let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
       let prettyText = prettyJSON(json) {
        return prettyText
    }
    if mimeType?.lowercased().contains("json") == true,
       let first = decodedText.first(where: { !$0.isWhitespace }),
       first == "{" || first == "[" {
        return indentJSONFragment(decodedText)
    }
    return decodedText
}

// HAR exports may end inside a string; do not synthesize missing JSON tokens.
private func indentJSONFragment(_ text: String) -> String {
    // ponytail: cap indentation at 32 levels; use a virtualized viewer for deeper trees.
    let maximumIndentationDepth = 32
    var formatted = ""
    var depth = 0
    var isInsideString = false
    var isEscaped = false
    var needsNewline = false
    var hadWhitespace = false

    for scalar in text.unicodeScalars {
        if isInsideString {
            formatted.unicodeScalars.append(scalar)
            if isEscaped { isEscaped = false }
            else if scalar == "\\" { isEscaped = true }
            else if scalar == "\"" { isInsideString = false }
            continue
        }
        if scalar.properties.isWhitespace {
            hadWhitespace = true
            continue
        }
        if scalar == "}" || scalar == "]" {
            depth = max(0, depth - 1)
            if let previous = formatted.unicodeScalars.last, previous != "{" && previous != "[" {
                formatted += "\n" + String(repeating: "  ", count: min(depth, maximumIndentationDepth))
            }
            formatted.unicodeScalars.append(scalar)
            needsNewline = false
            hadWhitespace = false
            continue
        }
        if needsNewline {
            formatted += "\n" + String(repeating: "  ", count: min(depth, maximumIndentationDepth))
            needsNewline = false
        } else if hadWhitespace, let previous = formatted.unicodeScalars.last,
                  !previous.properties.isWhitespace, !"{[,:".unicodeScalars.contains(previous), !"}],:".unicodeScalars.contains(scalar) {
            formatted.append(" ")
        }
        hadWhitespace = false
        switch scalar {
        case "{", "[":
            formatted.unicodeScalars.append(scalar)
            depth += 1
            needsNewline = true
        case ",":
            formatted.unicodeScalars.append(scalar)
            needsNewline = true
        case ":":
            formatted += ": "
        case "\"":
            formatted.unicodeScalars.append(scalar)
            isInsideString = true
        default:
            formatted.unicodeScalars.append(scalar)
        }
    }
    return formatted
}

private func prettyJSON(_ json: Any) -> String? {
    guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

private func isTextualMIME(_ mimeType: String?) -> Bool {
    guard let mimeType, !mimeType.isEmpty else { return true }
    let type = mimeType.lowercased().split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) ?? ""
    return type.hasPrefix("text/") || type.hasPrefix("multipart/") ||
        ["json", "xml", "javascript", "ecmascript", "x-www-form-urlencoded", "graphql"].contains(where: type.contains)
}
