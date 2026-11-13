import Darwin
import Foundation

/// 单实例锁：同一时刻只允许一个 SilenceGate 在跑。
///
/// 用 `flock` 而不是 pid 文件判存在 —— 进程不管是正常退出、崩溃还是被 SIGKILL，
/// 内核都会自动释放锁，永远不会留下"僵尸锁"把 App 挡在门外。
/// 锁文件里额外写一份 PID，只是为了让"已经在运行"的提示能说清是谁在占着。
final class SingleInstance {
    static let shared = SingleInstance()

    private var fileDescriptor: Int32 = -1

    private init() {}

    private var lockURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("SilenceGate", isDirectory: true)
            .appendingPathComponent("instance.lock")
    }

    /// 抢锁。返回 true = 抢到了，可以继续启动；
    /// 返回 false = 已有实例在跑，`ownerPID` 是对方的 PID（可能为 nil）。
    func claim() -> Bool {
        let url = lockURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)

        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            // 开不了锁文件就放行，宁可多开也不要把 App 彻底锁死
            return true
        }

        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            ownerPID = readOwnerPID(url)
            close(descriptor)
            return false
        }

        ftruncate(descriptor, 0)
        let line = "\(getpid())\n"
        _ = line.withCString { write(descriptor, $0, strlen($0)) }
        fsync(descriptor)

        // 故意不 close：关掉文件描述符就等于释放锁
        fileDescriptor = descriptor
        return true
    }

    /// 已有实例的 PID（仅当 claim() 返回 false 时有意义）
    private(set) var ownerPID: pid_t?

    /// 只查询、不占坑：有别的实例在跑就返回它的 PID（拿不到具体值时为 -1），
    /// 没人占就返回 nil。给 --probe 诊断用。
    func probeOwner() -> pid_t? {
        let url = lockURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let descriptor = open(url.path, O_RDWR)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            flock(descriptor, LOCK_UN)
            return nil
        }
        return readOwnerPID(url) ?? -1
    }

    private func readOwnerPID(_ url: URL) -> pid_t? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = pid_t(trimmed), value > 0 else { return nil }
        return value
    }
}
