import Foundation
import Darwin

/// Serialize live harness mutations across processes on this user's desktop.
/// The OS releases the lock on crash/exit; a stale lock file cannot block a run.
final class DesktopLease {
    private var descriptor: Int32
    init(path: String = "/tmp/errol-desktop-verify-\(getuid()).lock") throws {
        descriptor = open(path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw VerificationError("Cannot open desktop test lock: \(String(cString: strerror(errno)))") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor); descriptor = -1
            throw VerificationError("Another live verification process owns this desktop; wait for it to finish")
        }
    }
    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor); descriptor = -1
    }
    deinit { release() }
}
