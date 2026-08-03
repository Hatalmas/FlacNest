import Foundation

final class ExportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var runningProcesses: [Process] = []

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let processes = runningProcesses
        lock.unlock()

        for process in processes where process.isRunning {
            process.terminate()
        }
    }

    func register(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        runningProcesses.append(process)
    }

    func unregister(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        runningProcesses.removeAll { $0 === process }
    }
}
