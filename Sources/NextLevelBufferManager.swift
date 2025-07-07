//
//  NextLevelBufferManager.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import UIKit

/// Manages buffer allocation and recycling for multi-camera capture
public class NextLevelBufferManager {
    
    // MARK: - Properties
    
    /// Buffer pools for each camera
    private var bufferPools: [NextLevelDevicePosition: BufferPool] = [:]
    
    /// Memory pressure monitor
    private let memoryMonitor = MemoryPressureMonitor()
    
    /// Queue for buffer management
    private let bufferQueue: DispatchQueue
    
    /// Maximum memory usage in bytes
    private var maxMemoryUsage: Int64 = 512 * 1024 * 1024 // 512 MB default
    
    /// Current memory usage
    private var currentMemoryUsage: Int64 = 0
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    /// Buffer usage statistics
    private var statistics = BufferStatistics()
    
    // MARK: - Initialization
    
    public init() {
        self.bufferQueue = DispatchQueue(label: "com.nextlevel.buffer.manager", qos: .userInitiated)
        setupMemoryMonitoring()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Buffer Pool Management
    
    /// Create buffer pool for camera
    public func createBufferPool(for position: NextLevelDevicePosition,
                               configuration: BufferPoolConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        
        // Remove existing pool if any
        if let existingPool = bufferPools[position] {
            existingPool.drain()
        }
        
        // Create new pool
        let pool = BufferPool(configuration: configuration)
        bufferPools[position] = pool
        
        // Pre-allocate buffers
        pool.preallocate()
    }
    
    /// Remove buffer pool for camera
    public func removeBufferPool(for position: NextLevelDevicePosition) {
        lock.lock()
        defer { lock.unlock() }
        
        if let pool = bufferPools[position] {
            pool.drain()
            bufferPools.removeValue(forKey: position)
        }
    }
    
    /// Get buffer from pool
    public func getBuffer(for position: NextLevelDevicePosition) -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let pool = bufferPools[position] else { return nil }
        
        // Check memory pressure
        if memoryMonitor.isUnderPressure {
            handleMemoryPressure()
        }
        
        // Get buffer from pool
        if let buffer = pool.getBuffer() {
            statistics.bufferRequested(for: position)
            updateMemoryUsage(buffer, acquired: true)
            return buffer
        } else {
            statistics.bufferMiss(for: position)
            return nil
        }
    }
    
    /// Return buffer to pool
    public func returnBuffer(_ buffer: CVPixelBuffer, to position: NextLevelDevicePosition) {
        lock.lock()
        defer { lock.unlock() }
        
        guard let pool = bufferPools[position] else { return }
        
        pool.returnBuffer(buffer)
        statistics.bufferReturned(for: position)
        updateMemoryUsage(buffer, acquired: false)
    }
    
    /// Process buffer with copy-on-write semantics
    public func processBuffer(_ buffer: CMSampleBuffer,
                            from position: NextLevelDevicePosition,
                            processor: (CVPixelBuffer) -> CVPixelBuffer?) -> CMSampleBuffer? {
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return nil }
        
        // Get processed buffer
        guard let processedPixelBuffer = processor(pixelBuffer) else { return nil }
        
        // Create new sample buffer with processed pixel buffer
        var timingInfo = CMSampleTimingInfo()
        timingInfo.duration = CMSampleBufferGetDuration(buffer)
        timingInfo.presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(buffer)
        timingInfo.decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(buffer)
        
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: processedPixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        guard let desc = formatDescription else { return nil }
        
        var processedSampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: processedPixelBuffer,
            formatDescription: desc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &processedSampleBuffer
        )
        
        return processedSampleBuffer
    }
    
    // MARK: - Memory Management
    
    private func setupMemoryMonitoring() {
        memoryMonitor.onMemoryWarning = { [weak self] in
            self?.handleMemoryPressure()
        }
        
        memoryMonitor.startMonitoring()
    }
    
    private func handleMemoryPressure() {
        // Reduce buffer pool sizes
        for (_, pool) in bufferPools {
            pool.reduceSize(by: 0.5) // Reduce by 50%
        }
        
        // Force garbage collection of unused buffers
        performEmergencyCleanup()
    }
    
    private func performEmergencyCleanup() {
        lock.lock()
        defer { lock.unlock() }
        
        for (position, pool) in bufferPools {
            let freedCount = pool.performEmergencyCleanup()
            statistics.emergencyCleanup(for: position, freedBuffers: freedCount)
        }
    }
    
    private func updateMemoryUsage(_ buffer: CVPixelBuffer, acquired: Bool) {
        let bufferSize = CVPixelBufferGetDataSize(buffer)
        
        if acquired {
            currentMemoryUsage += Int64(bufferSize)
        } else {
            currentMemoryUsage -= Int64(bufferSize)
        }
        
        // Ensure non-negative
        currentMemoryUsage = max(0, currentMemoryUsage)
    }
    
    private func cleanup() {
        lock.lock()
        defer { lock.unlock() }
        
        for (_, pool) in bufferPools {
            pool.drain()
        }
        
        bufferPools.removeAll()
        currentMemoryUsage = 0
    }
    
    // MARK: - Statistics
    
    /// Get current buffer statistics
    public func getStatistics() -> BufferStatistics {
        lock.lock()
        defer { lock.unlock() }
        
        return statistics
    }
    
    /// Reset statistics
    public func resetStatistics() {
        lock.lock()
        defer { lock.unlock() }
        
        statistics = BufferStatistics()
    }
}

// MARK: - Buffer Pool

