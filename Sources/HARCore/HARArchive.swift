import Foundation

public struct HARArchive: Decodable, Sendable {
    private let log: HARLog
    private var sourceEntries: [UUID: String] = [:]
    public var entries: [HAREntry] { log.entries }

    private enum CodingKeys: String, CodingKey { case log }

    public func sourceJSON(for entryID: UUID) -> String? {
        sourceEntries[entryID]
    }

    public static func decode(_ data: Data) throws -> HARArchive {
        var archive = try JSONDecoder().decode(HARArchive.self, from: data)
        var source = try HARSourceScanner(data)
        let fragments = try source.entryFragments()
        guard fragments.count == archive.entries.count else {
            throw sourceJSONError("Source entry count does not match decoded entries.")
        }
        archive.sourceEntries = Dictionary(uniqueKeysWithValues: zip(archive.entries.map(\.id), fragments))
        return archive
    }
}

// JSONDecoder validates the document; this scanner only locates the original entry ranges.
private struct HARSourceScanner {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) throws {
        let prefix = Array(data.prefix(4))
        let encoding: String.Encoding
        let bomLength: Int
        if prefix.starts(with: [0, 0, 0xFE, 0xFF]) {
            encoding = .utf32BigEndian; bomLength = 4
        } else if prefix.starts(with: [0xFF, 0xFE, 0, 0]) {
            encoding = .utf32LittleEndian; bomLength = 4
        } else if prefix.starts(with: [0xFE, 0xFF]) {
            encoding = .utf16BigEndian; bomLength = 2
        } else if prefix.starts(with: [0xFF, 0xFE]) {
            encoding = .utf16LittleEndian; bomLength = 2
        } else if prefix.starts(with: [0xEF, 0xBB, 0xBF]) {
            encoding = .utf8; bomLength = 3
        } else if prefix.count == 4, prefix[0] == 0, prefix[1] == 0 {
            encoding = .utf32BigEndian; bomLength = 0
        } else if prefix.count == 4, prefix[1] == 0, prefix[2] == 0, prefix[3] == 0 {
            encoding = .utf32LittleEndian; bomLength = 0
        } else if prefix.count == 4, prefix[0] == 0 {
            encoding = .utf16BigEndian; bomLength = 0
        } else if prefix.count == 4, prefix[1] == 0 {
            encoding = .utf16LittleEndian; bomLength = 0
        } else {
            encoding = .utf8; bomLength = 0
        }
        if encoding == .utf8 {
            bytes = Array(data.dropFirst(bomLength))
            return
        }
        guard let text = String(data: data.dropFirst(bomLength), encoding: encoding) else {
            throw sourceJSONError("Could not decode the HAR source text.")
        }
        bytes = Array(text.utf8)
    }

    mutating func entryFragments() throws -> [String] {
        let log = try memberRange(named: "log", objectAt: 0)
        let entries = try memberRange(named: "entries", objectAt: log.lowerBound)
        index = entries.lowerBound
        try consume(0x5B) // [
        skipWhitespace()
        var fragments: [String] = []
        while index < entries.upperBound {
            if bytes[index] == 0x5D { return fragments }
            let start = index
            guard bytes[index] == 0x7B else { throw sourceJSONError("Source entry is not an object.") }
            try skipValue()
            guard index <= entries.upperBound else { throw sourceJSONError("Source entry range exceeds its array.") }
            fragments.append(String(decoding: bytes[start..<index], as: UTF8.self))
            skipWhitespace()
            guard index < entries.upperBound else { throw sourceJSONError("Source entries array is incomplete.") }
            if bytes[index] == 0x5D { return fragments }
            try consume(0x2C) // ,
            skipWhitespace()
        }
        throw sourceJSONError("Could not locate the source entries.")
    }

    private mutating func memberRange(named name: String, objectAt start: Int) throws -> Range<Int> {
        index = start
        skipWhitespace()
        try consume(0x7B) // {
        skipWhitespace()
        while index < bytes.count, bytes[index] != 0x7D {
            let keyStart = index
            try skipString()
            let key = try JSONDecoder().decode(String.self, from: Data(bytes[keyStart..<index]))
            skipWhitespace()
            try consume(0x3A) // :
            skipWhitespace()
            let valueStart = index
            try skipValue()
            if key == name { return valueStart..<index }
            skipWhitespace()
            if index < bytes.count, bytes[index] == 0x7D { break }
            try consume(0x2C) // ,
            skipWhitespace()
        }
        throw sourceJSONError("Could not locate source member \(name).")
    }

    private mutating func skipValue() throws {
        guard index < bytes.count else { throw sourceJSONError("Missing source value.") }
        if bytes[index] == 0x22 { try skipString(); return }
        if bytes[index] == 0x7B || bytes[index] == 0x5B {
            var depth = 0
            while index < bytes.count {
                switch bytes[index] {
                case 0x22:
                    try skipString()
                    continue
                case 0x7B, 0x5B: depth += 1
                case 0x7D, 0x5D: depth -= 1
                default: break
                }
                index += 1
                if depth == 0 { return }
            }
            throw sourceJSONError("Incomplete source container.")
        }
        let start = index
        while index < bytes.count, ![0x2C, 0x7D, 0x5D, 0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
            index += 1
        }
        guard index > start else { throw sourceJSONError("Missing source value.") }
    }

    private mutating func skipString() throws {
        try consume(0x22) // "
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 0x22 { return }
            if byte == 0x5C {
                guard index < bytes.count else { throw sourceJSONError("Incomplete source escape.") }
                index += 1
            }
        }
        throw sourceJSONError("Incomplete source string.")
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    private mutating func consume(_ byte: UInt8) throws {
        guard index < bytes.count, bytes[index] == byte else {
            throw sourceJSONError("Unexpected token in the HAR source.")
        }
        index += 1
    }
}

private func sourceJSONError(_ description: String) -> DecodingError {
    .dataCorrupted(.init(codingPath: [], debugDescription: description))
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
