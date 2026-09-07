import Darwin
import Foundation

/// Serializes a complete operation across threads, store instances, and processes.
/// The persistent lock file is never removed or replaced while a store is in use.
final class StoreLock: @unchecked Sendable {
    private let mutex = NSRecursiveLock()
    private var depth = 0
    private let descriptor: Int32

    init(root: URL) throws {
        descriptor = Darwin.open(root.appendingPathComponent(".store.lock").path,
                                 O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw Self.posixError() }
        if fchmod(descriptor, 0o600) != 0 {
            let error = Self.posixError()
            Darwin.close(descriptor)
            throw error
        }
    }

    deinit { Darwin.close(descriptor) }

    func withLock<T>(_ operation: () throws -> T) throws -> T {
        mutex.lock()
        defer { mutex.unlock() }
        if depth == 0 {
            while flock(descriptor, LOCK_EX) != 0 {
                if errno != EINTR { throw Self.posixError() }
            }
        }
        depth += 1
        defer {
            depth -= 1
            if depth == 0 { _ = flock(descriptor, LOCK_UN) }
        }
        return try operation()
    }

    static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
