import AppKit
import Foundation
import KokukokuCore

// --smoke: UIを起動せず設定と状態の読み込みだけ確認して終了する(CI・動作確認用)
if CommandLine.arguments.contains("--smoke") {
    do {
        let config = try ConfigLoader.load()
        print("Kokukoku (smoke): loaded \(config.projects.count) project(s) from config")
    } catch {
        FileHandle.standardError.write(Data("Kokukoku: failed to load config: \(error)\n".utf8))
        exit(1)
    }
    if let state = Persistence().load() {
        print(
            "Kokukoku (smoke): loaded state (accumulated: \(state.accumulated.count) project(s), lastResetAt: \(state.lastResetAt))"
        )
    } else {
        print("Kokukoku (smoke): no state file, starting fresh")
    }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
