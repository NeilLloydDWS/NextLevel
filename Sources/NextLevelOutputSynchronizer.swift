//
//  NextLevelOutputSynchronizer.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import AVFoundation
import CoreMedia

/// Synchronizes outputs from multiple cameras to maintain alignment
public class NextLevelOutputSynchronizer {
    
    // MARK: - Properties
    
    /// Synchronization mode
    public enum SyncMode {
        case none           // No synchronization
        case timestamp      // Align by presentation timestamps
        case frameAccurate  // Frame-accurate synchronization
        case audioSync      // Sync to audio timestamps
    }
    
    /// Current sync mode
    public var syncMode: SyncMode = .timestamp
    
    /// Maximum acceptable drift in seconds
    public var maxDriftTolerance: TimeInterval = 0.033 // ~1 frame at 30fps
    
    /// Reference time base for synchronization
    private var referenceTimebase: CMTimebase?
    
    /// Sync points for each camera
    private var syncPoints: [NextLevelDevicePosition: SyncPoint] = [:]
    
    /// Frame buffers for synchronization
    private var frameBuffers: [NextLevelDevicePosition: FrameBuffer] = [:]
    
    /// Synchronization queue
    private let syncQueue: DispatchQueue
    
    /// Output queue for synchronized frames
    private let outputQueue: DispatchQueue
    
    /// Delegate
    public weak var delegate: NextLevelMultiCameraV2Delegate?
    
    /// Statistics
    private var statistics = SyncStatistics()
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    public init() {
        self.syncQueue = DispatchQueue(label: "com.nextlevel.sync", qos: .userInitiated)
        self.outputQueue = DispatchQueue(label: "com.nextlevel.sync.output", qos: .userInitiated)
        setupTimebase()
    }
    
    // MARK: - Configuration
    
    /// Configure synchronization for cameras
    public func configureSynchronization(for positions: [NextLevelDevicePosition], mode: SyncMode = .timestamp) {
        lock.lock()
        defer { lock.unlock() }
        
        self.syncMode = mode
        
        // Initialize sync points and buffers
        for position in positions {
            syncPoints[position] = SyncPoint(position: position)
            
            if mode == .frameAccurate {
                frameBuffers[position] = FrameBuffer(maxFrames: 5)
            }
        }
        
        // Reset statistics
        statistics = SyncStatistics()
    }
    
    /// Remove synchronization for camera
    public func removeSynchronization(for position: NextLevelDevicePosition) {
        lock.lock()
        defer { lock.unlock() }
        
        syncPoints.removeValue(forKey: position)
        frameBuffers[position]?.clear()
        frameBuffers.removeValue(forKey: position)
    }
    
    // MARK: - Frame Processing
    
    /// Process frame from camera
    public func processFrame(_ sampleBuffer: CMSampleBuffer, from position: NextLevelDevicePosition) {
        guard syncMode != .none else {
            // Pass through without synchronization
            outputFrame(sampleBuffer, from: position)
            return
        }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        switch syncMode {
        case .timestamp:
            processTimestampSync(sampleBuffer, from: position, timestamp: timestamp)
            
        case .frameAccurate:
            processFrameAccurateSync(sampleBuffer, from: position, timestamp: timestamp)
            
        case .audioSync:
            processAudioSync(sampleBuffer, from: position, timestamp: timestamp)
            
        case .none:
            break
        }
    }
    
    // MARK: - Timestamp Synchronization
    
    private func processTimestampSync(_ sampleBuffer: CMSampleBuffer, from position: NextLevelDevicePosition, timestamp: CMTime) {
        lock.lock()
        defer { lock.unlock() }
        
        // Update sync point
        if var syncPoint = syncPoints[position] {
            syncPoint.lastTimestamp = timestamp
            syncPoint.frameCount += 1
            syncPoints[position] = syncPoint
        }
        
        // Check drift
        let drift = calculateDrift(for: position, at: timestamp)
        statistics.recordDrift(drift, for: position)
        
        if abs(drift) > maxDriftTolerance {
            // Apply drift correction
            let correctedBuffer = applyDriftCorrection(to: sampleBuffer, drift: drift)
            outputFrame(correctedBuffer ?? sampleBuffer, from: position)
            
            statistics.recordCorrection(for: position)
        } else {
            // Output as-is
            outputFrame(sampleBuffer, from: position)
        }
    }
    
    // MARK: - Frame Accurate Synchronization
    
