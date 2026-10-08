import Foundation
import XCTest
@testable import HARCore

final class HARArchiveTests: XCTestCase {
    func testMinimalEntriesHaveStableDistinctIdentities() throws {
        let archive = try decode(#"{"log":{"entries":[{"request":{"method":"GET","url":"https://demo.example/"},"response":{"status":200}},{"request":{"method":"GET","url":"https://demo.example/"},"response":{"status":200}}]}}"#)

        XCTAssertEqual(archive.entries.count, 2)
        XCTAssertEqual(archive.entries[0].request.method, "GET")
        XCTAssertEqual(archive.entries[0].response.status, 200)
        XCTAssertNil(archive.entries[0].response.content)
        XCTAssertNil(archive.entries[0].startedDateTime)
        XCTAssertEqual(archive.entries[0].id, archive.entries[0].id)
        XCTAssertNotEqual(archive.entries[0].id, archive.entries[1].id)
    }

    func testFullEntryPreservesRequestResponseAndTimingDetails() throws {
        let archive = try decode(#"""
        {"log":{"version":"1.2","creator":{"name":"Synthetic","version":"1"},"entries":[{
          "startedDateTime":"2026-10-01T10:00:00Z","time":52.5,"serverIPAddress":"192.0.2.10","comment":"Demo only",
          "request":{"method":"POST","url":"https://api.example/items?q=demo","httpVersion":"HTTP/2",
            "headers":[{"name":"Content-Type","value":"application/json"}],"queryString":[{"name":"q","value":"demo"}],
            "cookies":[{"name":"theme","value":"light","domain":"api.example","path":"/","expires":null,"httpOnly":false,"secure":true}],
            "postData":{"mimeType":"application/json","text":"{\"name\":\"demo\"}"},"headersSize":-1,"bodySize":15},
          "response":{"status":201,"statusText":"Created","httpVersion":"HTTP/2",
            "headers":[{"name":"Content-Type","value":"application/json"}],"cookies":[],
            "content":{"size":8,"mimeType":"application/json","text":"{\"id\":1}","compression":4},
            "redirectURL":"","headersSize":-1,"bodySize":8,"_transferSize":42},
          "timings":{"blocked":0.5,"dns":-1,"connect":2,"send":1,"wait":40,"receive":9,"ssl":1}
        }]}}
        """#)
        let entry = try XCTUnwrap(archive.entries.first)

        XCTAssertEqual(entry.request.queryString?.first?.value, "demo")
        XCTAssertEqual(entry.request.headers?.first?.name, "Content-Type")
        XCTAssertEqual(entry.request.cookies?.first?.secure, true)
        XCTAssertEqual(entry.request.bodySize, 15)
        XCTAssertEqual(entry.response.transferSize, 42)
        XCTAssertEqual(entry.response.content?.compression, 4)
        XCTAssertEqual(entry.timings?.dns, -1)
        XCTAssertEqual(entry.timings?.wait, 40)
        XCTAssertEqual(entry.time, 52.5)
        XCTAssertEqual(entry.serverIPAddress, "192.0.2.10")
    }

    func testEmptyLogIsValid() throws {
        XCTAssertTrue(try decode(#"{"log":{"entries":[]}}"#).entries.isEmpty)
    }

    func testMalformedStructureAndEntriesAreRejected() {
        let invalidArchives = [
            "not JSON", "{}", #"{"log":{}}"#, #"{"log":{"entries":null}}"#,
            #"{"log":{"entries":{}}}"#,
            #"{"log":{"entries":[{"request":{"url":"https://demo.example/"},"response":{"status":200}}]}}"#,
            #"{"log":{"entries":[{"request":{"method":"GET"},"response":{"status":200}}]}}"#,
            #"{"log":{"entries":[{"request":{"method":"GET","url":"https://demo.example/"},"response":{"status":"200"}}]}}"#,
            #"{"log":{"entries":[{"request":{"method":"GET","url":"https://demo.example/"},"response":{"status":200}},{"request":{},"response":{}}]}}"#
        ]
        for json in invalidArchives {
            XCTAssertThrowsError(try decode(json))
        }
    }

    func testJSONBodiesArePrettyPrintedWithoutExecutingHTML() throws {
        let content = try body(#"{"mimeType":"application/json","text":"{\"b\":2,\"a\":1}"}"#)
        XCTAssertTrue(content.displayText.contains("\n"))
        XCTAssertTrue(content.displayText.contains(#""a" : 1"#))

        let postData = try JSONDecoder().decode(HARPostData.self, from: Data(#"{"mimeType":"application/json","text":"{\"ok\":true}"}"#.utf8))
        XCTAssertTrue(postData.displayText.contains("\n"))

        let html = try body(#"{"mimeType":"text/html","text":"<script>alert('demo')</script>"}"#)
        XCTAssertEqual(html.displayText, "<script>alert('demo')</script>")
    }

    func testBase64TextIsDecodedAndPrettyPrinted() throws {
        let content = try body(#"{"mimeType":"application/json; charset=utf-8","encoding":"base64","text":"eyJvayI6dHJ1ZX0="}"#)
        XCTAssertTrue(content.displayText.contains(#""ok" : true"#))
        XCTAssertFalse(content.displayText.contains("eyJvay"))
    }

    func testRequestJSONObjectsAndArraysArePrettyPrintedWithoutJSONMIME() {
        for mimeType in [nil, "application/octet-stream"] {
            for text in [#"{"name":"Demo"}"#, #"[{"name":"Demo"}]"#] {
                let postData = HARPostData(mimeType: mimeType, text: text, params: nil)
                XCTAssertTrue(postData.displayText.contains("\n  "))
                XCTAssertTrue(postData.displayText.contains(#""name" : "Demo""#))
            }
        }
    }

    func testRequestPlainTextIsPreserved() {
        let text = "not JSON\n  retain whitespace"
        for mimeType in [nil, "text/plain"] {
            XCTAssertEqual(HARPostData(mimeType: mimeType, text: text, params: nil).displayText, text)
        }
    }

    func testIncompleteDeclaredJSONBodyIsIndentedWithoutChangingItsFragment() {
        let text = #"{"items":[{"text":"quoted \"value\", {[}] \\ path","count":2,"flag":true,"empty":null}],"tail":"unfinished \"quote\", {[}]"#
        let expected = #"""
        {
          "items": [
            {
              "text": "quoted \"value\", {[}] \\ path",
              "count": 2,
              "flag": true,
              "empty": null
            }
          ],
          "tail": "unfinished \"quote\", {[}]
        """#

        let postData = HARPostData(mimeType: "application/json", text: text, params: nil)
        XCTAssertEqual(postData.displayText, expected)
        let content = HARContent(size: nil, mimeType: "application/json", text: text, encoding: nil, compression: nil)
        XCTAssertEqual(content.displayText, expected)

        let combiningText = "{\"tail\":\"\u{0301}a,b{c"
        let combiningExpected = "{\n  \"tail\": \"\u{0301}a,b{c"
        XCTAssertEqual(HARPostData(mimeType: "application/json", text: combiningText, params: nil).displayText, combiningExpected)
        XCTAssertEqual(HARContent(size: nil, mimeType: "application/json", text: combiningText, encoding: nil, compression: nil).displayText, combiningExpected)
    }

    func testMalformedJSONLikePlainTextBodyIsPreserved() {
        let text = #"{"message":"unfinished"#
        let postData = HARPostData(mimeType: "text/plain", text: text, params: nil)
        XCTAssertEqual(postData.displayText, text)
        let content = HARContent(size: nil, mimeType: "text/plain", text: text, encoding: nil, compression: nil)
        XCTAssertEqual(content.displayText, text)
    }

    func testDeeplyNestedIncompleteJSONBodyHasBoundedExpansion() {
        let suffix = #""unfinished"#
        let text = String(repeating: "[", count: 1200) + suffix
        let content = HARContent(size: nil, mimeType: "application/json", text: text, encoding: nil, compression: nil)
        let output = content.displayText

        XCTAssertLessThan(output.count, text.count * 80)
        XCTAssertEqual(output.filter { $0 == "[" }.count, 1200)
        XCTAssertTrue(output.hasSuffix(suffix))
    }

    func testRequestJSONWithUnicodeControlCharacterRemainsJSON() {
        let postData = HARPostData(mimeType: "application/octet-stream", text: "{\"name\":\"Demo\u{0085}\"}", params: nil)
        XCTAssertTrue(postData.displayText.contains("\n  "))
        XCTAssertTrue(postData.displayText.contains("Demo"))
    }

    func testMissingBinaryAndInvalidBodiesHaveClearDescriptions() throws {
        let missing = try body(#"{"mimeType":"text/plain","size":42}"#)
        XCTAssertTrue(missing.displayText.contains("не сохранено"))
        XCTAssertEqual(try body(#"{"mimeType":"text/plain","text":""}"#).displayText, "")

        let binary = try body(#"{"mimeType":"image/gif","encoding":"base64","text":"R0lGODlh"}"#)
        XCTAssertTrue(binary.displayText.contains("Двоичное"))
        XCTAssertFalse(binary.displayText.contains("GIF89a"))

        let binaryJSON = try body(#"{"mimeType":"application/octet-stream","text":"{\"ok\":true}"}"#)
        XCTAssertTrue(binaryJSON.displayText.contains("Двоичное"))

        let controlBytes = try body(#"{"mimeType":"text/plain","encoding":"base64","text":"AAE="}"#)
        XCTAssertTrue(controlBytes.displayText.contains("Двоичное"))

        let invalid = try body(#"{"mimeType":"text/plain","encoding":"base64","text":"%%%"}"#)
        XCTAssertTrue(invalid.displayText.contains("Base64"))
        let unsupported = try body(#"{"mimeType":"text/plain","encoding":"custom","text":"encoded"}"#)
        XCTAssertTrue(unsupported.displayText.contains("кодировка"))
        XCTAssertFalse(unsupported.displayText.contains("encoded"))
    }

    func testFormParametersRemainVisibleWhenTextWasNotCaptured() throws {
        let form = try JSONDecoder().decode(HARPostData.self, from: Data(#"{"mimeType":"multipart/form-data","params":[{"name":"title","value":"Demo"},{"name":"upload","fileName":"sample.txt","contentType":"text/plain"}]}"#.utf8))
        XCTAssertTrue(form.displayText.contains("title: Demo"))
        XCTAssertTrue(form.displayText.contains("sample.txt"))
    }

    private func decode(_ json: String) throws -> HARArchive {
        try HARArchive.decode(Data(json.utf8))
    }

    private func body(_ json: String) throws -> HARContent {
        try JSONDecoder().decode(HARContent.self, from: Data(json.utf8))
    }
}
