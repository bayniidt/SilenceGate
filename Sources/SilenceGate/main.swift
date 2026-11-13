import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    /// 退出时是否把音量还原（默认还原，避免把系统留在静音状态）。
    var restoreOnExit = true

    private var statusController: StatusController?
    private var signalSources: [DispatchSourceSignal] = []

    private func installSignalHandling() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                AppDelegate.shared?.restoreOnExit = true
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installSignalHandling()
        statusController = StatusController()
        GateEngine.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if restoreOnExit {
            GateEngine.shared.shutdown()
        }
    }
}

// MARK: - 入口

let arguments = CommandLine.arguments

// 语言偏好也可以在命令行里指定，方便脚本和排错
if let index = arguments.firstIndex(of: "--lang"), index + 1 < arguments.count {
    L.preference = Language.from(arguments[index + 1])
}

if arguments.contains("--help") || arguments.contains("-h") {
    print(L.t(.helpText))
    exit(0)
}

if arguments.contains("--dump-menu") {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let controller = StatusController()
    print(controller.dumpMenuTitles().joined(separator: "\n"))
    exit(0)
}

if arguments.contains("--probe") {
    Diagnostics.printReport()
    exit(0)
}

if arguments.contains("--selftest") {
    Diagnostics.selfTest()
    exit(0)
}

if let index = arguments.firstIndex(of: "--set-output"), index + 1 < arguments.count {
    exit(Diagnostics.setOutput(matching: arguments[index + 1]))
}

// 单实例：已经有一份在跑就直接说清楚并退出，绝不并排跑第二份。
if !SingleInstance.shared.claim() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    // 少了 finishLaunching，runModal 会立刻返回、提示框根本不出现
    app.finishLaunching()
    let pidText = SingleInstance.shared.ownerPID.map { String($0) } ?? "?"
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = L.t(.alertAlreadyRunningTitle)
    alert.informativeText = L.t(.alertAlreadyRunningBody, pidText)
    alert.addButton(withTitle: L.t(.alertOK))
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
AppDelegate.shared = delegate
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
