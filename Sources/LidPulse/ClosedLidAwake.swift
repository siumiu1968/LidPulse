import Foundation
import IOKit
import IOKit.pwr_mgt
import Darwin

/// An unprivileged guard releases the global lid override if the app exits or crashes.
@MainActor
final class ClosedLidAwake {
    private var process: Process?
    private var lease: Pipe?
    var onStopped: ((ClosedLidPolicy.Stop) -> Void)?
    enum Result { case ready, failed }

    func start(language: Language) -> Result {
        if process?.isRunning == true { return .ready }
        stop()
        guard let executable = Bundle.main.executableURL else { return .failed }
        let child = Process()
        let input = Pipe()
        let output = Pipe()
        child.executableURL = executable
        child.arguments = ["--lid-guard"]
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        do { try child.run() } catch { return .failed }
        input.fileHandleForReading.closeFile()
        output.fileHandleForWriting.closeFile()
        var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, 1500) > 0 && output.fileHandleForReading.availableData == Data("ready\n".utf8)
        output.fileHandleForReading.closeFile()
        guard ready else {
            input.fileHandleForWriting.closeFile()
            child.waitUntilExit()
            return .failed
        }
        lease = input
        process = child
        child.terminationHandler = { [weak self] ended in
            Task { @MainActor in
                guard let self, self.process === ended else { return }
                self.process = nil
                self.lease?.fileHandleForWriting.closeFile()
                self.lease = nil
                ClosedLidLogo.recoverAfterExit()
                LidGuard.setSleepDisabled(false)
                self.onStopped?(ClosedLidPolicy.Stop(rawValue: ended.terminationStatus) ?? .unavailable)
            }
        }
        return .ready
    }

    func stop() {
        let previous = process
        process = nil
        lease?.fileHandleForWriting.closeFile()
        lease = nil
        previous?.waitUntilExit()
    }
}

enum LidGuard {
    static var isClosed: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        return (IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, nil, 0)?
            .takeRetainedValue() as? NSNumber)?.boolValue == true
    }

    @discardableResult
    static func setSleepDisabled(_ disabled: Bool) -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(root, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return false }
        defer { IOServiceClose(connection) }
        var value: UInt64 = disabled ? 1 : 0
        // kPMSetClamshellSleepState, defined in Apple's IOPMLibDefs.h.
        return IOConnectCallScalarMethod(connection, 12, &value, 1, nil, nil) == KERN_SUCCESS
    }

    static func run() -> Int32 {
        // The parent handles termination and closes the lease. Finish cleanup on
        // EOF even if a launcher sends SIGTERM to both processes together.
        var signals = sigset_t()
        sigemptyset(&signals)
        sigaddset(&signals, SIGTERM)
        sigaddset(&signals, SIGINT)
        sigprocmask(SIG_BLOCK, &signals, nil)
        var ownsOverride = false
        var assertion: IOPMAssertionID = 0
        defer {
            ClosedLidLogo.recoverAfterExit()
            if assertion != 0 { IOPMAssertionRelease(assertion) }
            if ownsOverride { setSleepDisabled(false) }
        }
        guard setSleepDisabled(true) else { return ClosedLidPolicy.Stop.unavailable.rawValue }
        ownsOverride = true
        FileHandle.standardOutput.write(Data("ready\n".utf8))
        var closedSince: TimeInterval?
        while true {
            var input = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN | POLLHUP), revents: 0)
            if poll(&input, 1, 500) != 0 { return 0 }
            let closed = isClosed
            let now = ProcessInfo.processInfo.systemUptime
            if !closed { closedSince = nil }
            else if closedSince == nil { closedSince = now }
            if let reason = ClosedLidPolicy.stopReason(closed: closed, elapsed: now - (closedSince ?? now),
                                                       power: .read(), thermal: ProcessInfo.processInfo.thermalState) {
                return reason.rawValue
            }
            if closed, assertion == 0 {
                guard IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn), "LidPulse: closed-lid logo session" as CFString,
                    &assertion) == kIOReturnSuccess else { return ClosedLidPolicy.Stop.unavailable.rawValue }
            } else if !closed, assertion != 0 {
                IOPMAssertionRelease(assertion)
                assertion = 0
            }
            guard setSleepDisabled(true) else { return ClosedLidPolicy.Stop.unavailable.rawValue }
        }
    }
}
