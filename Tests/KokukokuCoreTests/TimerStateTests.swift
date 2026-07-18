import Foundation
import Testing

@testable import KokukokuCore

@Suite("TimerState")
struct TimerStateTests {
    @Test("hs.jsonが出力した空配列のaccumulatedをデコードできる")
    func decodeEmptyAccumulatedArray() throws {
        let json = """
            {
              "continuousElapsedBase" : 0,
              "accumulated" : [],
              "lastResetAt" : 1782054182
            }
            """

        let state = try JSONDecoder().decode(TimerState.self, from: Data(json.utf8))

        #expect(state == TimerState(lastResetAt: 1_782_054_182))
    }

    @Test("欠けたキーはデフォルト値になる")
    func decodeMissingKeys() throws {
        let state = try JSONDecoder().decode(TimerState.self, from: Data("{}".utf8))

        #expect(state == TimerState())
    }

    @Test("辞書形式のaccumulatedをデコードできる")
    func decodeAccumulatedDictionary() throws {
        let json = """
            {"accumulated":{"proj-a":3600},"activeProjectId":"proj-a"}
            """

        let state = try JSONDecoder().decode(TimerState.self, from: Data(json.utf8))

        #expect(state.accumulated == ["proj-a": 3600])
        #expect(state.activeProjectId == "proj-a")
    }

    @Test("非空配列のaccumulatedはデコードに失敗する")
    func rejectNonEmptyAccumulatedArray() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                TimerState.self, from: Data("{\"accumulated\":[1]}".utf8))
        }
    }

    @Test("nilフィールドはエンコード時に省略される")
    func omitNilFieldsWhenEncoding() throws {
        let data = try JSONEncoder().encode(TimerState(lastResetAt: 100))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["activeProjectId"] == nil)
        #expect(object["activeStartedAt"] == nil)
        #expect(object["continuousStartedAt"] == nil)
        #expect((object["accumulated"] as? [String: Any])?.isEmpty == true)
    }
}
