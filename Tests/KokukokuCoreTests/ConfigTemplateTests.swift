import Foundation
import Testing

@testable import KokukokuCore

@Suite("ConfigTemplate")
struct ConfigTemplateTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kokukoku-config-template-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("雛形をそのまま読み込むと、ファイルが無いときと同じ既定の設定になる")
    func templateEqualsMissingFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let missing = try ConfigLoader.load(from: dir.appendingPathComponent("missing.toml"))

        #expect(try ConfigLoader.parse(toml: DefaultConfigTemplate.text) == missing)
    }

    @Test("ファイルが無ければ親ディレクトリごと雛形を書き出す")
    func writesTemplateWhenMissing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("nested/kokukoku/config.toml")

        try ConfigLoader.ensureConfigFileExists(at: url)

        #expect(try String(contentsOf: url, encoding: .utf8) == DefaultConfigTemplate.text)
    }

    @Test("既存のファイルは上書きしない")
    func keepsExistingFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.toml")
        try "# mine\n".write(to: url, atomically: true, encoding: .utf8)

        try ConfigLoader.ensureConfigFileExists(at: url)

        #expect(try String(contentsOf: url, encoding: .utf8) == "# mine\n")
    }

    @Test("確かめた後に別のプロセスが作ったファイルは上書きせず、エラーにもしない")
    func writeDoesNotOverwriteRacedFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.toml")
        try "# raced\n".write(to: url, atomically: true, encoding: .utf8)

        try ConfigLoader.writeTemplateWithoutOverwriting(to: url)

        #expect(try String(contentsOf: url, encoding: .utf8) == "# raced\n")
        #expect(try entries(of: dir) == ["config.toml"])
    }

    @Test("配置できたら最終のパスに雛形だけが残り、一時ファイルは残らない")
    func writePlacesTemplateWithoutTemporaryFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.toml")

        try ConfigLoader.writeTemplateWithoutOverwriting(to: url)

        #expect(try String(contentsOf: url, encoding: .utf8) == DefaultConfigTemplate.text)
        #expect(try entries(of: dir) == ["config.toml"])
    }

    @Test("配置する時点で、一時ファイルには雛形が最後まで書けている")
    func placesFullyWrittenTemporaryFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.toml")
        var placedText: String?

        try ConfigLoader.writeTemplateWithoutOverwriting(to: url) { from, to in
            #expect(from.deletingLastPathComponent() == to.deletingLastPathComponent())
            placedText = try String(contentsOf: from, encoding: .utf8)
            try ConfigLoader.linkWithoutOverwriting(from: from, to: to)
        }

        #expect(placedText == DefaultConfigTemplate.text)
        #expect(try entries(of: dir) == ["config.toml"])
    }

    @Test("配置に失敗したらエラーにし、一時ファイルも最終のパスも残らない")
    func failedPlacementLeavesNoTemporaryFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.toml")

        #expect(throws: POSIXError(.ENOSPC)) {
            try ConfigLoader.writeTemplateWithoutOverwriting(to: url) { _, _ in
                throw POSIXError(.ENOSPC)
            }
        }
        #expect(try entries(of: dir) == [])
    }

    @Test("一時ファイルを書けなければエラーにし、何も残さない")
    func failedTemporaryWriteLeavesNothing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // 親がファイルなので、一時ファイルを書く時点で失敗する
        let parentFile = dir.appendingPathComponent("not-a-dir")
        try "".write(to: parentFile, atomically: true, encoding: .utf8)

        #expect(throws: (any Error).self) {
            try ConfigLoader.writeTemplateWithoutOverwriting(
                to: parentFile.appendingPathComponent("config.toml"))
        }
        #expect(try entries(of: dir) == ["not-a-dir"])
    }

    private func entries(of dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
    }

    @Test("確かめた後に別のプロセスが作ったリンク切れは、リンクを残してエラーにする")
    func writeThrowsOnRacedBrokenSymlink() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.toml")
        let destination = dir.appendingPathComponent("dotfiles/config.toml")
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: destination)

        #expect(throws: ConfigFileError.brokenSymlink(path: url.path)) {
            try ConfigLoader.writeTemplateWithoutOverwriting(to: url)
        }
        #expect(ConfigLoader.isBrokenSymlink(url))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try entries(of: dir) == ["config.toml"])
    }

    @Test("リンク先が無いシンボリックリンクは作らずにエラーにする")
    func brokenSymlinkThrows() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.toml")
        try FileManager.default.createSymbolicLink(
            at: url, withDestinationURL: dir.appendingPathComponent("dotfiles/config.toml"))

        #expect(throws: ConfigFileError.brokenSymlink(path: url.path)) {
            try ConfigLoader.ensureConfigFileExists(at: url)
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("dotfiles").path))
        #expect(
            ConfigFileError.brokenSymlink(path: "/x/config.toml").localizedDescription
                == "設定ファイルのシンボリックリンクのリンク先がありません: /x/config.toml")
    }
}
