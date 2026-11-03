#if DEBUG
import UIKit
import Darwin

/// Informational prototype monitor; CADisplayLink cadence is not stroke latency.
@MainActor
final class SpikeMetrics: NSObject {
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval?
    private var reportTime: CFTimeInterval = 0
    private(set) var intervals = 0
    private(set) var estimatedMissedFrames = 0
    private(set) var peakMiB: Double = 0
    var report: ((String, Bool) -> Void)?

    func start() {
        stop()
        intervals = 0
        estimatedMissedFrames = 0
        peakMiB = 0
        reportTime = 0
        lastTime = nil
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTime = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let expected = link.targetTimestamp - link.timestamp
        if let lastTime, expected > 0 {
            intervals += 1
            estimatedMissedFrames += max(0, Int(((link.timestamp - lastTime) / expected).rounded()) - 1)
        }
        lastTime = link.timestamp
        guard link.timestamp - reportTime >= 1 else { return }
        reportTime = link.timestamp
        let memory = Self.footprintMiB()
        if let memory { peakMiB = max(peakMiB, memory) }
        let memoryText = memory.map { String(format: "%.0f MiB • peak %.0f", $0, peakMiB) } ?? "Memory unavailable"
        let reachedLimit = (memory ?? 0) >= 1_024
        report?("\(memoryText) • missed ≈\(estimatedMissedFrames)/\(intervals) intervals" +
                (reachedLimit ? " • STOP: ≥1 GiB" : ""), reachedLimit)
    }

    static func footprintMiB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1_048_576
    }
}
#endif
