//
//  PerformanceMonitor.swift
//  wallpier
//
//  Performance monitoring utility for tracking app performance and resource usage
//

import Foundation
import OSLog
import AppKit

/// Performance monitoring utility for tracking app metrics
final class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()

    private let logger = Logger(subsystem: "com.oxystack.wallpier", category: "PerformanceMonitor")

    // MARK: - Performance Metrics

    @Published var memoryUsage: Double = 0 // MB
    @Published var cpuUsage: Double = 0 // %
    @Published var averageScanTime: TimeInterval = 0 // seconds
    @Published var averageWallpaperChangeTime: TimeInterval = 0 // seconds
    @Published var cacheHitRate: Double = 0 // %
    @Published var isPerformanceGood: Bool = true

    // MARK: - Performance Targets (from Phase 7 requirements)

    private let maxMemoryUsage: Double = 100.0 // MB
    private let maxScanTime: TimeInterval = 1.0 // seconds for 1000 images
    private let maxWallpaperChangeTime: TimeInterval = 0.5 // seconds
    private let minCacheHitRate: Double = 0.7 // 70%

    // MARK: - Internal Tracking

    private var scanTimes: [TimeInterval] = []
    private var wallpaperChangeTimes: [TimeInterval] = []
    private var monitoringTimer: Timer?
    private var isMonitoring = false

    private init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Public Interface

    /// Starts performance monitoring
    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
        }

        logger.info("Performance monitoring started")
    }

    /// Stops performance monitoring
    func stopMonitoring() {
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil

        logger.info("Performance monitoring stopped")
    }

    /// Records a folder scan time
    func recordScanTime(_ time: TimeInterval, imageCount: Int) {
        scanTimes.append(time)

        // Keep only recent measurements (last 20)
        if scanTimes.count > 20 {
            scanTimes.removeFirst()
        }

        averageScanTime = scanTimes.reduce(0, +) / Double(scanTimes.count)

        // Log if scan time exceeds target (adjusted for image count)
        let expectedTime = Double(imageCount) / 1000.0 * maxScanTime
        if time > expectedTime {
            logger.warning("Scan time exceeded target: \(String(format: "%.3f", time))s for \(imageCount) images (expected: \(String(format: "%.3f", expectedTime))s)")
        }

        checkPerformanceTargets()
    }

    /// Records a wallpaper change time
    func recordWallpaperChangeTime(_ time: TimeInterval) {
        wallpaperChangeTimes.append(time)

        // Keep only recent measurements (last 50)
        if wallpaperChangeTimes.count > 50 {
            wallpaperChangeTimes.removeFirst()
        }

        averageWallpaperChangeTime = wallpaperChangeTimes.reduce(0, +) / Double(wallpaperChangeTimes.count)

        // Log if change time exceeds target
        if time > maxWallpaperChangeTime {
            logger.warning("Wallpaper change time exceeded target: \(String(format: "%.3f", time))s (target: \(String(format: "%.3f", self.maxWallpaperChangeTime))s)")
        }

        checkPerformanceTargets()
    }

    /// Updates cache hit rate
    func updateCacheHitRate(_ rate: Double) {
        cacheHitRate = rate

        if rate < minCacheHitRate {
            logger.warning("Cache hit rate below target: \(String(format: "%.1f", rate * 100))% (target: \(String(format: "%.1f", self.minCacheHitRate * 100))%)")
        }

        checkPerformanceTargets()
    }

    /// Gets comprehensive performance report
    func getPerformanceReport() -> PerformanceReport {
        return PerformanceReport(
            memoryUsage: memoryUsage,
            cpuUsage: cpuUsage,
            averageScanTime: averageScanTime,
            averageWallpaperChangeTime: averageWallpaperChangeTime,
            cacheHitRate: cacheHitRate,
            isWithinTargets: isPerformanceGood,
            targets: PerformanceTargets(
                maxMemoryUsage: maxMemoryUsage,
                maxScanTime: maxScanTime,
                maxWallpaperChangeTime: maxWallpaperChangeTime,
                minCacheHitRate: minCacheHitRate
            ),
            recommendations: getPerformanceRecommendations()
        )
    }

    /// Forces immediate metrics update
    func updateMetricsNow() {
        updateMetrics()
    }

    // MARK: - Private Implementation

    /// Updates all performance metrics
    private func updateMetrics() {
        updateMemoryUsage()
        updateCPUUsage()
        checkPerformanceTargets()
    }

    /// Updates memory usage metric
    private func updateMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let memoryUsageBytes = info.resident_size
            memoryUsage = Double(memoryUsageBytes) / (1024 * 1024) // Convert to MB

            if memoryUsage > maxMemoryUsage {
                logger.warning("Memory usage exceeded target: \(String(format: "%.1f", self.memoryUsage))MB (target: \(String(format: "%.1f", self.maxMemoryUsage))MB)")
            }
        }
    }

    /// Updates CPU usage metric (simplified)
    private func updateCPUUsage() {
        // CPU usage monitoring is complex on macOS, so we'll use a simplified approach
        // In a production app, you'd use more sophisticated CPU monitoring
        cpuUsage = 0.0 // Placeholder - would implement proper CPU monitoring
    }

    /// Checks if all performance targets are met
    private func checkPerformanceTargets() {
        let memoryGood = memoryUsage <= maxMemoryUsage
        let scanTimeGood = averageScanTime <= maxScanTime
        let changeTimeGood = averageWallpaperChangeTime <= maxWallpaperChangeTime
        let cacheGood = cacheHitRate >= minCacheHitRate

        isPerformanceGood = memoryGood && scanTimeGood && changeTimeGood && cacheGood

        if !isPerformanceGood {
            logger.warning("Performance targets not met - Memory: \(memoryGood), Scan: \(scanTimeGood), Change: \(changeTimeGood), Cache: \(cacheGood)")
        }
    }

    /// Generates performance recommendations
    private func getPerformanceRecommendations() -> [String] {
        var recommendations: [String] = []

        if memoryUsage > maxMemoryUsage {
            recommendations.append("Reduce memory usage by clearing image cache or reducing cache size")
        }

        if averageScanTime > maxScanTime {
            recommendations.append("Optimize folder scanning by using quick scan for large folders")
        }

        if averageWallpaperChangeTime > maxWallpaperChangeTime {
            recommendations.append("Improve wallpaper change performance by increasing preloading")
        }

        if cacheHitRate < minCacheHitRate {
            recommendations.append("Increase cache size or adjust preloading strategy")
        }

        if recommendations.isEmpty {
            recommendations.append("Performance is optimal - all targets met")
        }

        return recommendations
    }
}