    private func processFrameAccurateSync(_ sampleBuffer: CMSampleBuffer, from position: NextLevelDevicePosition, timestamp: CMTime) {
        lock.lock()
        defer { lock.unlock() }
        
        // Add to frame buffer
        frameBuffers[position]?.addFrame(sampleBuffer)
        
        // Check if we can output synchronized frames
        if canOutputSynchronizedFrames() {
            outputSynchronizedFrames()
        }
    }
    
    private func canOutputSynchronizedFrames() -> Bool {
        // Check if all cameras have frames available
        for (_, buffer) in frameBuffers {
            if buffer.isEmpty {
                return false
            }
        }
        
        // Check if timestamps are close enough
        var timestamps: [CMTime] = []
        
        for (_, buffer) in frameBuffers {
            if let timestamp = buffer.oldestTimestamp {
                timestamps.append(timestamp)
            }
        }
        
        guard !timestamps.isEmpty else { return false }
        
        // Find min and max timestamps
        let minTime = timestamps.min { $0 < $1 } ?? CMTime.zero
        let maxTime = timestamps.max { $0 < $1 } ?? CMTime.zero
        
        let timeDiff = CMTimeSubtract(maxTime, minTime).seconds
        
        return timeDiff <= maxDriftTolerance
    }
    
    private func outputSynchronizedFrames() {
        var synchronizedFrames: [(NextLevelDevicePosition, CMSampleBuffer)] = []
        
        // Get oldest frame from each buffer
        for (position, buffer) in frameBuffers {
            if let frame = buffer.popOldestFrame() {
                synchronizedFrames.append((position, frame))
            }
        }
        
        // Output all frames with same timestamp
        let syncTimestamp = synchronizedFrames.first?.1.presentationTimeStamp ?? CMTime.zero
        
        for (position, frame) in synchronizedFrames {
            // Adjust timestamp if needed
            if let adjustedFrame = adjustTimestamp(of: frame, to: syncTimestamp) {
                outputFrame(adjustedFrame, from: position)
            } else {
                outputFrame(frame, from: position)
            }
        }
        
        statistics.recordSynchronizedSet(count: synchronizedFrames.count)
    }
    
    // MARK: - Audio Synchronization
    
    private func processAudioSync(_ sampleBuffer: CMSampleBuffer, from position: NextLevelDevicePosition, timestamp: CMTime) {
        // Sync video frames to audio master clock
        guard let audioTimebase = getAudioTimebase() else {
            // Fall back to timestamp sync
            processTimestampSync(sampleBuffer, from: position, timestamp: timestamp)
            return
        }
        
        // Get audio clock time
        let audioTime = CMTimebaseGetTime(audioTimebase)
        
        // Calculate offset from audio clock
        let offset = CMTimeSubtract(timestamp, audioTime).seconds
        
        if abs(offset) > maxDriftTolerance {
            // Adjust to audio clock
            if let adjustedBuffer = adjustTimestamp(of: sampleBuffer, to: audioTime) {
                outputFrame(adjustedBuffer, from: position)
            } else {
                outputFrame(sampleBuffer, from: position)
            }
        } else {
            outputFrame(sampleBuffer, from: position)
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupTimebase() {
        // Create master timebase
        CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &referenceTimebase
        )
        
        if let timebase = referenceTimebase {
            CMTimebaseSetTime(timebase, time: CMTime.zero)
            CMTimebaseSetRate(timebase, rate: 1.0)
        }
    }
    
    private func calculateDrift(for position: NextLevelDevicePosition, at timestamp: CMTime) -> TimeInterval {
        guard let referenceTime = getReferenceTime() else { return 0 }
        
        return CMTimeSubtract(timestamp, referenceTime).seconds
    }
    
    private func getReferenceTime() -> CMTime? {
        guard let timebase = referenceTimebase else { return nil }
        return CMTimebaseGetTime(timebase)
    }
    
    private func getAudioTimebase() -> CMTimebase? {
        // Would be provided by audio system
        return nil
    }
    
    private func applyDriftCorrection(to sampleBuffer: CMSampleBuffer, drift: TimeInterval) -> CMSampleBuffer? {
        // Adjust presentation timestamp
        let originalTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let correctedTime = CMTimeSubtract(originalTime, CMTime(seconds: drift, preferredTimescale: originalTime.timescale))
        
        return adjustTimestamp(of: sampleBuffer, to: correctedTime)
    }
    
    private func adjustTimestamp(of sampleBuffer: CMSampleBuffer, to newTimestamp: CMTime) -> CMSampleBuffer? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        
        var timingInfo = CMSampleTimingInfo()
        timingInfo.presentationTimeStamp = newTimestamp
        timingInfo.duration = CMSampleBufferGetDuration(sampleBuffer)
        timingInfo.decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(sampleBuffer)
        
        var adjustedSampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            formatDescription: CMSampleBufferGetFormatDescription(sampleBuffer)!,
            sampleTiming: &timingInfo,
            sampleBufferOut: &adjustedSampleBuffer
        )
        