private class BufferPool {
    
    private let configuration: BufferPoolConfiguration
    private var availableBuffers: [CVPixelBuffer] = []
    private var inUseBuffers: Set<CVPixelBuffer> = []
    private let lock = NSLock()
    
    init(configuration: BufferPoolConfiguration) {
        self.configuration = configuration
    }
    
    func preallocate() {
        lock.lock()
        defer { lock.unlock() }
        
        for _ in 0..<configuration.minBufferCount {
            if let buffer = createBuffer() {
                availableBuffers.append(buffer)
            }
        }
    }
    
    func getBuffer() -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        
        // Try to get from available pool
        if let buffer = availableBuffers.popLast() {
            inUseBuffers.insert(buffer)
            return buffer
        }
        
        // Create new buffer if under max count
        if inUseBuffers.count < configuration.maxBufferCount {
            if let buffer = createBuffer() {
                inUseBuffers.insert(buffer)
                return buffer
            }
        }
        
        return nil
    }
    
    func returnBuffer(_ buffer: CVPixelBuffer) {
        lock.lock()
        defer { lock.unlock() }
        
        guard inUseBuffers.remove(buffer) != nil else { return }
        
        // Return to pool if under max available count
        if availableBuffers.count < configuration.maxAvailableBuffers {
            availableBuffers.append(buffer)
        }
        // Otherwise let it be deallocated
    }
    
    func reduceSize(by factor: Float) {
        lock.lock()
        defer { lock.unlock() }
        
        let targetCount = Int(Float(availableBuffers.count) * (1.0 - factor))
        while availableBuffers.count > targetCount {
            _ = availableBuffers.popLast()
        }
    }
    
    func performEmergencyCleanup() -> Int {
        lock.lock()
        defer { lock.unlock() }
        
        let freedCount = availableBuffers.count
        availableBuffers.removeAll()
        return freedCount
    }
    
    func drain() {
        lock.lock()
        defer { lock.unlock() }
        
        availableBuffers.removeAll()
        inUseBuffers.removeAll()
    }
    
    private func createBuffer() -> CVPixelBuffer? {
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            configuration.width,
            configuration.height,
            configuration.pixelFormat,
            attributes as CFDictionary,
            &buffer
        )
        
        return status == kCVReturnSuccess ? buffer : nil
    }
}

// MARK: - Memory Pressure Monitor

private class MemoryPressureMonitor {
    
    var onMemoryWarning: (() -> Void)?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    var isUnderPressure: Bool = false
    
    func startMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global())
        
        source.setEventHandler { [weak self] in
            self?.isUnderPressure = true
            self?.onMemoryWarning?()
        }
        
        source.resume()
        memoryPressureSource = source
        
        // Also monitor app memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    func stopMonitoring() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func didReceiveMemoryWarning() {
        isUnderPressure = true
        onMemoryWarning?()
    }
}

// MARK: - Supporting Types

/// Buffer pool configuration
public struct BufferPoolConfiguration {
    let width: Int
    let height: Int
    let pixelFormat: OSType
    let minBufferCount: Int
    let maxBufferCount: Int
    let maxAvailableBuffers: Int
    
    public init(width: Int,
                height: Int,
                pixelFormat: OSType = kCVPixelFormatType_32BGRA,
                minBufferCount: Int = 3,
                maxBufferCount: Int = 10,
                maxAvailableBuffers: Int = 5) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.minBufferCount = minBufferCount
        self.maxBufferCount = maxBufferCount
        self.maxAvailableBuffers = maxAvailableBuffers
    }
}

/// Buffer usage statistics
public struct BufferStatistics {
    private var requestCounts: [NextLevelDevicePosition: Int] = [:]
    private var missCounts: [NextLevelDevicePosition: Int] = [:]
    private var returnCounts: [NextLevelDevicePosition: Int] = [:]
    private var emergencyCleanupCounts: [NextLevelDevicePosition: Int] = [:]
    
    mutating func bufferRequested(for position: NextLevelDevicePosition) {
        requestCounts[position, default: 0] += 1
    }
    
    mutating func bufferMiss(for position: NextLevelDevicePosition) {
        missCounts[position, default: 0] += 1
    }
    
    mutating func bufferReturned(for position: NextLevelDevicePosition) {
        returnCounts[position, default: 0] += 1
    }
    
    mutating func emergencyCleanup(for position: NextLevelDevicePosition, freedBuffers: Int) {
        emergencyCleanupCounts[position, default: 0] += freedBuffers
    }
    
    public func hitRate(for position: NextLevelDevicePosition) -> Float {
        let requests = requestCounts[position] ?? 0
        let misses = missCounts[position] ?? 0
        
        guard requests > 0 else { return 0 }
        return Float(requests - misses) / Float(requests)
    }
    
    public var description: String {
        var desc = "Buffer Statistics:\n"
        
        for position in requestCounts.keys {
            let requests = requestCounts[position] ?? 0
            let misses = missCounts[position] ?? 0
            let returns = returnCounts[position] ?? 0
            let cleanups = emergencyCleanupCounts[position] ?? 0
            let hitRate = self.hitRate(for: position)
            
            desc += "  Position \(position.rawValue):\n"
            desc += "    Requests: \(requests)\n"
            desc += "    Misses: \(misses)\n"
            desc += "    Returns: \(returns)\n"
            desc += "    Hit Rate: \(String(format: "%.1f%%", hitRate * 100))\n"
            desc += "    Emergency Cleanups: \(cleanups)\n"
        }
        
        return desc
    }
}