import Testing

@testable import KokukokuCore

@Suite("TimeInput")
struct TimeInputTests {
    @Test("H:M:Sを秒に変換する")
    func hoursMinutesSeconds() {
        #expect(TimeInput.parse("01:30:00") == 5400)
        #expect(TimeInput.parse("00:05:30") == 330)
        #expect(TimeInput.parse("00:00:00") == 0)
    }

    @Test("M:Sを秒に変換する")
    func minutesSeconds() {
        #expect(TimeInput.parse("5:30") == 330)
    }

    @Test("数値を切り捨てた秒に変換する")
    func numericSeconds() {
        #expect(TimeInput.parse("3600") == 3600)
        #expect(TimeInput.parse("1.9") == 1)
        #expect(TimeInput.parse("-1.2") == -2)
    }

    @Test("空・nil・不正文字列はnilにする")
    func invalid() {
        #expect(TimeInput.parse("") == nil)
        #expect(TimeInput.parse(nil) == nil)
        #expect(TimeInput.parse("abc") == nil)
        #expect(TimeInput.parse("1:2.5") == nil)
    }
}