        return status == noErr ? adjustedSampleBuffer : nil
    }
    
    private func outputFrame(_ sampleBuffer: CMSampleBuffer, from position: NextLevelDevicePosition) {
        outputQueue.async { [weak self] in
            // Notify delegate on main thread
            DispatchQueue.main.async {
                guard let self = self else { return }
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                self.delegate?.nextLevel(NextLevel.shared, didProcessVideoFrame: sampleBuffer, fromCamera: position, timestamp: timestamp)
            }
        }
    }
    
    // MARK: - Statistics
    
    /// Get synchronization statistics
    public func getStatistics() -> SyncStatistics {
        lock.lock()
        defer { lock.unlock() }
        
        return statistics
    }
    
    /// Reset statistics
    public func resetStatistics() {
        lock.lock()
        defer { lock.unlock() }
        
        statistics = SyncStatistics()
    }
}

// MARK: - Frame Buffer

private class FrameBuffer {
    private var frames: [(CMSampleBuffer, CMTime)] = []
    private let maxFrames: Int
    private let lock = NSLock()
    
    init(maxFrames: Int) {
        self.maxFrames = maxFrames
    }
    
    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return frames.isEmpty
    }
    
    var oldestTimestamp: CMTime? {
        lock.lock()
        defer { lock.unlock() }
        return frames.first?.1
    }
    
    func addFrame(_ frame: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(frame)
        frames.append((frame, timestamp))
        
        // Remove oldest if over limit
        if frames.count > maxFrames {
            frames.removeFirst()
        }
    }
    
    func popOldestFrame() -> CMSampleBuffer? {
        lock.lock()
        defer { lock.unlock() }
        
        guard !frames.isEmpty else { return nil }
        return frames.removeFirst().0
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        frames.removeAll()
    }
}

// MARK: - Supporting Types

/// Sync point information
private struct SyncPoint {
    let position: NextLevelDevicePosition
    var lastTimestamp: CMTime = CMTime.zero
    var frameCount: Int = 0
    var driftHistory: [TimeInterval] = []
}

/// Synchronization statistics
public struct SyncStatistics {
    private var driftRecords: [NextLevelDevicePosition: [TimeInterval]] = [:]
    private var correctionCounts: [NextLevelDevicePosition: Int] = [:]
    private var synchronizedSetCount: Int = 0
    private var totalFrames: Int = 0
    
    mutating func recordDrift(_ drift: TimeInterval, for position: NextLevelDevicePosition) {
        driftRecords[position, default: []].append(drift)
        
        // Keep only last 100 records
        if driftRecords[position]!.count > 100 {
            driftRecords[position]!.removeFirst()
        }
    }
    
    mutating func recordCorrection(for position: NextLevelDevicePosition) {
        correctionCounts[position, default: 0] += 1
    }
    
    mutating func recordSynchronizedSet(count: Int) {
        synchronizedSetCount += 1
        totalFrames += count
    }
    
    public func averageDrift(for position: NextLevelDevicePosition) -> TimeInterval {
        guard let drifts = driftRecords[position], !drifts.isEmpty else { return 0 }
        return drifts.reduce(0, +) / Double(drifts.count)
    }
    
    public func maxDrift(for position: NextLevelDevicePosition) -> TimeInterval {
        guard let drifts = driftRecords[position], !drifts.isEmpty else { return 0 }
        return drifts.map { abs($0) }.max() ?? 0
    }
    
    public var description: String {
        var desc = "Synchronization Statistics:\n"
        desc += "  Synchronized Sets: \(synchronizedSetCount)\n"
        desc += "  Total Frames: \(totalFrames)\n"
        
        for position in driftRecords.keys {
            let avgDrift = averageDrift(for: position)
            let maxDrift = self.maxDrift(for: position)
            let corrections = correctionCounts[position] ?? 0
            
            desc += "  Camera \(position.rawValue):\n"
            desc += "    Average Drift: \(String(format: "%.3f", avgDrift * 1000))ms\n"
            desc += "    Max Drift: \(String(format: "%.3f", maxDrift * 1000))ms\n"
            desc += "    Corrections: \(corrections)\n"
        }
        
        return desc
    }
}

// MARK: - CMSampleBuffer Extensions

extension CMSampleBuffer {
    var presentationTimeStamp: CMTime {
        return CMSampleBufferGetPresentationTimeStamp(self)
    }
}