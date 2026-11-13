import Foundation

/// 开机自启：往 ~/Library/LaunchAgents 放一个 LaunchAgent。
/// 不走 SMAppService，这样未签名的本地构建也能用。
enum LoginItem {
    static let label = "com.cc.silencegate"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func enable() -> Bool {
        guard let executable = Bundle.main.executablePath else { return false }
        let contents = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executable)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>ProcessType</key>
            <string>Interactive</string>
            <key>LimitLoadToSessionType</key>
            <string>Aqua</string>
        </dict>
        </plist>
        """
        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try contents.write(to: plistURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    static func disable() {
        try? FileManager.default.removeItem(at: plistURL)
    }
}
