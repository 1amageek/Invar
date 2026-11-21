import Darwin
import Foundation
import VerificationCore

struct NativeResourceMeter {
    private let started = ContinuousClock.now
    private let initialCPU: Double
    init() throws { initialCPU = try Self.cpu() }
    func measurements() throws -> [String: Double] {
        let duration = started.duration(to: .now).components
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw InvarError("UNKNOWN_RESOURCE_USAGE", "Cannot read build resource usage", exitCode: 6) }
        let consumed = try Self.cpu()
        return ["wallSeconds": Double(duration.seconds) + Double(duration.attoseconds) / 1e18,
            "cpuSeconds": max(0, consumed - initialCPU), "processLifetimePeakResidentBytes": Double(usage.ru_maxrss)]
    }
    private static func cpu() throws -> Double {
        var own = rusage(), children = rusage()
        guard getrusage(RUSAGE_SELF, &own) == 0, getrusage(RUSAGE_CHILDREN, &children) == 0 else { throw InvarError("UNKNOWN_RESOURCE_USAGE", "Cannot account build CPU", exitCode: 6) }
        var total = 0.0
        for usage in [own, children] {
            let seconds = Double(usage.ru_utime.tv_sec) + Double(usage.ru_stime.tv_sec)
            let fraction = Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
            total += seconds + fraction
        }
        return total
    }
}