// MARK: - Performance Data Structures

/// Comprehensive performance report
struct PerformanceReport {
    let memoryUsage: Double
    let cpuUsage: Double
    let averageScanTime: TimeInterval
    let averageWallpaperChangeTime: TimeInterval
    let cacheHitRate: Double
    let isWithinTargets: Bool
    let targets: PerformanceTargets
    let recommendations: [String]

    /// Formatted string for display
    var formattedReport: String {
        return """
        Performance Report:
        - Memory Usage: \(String(format: "%.1f", memoryUsage))MB / \(String(format: "%.1f", targets.maxMemoryUsage))MB
        - Average Scan Time: \(String(format: "%.3f", averageScanTime))s / \(String(format: "%.3f", targets.maxScanTime))s
        - Average Change Time: \(String(format: "%.3f", averageWallpaperChangeTime))s / \(String(format: "%.3f", targets.maxWallpaperChangeTime))s
        - Cache Hit Rate: \(String(format: "%.1f", cacheHitRate * 100))% / \(String(format: "%.1f", targets.minCacheHitRate * 100))%
        - Status: \(isWithinTargets ? "✅ All targets met" : "⚠️ Some targets missed")

        Recommendations:
        \(recommendations.map { "• \($0)" }.joined(separator: "\n"))
        """
    }
}

/// Performance targets for comparison
struct PerformanceTargets {
    let maxMemoryUsage: Double
    let maxScanTime: TimeInterval
    let maxWallpaperChangeTime: TimeInterval
    let minCacheHitRate: Double
}

// MARK: - Performance Timing Utilities

/// Utility for measuring operation performance
struct PerformanceTimer {
    private let startTime: CFAbsoluteTime
    private let operationName: String

    init(_ operationName: String) {
        self.operationName = operationName
        self.startTime = CFAbsoluteTimeGetCurrent()
    }

    /// Ends timing and returns elapsed time
    func end() -> TimeInterval {
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        Logger(subsystem: "com.oxystack.wallpier", category: "PerformanceTimer")
            .debug("\(operationName) took \(String(format: "%.3f", elapsed))s")
        return elapsed
    }

    /// Ends timing and records to performance monitor
    func endAndRecord() -> TimeInterval {
        let elapsed = end()

        // Auto-record specific operations to performance monitor
        if operationName.contains("scan") {
            // Would need image count to properly record scan time
            // PerformanceMonitor.shared.recordScanTime(elapsed, imageCount: count)
        } else if operationName.contains("wallpaper") || operationName.contains("change") {
            PerformanceMonitor.shared.recordWallpaperChangeTime(elapsed)
        }

        return elapsed
    }
}

// MARK: - Extensions for Easy Integration

extension PerformanceMonitor {
    /// Times a synchronous operation
    func time<T>(_ operation: String, _ block: () throws -> T) rethrows -> T {
        let timer = PerformanceTimer(operation)
        let result = try block()
        _ = timer.endAndRecord()
        return result
    }

    /// Times an asynchronous operation
    func timeAsync<T>(_ operation: String, _ block: () async throws -> T) async rethrows -> T {
        let timer = PerformanceTimer(operation)
        let result = try await block()
        _ = timer.endAndRecord()
        return result
    }
}