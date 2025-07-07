//
//  NextLevelResourceManager.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import AVFoundation
import CoreMedia
import os.log

/// Manages system resources for multi-camera capture with intelligent allocation
public class NextLevelResourceManager {
    
    // MARK: - Properties
    
    /// Shared instance
    public static let shared = NextLevelResourceManager()
    
    /// Resource allocation state
    private var allocations: [ResourceAllocation] = []
    
    /// Available resources
    private var availableResources: SystemResources
    
    /// Resource constraints
    private var constraints: ResourceConstraints
    
    /// Thermal state monitor
    private let thermalMonitor = ThermalStateMonitor()
    
    /// Hardware capability detector
    private let hardwareDetector = HardwareCapabilityDetector()
    
    /// Performance metrics
    private var performanceMetrics = ResourcePerformanceMetrics()
    
    /// Resource optimization engine
    private let optimizer = ResourceOptimizer()
    
    /// Queue for resource management
    private let resourceQueue: DispatchQueue
    
    /// Logger
    private let logger = OSLog(subsystem: "com.nextlevel", category: "ResourceManager")
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    private init() {
        self.resourceQueue = DispatchQueue(label: "com.nextlevel.resource", qos: .userInitiated)
        self.availableResources = SystemResources()
        self.constraints = ResourceConstraints()
        
        setupMonitoring()
        detectHardwareCapabilities()
    }
    
    // MARK: - Resource Allocation
    
    /// Request resources for camera configuration
    public func requestResources(for configuration: NextLevelCameraConfiguration,
                                priority: CameraPriority) -> Result<ResourceAllocation, ResourceError> {
        lock.lock()
        defer { lock.unlock() }
        
        // Calculate required resources
        let required = calculateRequiredResources(for: configuration)
        
        // Check availability
        guard canAllocate(resources: required) else {
            os_log("Insufficient resources for configuration", log: logger, type: .error)
            return .failure(.insufficientResources)
        }
        
        // Check thermal constraints
        if !thermalMonitor.canAccommodate(required) {
            os_log("Thermal constraints prevent allocation", log: logger, type: .default)
            return .failure(.thermalConstraints)
        }
        
        // Create allocation
        let allocation = ResourceAllocation(
            id: UUID(),
            position: configuration.cameraPosition,
            configuration: configuration,
            priority: priority,
            resources: required,
            timestamp: Date()
        )
        
        // Allocate resources
        allocateResources(allocation)
        
        os_log("Resources allocated for camera at position %d", log: logger, type: .info, configuration.cameraPosition.rawValue)
        
        return .success(allocation)
    }
    
    /// Release resources for camera
    public func releaseResources(for allocation: ResourceAllocation) {
        lock.lock()
        defer { lock.unlock() }
        
        guard let index = allocations.firstIndex(where: { $0.id == allocation.id }) else { return }
        
        let removed = allocations.remove(at: index)
        releaseResources(removed)
        
        os_log("Resources released for camera at position %d", log: logger, type: .info, removed.position.rawValue)
    }
    
    /// Update resource allocation
    public func updateAllocation(_ allocation: ResourceAllocation,
                               newConfiguration: NextLevelCameraConfiguration) -> Result<ResourceAllocation, ResourceError> {
        lock.lock()
        defer { lock.unlock() }
        
        // Calculate new requirements
        let newRequired = calculateRequiredResources(for: newConfiguration)
        
        // Check if we can accommodate the change
        let additionalRequired = newRequired.subtract(allocation.resources)
        
        guard canAllocate(resources: additionalRequired) else {
            return .failure(.insufficientResources)
        }
        
        // Update allocation
        if let index = allocations.firstIndex(where: { $0.id == allocation.id }) {
            var updated = allocation
            updated.configuration = newConfiguration
            updated.resources = newRequired
            allocations[index] = updated
            
            return .success(updated)
        }
        
        return .failure(.allocationNotFound)
    }
    
    // MARK: - Resource Calculation
    
    private func calculateRequiredResources(for configuration: NextLevelCameraConfiguration) -> RequiredResources {
        var resources = RequiredResources()
        
        // Calculate bandwidth
        if let videoConfig = configuration.videoConfiguration {
            let resolution = getResolution(for: videoConfig.preset)
            let pixelsPerSecond = resolution.width * resolution.height * configuration.preferredFrameRate
            let bitsPerPixel = 32 // Default 32-bit pixel format
            
            resources.bandwidth = Double(pixelsPerSecond * bitsPerPixel) / (1024 * 1024) // Mbps
            resources.bandwidth += Double(videoConfig.bitRate) / (1024 * 1024) // Add encoding overhead
        }
        
        // Calculate memory
        resources.memory = calculateMemoryRequirement(for: configuration)
        
        // Calculate CPU
        resources.cpuUsage = calculateCPURequirement(for: configuration)
        
        // Calculate GPU
        resources.gpuUsage = calculateGPURequirement(for: configuration)
        
        // Calculate power
        resources.powerUsage = calculatePowerRequirement(for: configuration)
        
        return resources
    }
    
    private func calculateMemoryRequirement(for configuration: NextLevelCameraConfiguration) -> Int64 {
        var memory: Int64 = 0
        
        if let videoConfig = configuration.videoConfiguration {
            let resolution = getResolution(for: videoConfig.preset)
            let bytesPerPixel = 4 // Assuming 32-bit pixel format
            let bufferSize = resolution.width * resolution.height * bytesPerPixel
            let bufferCount = 10 // Typical buffer pool size
            
            memory += Int64(bufferSize * bufferCount)
        }
        
        if configuration.photoConfiguration != nil {
            memory += 100 * 1024 * 1024 // 100MB for photo capture
        }
        
        return memory
    }
    
    private func calculateCPURequirement(for configuration: NextLevelCameraConfiguration) -> Double {
        var cpu = 0.0
        
        // Base CPU for capture
        cpu += 5.0
        
        // Video encoding
        if let videoConfig = configuration.videoConfiguration {
            let resolution = getResolution(for: videoConfig.preset)
            let megapixels = Double(resolution.width * resolution.height) / 1_000_000
            cpu += megapixels * Double(configuration.preferredFrameRate) * 0.5
        }
        
        // Stabilization
        if configuration.videoStabilizationMode != .off {
            cpu += 10.0
        }
        
        return cpu
    }
    
    private func calculateGPURequirement(for configuration: NextLevelCameraConfiguration) -> Double {
        var gpu = 0.0
        
        // Video processing
        if configuration.videoConfiguration != nil {
            gpu += 15.0
        }
        
        // HDR processing
        if configuration.isHDREnabled {
            gpu += 10.0
        }
        
        return gpu
    }
    
    private func calculatePowerRequirement(for configuration: NextLevelCameraConfiguration) -> Double {
        var power = 0.0
        
        // Base power for camera
        power += 100.0
        
        // Additional power for features
        if configuration.isHDREnabled {
            power += 50.0
        }
        
        if configuration.isLowLightBoostEnabled {
            power += 30.0
        }
        
        return power
    }
    
    // MARK: - Resource Checking
    
    private func canAllocate(resources: RequiredResources) -> Bool {
        let currentUsage = getCurrentResourceUsage()
        
        return (currentUsage.bandwidth + resources.bandwidth <= availableResources.maxBandwidth) &&
               (currentUsage.memory + resources.memory <= availableResources.maxMemory) &&
               (currentUsage.cpuUsage + resources.cpuUsage <= availableResources.maxCPU) &&
               (currentUsage.gpuUsage + resources.gpuUsage <= availableResources.maxGPU)
    }
    
    private func getCurrentResourceUsage() -> RequiredResources {
        return allocations.reduce(RequiredResources()) { result, allocation in
            result.add(allocation.resources)
        }
    }
    
    // MARK: - Resource Management
    
    private func allocateResources(_ allocation: ResourceAllocation) {
        allocations.append(allocation)
        updateResourceMetrics()
    }
    
    private func releaseResources(_ allocation: ResourceAllocation) {
        updateResourceMetrics()
    }
    
    private func updateResourceMetrics() {
        let usage = getCurrentResourceUsage()
        
        performanceMetrics.currentBandwidth = usage.bandwidth
        performanceMetrics.currentMemory = usage.memory
        performanceMetrics.currentCPU = usage.cpuUsage
        performanceMetrics.currentGPU = usage.gpuUsage
        performanceMetrics.lastUpdate = Date()
    }
    
    // MARK: - Monitoring
    
    private func setupMonitoring() {
        // Monitor thermal state
        thermalMonitor.onThermalStateChange = { [weak self] state in
            self?.handleThermalStateChange(state)
        }
        
        thermalMonitor.startMonitoring()
    }
    
    private func detectHardwareCapabilities() {
        let capabilities = hardwareDetector.detectCapabilities()
        
        // Update available resources based on hardware
        availableResources.maxBandwidth = capabilities.maxBandwidth
        availableResources.maxMemory = capabilities.maxMemory
        availableResources.maxCPU = capabilities.maxCPU
        availableResources.maxGPU = capabilities.maxGPU
        
        // Update constraints
        constraints.maxSimultaneousCameras = capabilities.maxCameras
        constraints.supportedResolutions = capabilities.supportedResolutions
        constraints.supportedFrameRates = capabilities.supportedFrameRates
    }
    
    // MARK: - Thermal Management
    
    private func handleThermalStateChange(_ state: ProcessInfo.ThermalState) {
        lock.lock()
        defer { lock.unlock() }
        
        os_log("Thermal state changed to %@", log: logger, type: .info, state.description)
        
        // Get optimization recommendations
        let optimizations = optimizer.optimizeForThermalState(state, allocations: allocations)
        
        // Apply optimizations
        for optimization in optimizations {
            applyOptimization(optimization)
        }
    }
    
    private func applyOptimization(_ optimization: ResourceOptimization) {
        switch optimization.type {
        case .reduceFrameRate:
            if let allocationId = optimization.targetAllocation,
               let index = allocations.firstIndex(where: { $0.id == allocationId }) {
                var allocation = allocations[index]
                allocation.configuration.preferredFrameRate = optimization.value as? Int ?? 30
                allocations[index] = allocation
            }
            
        case .disableFeature:
            // Disable specific features like HDR
            break
            
        case .reduceQuality:
            // Reduce video quality
            break
            
        case .disableCamera:
            // Remove camera allocation
            if let allocationId = optimization.targetAllocation,
               let index = allocations.firstIndex(where: { $0.id == allocationId }) {
                let removed = allocations.remove(at: index)
                releaseResources(removed)
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Get current resource usage
    public func getCurrentUsage() -> ResourceUsage {
        lock.lock()
        defer { lock.unlock() }
        
        let current = getCurrentResourceUsage()
        
        return ResourceUsage(
            bandwidth: current.bandwidth,
            memory: current.memory,
            cpu: current.cpuUsage,
            gpu: current.gpuUsage,
            thermalState: thermalMonitor.currentState,
            allocations: allocations
        )
    }
    
    /// Get resource constraints
    public func getConstraints() -> ResourceConstraints {
        return constraints
    }
    
    /// Check if configuration is supported
    public func isConfigurationSupported(_ configuration: NextLevelCameraConfiguration) -> Bool {
        let required = calculateRequiredResources(for: configuration)
        return canAllocate(resources: required)
    }
    
    /// Get optimization suggestions
    public func getOptimizationSuggestions() -> [OptimizationSuggestion] {
        return optimizer.getSuggestions(for: allocations, constraints: constraints)
    }
}

// MARK: - Supporting Types

/// Required resources for a camera configuration
public struct RequiredResources {
    var bandwidth: Double = 0 // Mbps
    var memory: Int64 = 0 // Bytes
    var cpuUsage: Double = 0 // Percentage
    var gpuUsage: Double = 0 // Percentage
    var powerUsage: Double = 0 // mW
    
    func add(_ other: RequiredResources) -> RequiredResources {
        var result = self
        result.bandwidth += other.bandwidth
        result.memory += other.memory
        result.cpuUsage += other.cpuUsage
        result.gpuUsage += other.gpuUsage
        result.powerUsage += other.powerUsage
        return result
    }
    
    func subtract(_ other: RequiredResources) -> RequiredResources {
        var result = self
        result.bandwidth -= other.bandwidth
        result.memory -= other.memory
        result.cpuUsage -= other.cpuUsage
        result.gpuUsage -= other.gpuUsage
        result.powerUsage -= other.powerUsage
        return result
    }
}

/// System resources
public struct SystemResources {
    var maxBandwidth: Double = 400 // Mbps
    var maxMemory: Int64 = 2 * 1024 * 1024 * 1024 // 2GB
    var maxCPU: Double = 100 // Percentage
    var maxGPU: Double = 100 // Percentage
    var maxPower: Double = 5000 // mW
}

/// Resource allocation
public struct ResourceAllocation {
    let id: UUID
    let position: NextLevelDevicePosition
    var configuration: NextLevelCameraConfiguration
    let priority: CameraPriority
    var resources: RequiredResources
    let timestamp: Date
}

/// Resource constraints
public struct ResourceConstraints {
    var maxSimultaneousCameras: Int = 2
    var supportedResolutions: [String] = []
    var supportedFrameRates: [Int] = []
    var maxBitratePerCamera: Int = 100_000_000 // 100 Mbps
}

/// Resource usage
public struct ResourceUsage {
    let bandwidth: Double
    let memory: Int64
    let cpu: Double
    let gpu: Double
    let thermalState: ProcessInfo.ThermalState
    let allocations: [ResourceAllocation]
}

/// Resource performance metrics
internal struct ResourcePerformanceMetrics {
    var currentBandwidth: Double = 0
    var currentMemory: Int64 = 0
    var currentCPU: Double = 0
    var currentGPU: Double = 0
    var lastUpdate: Date = Date()
}

/// Resource optimization
public struct ResourceOptimization {
    enum OptimizationType {
        case reduceFrameRate
        case disableFeature
        case reduceQuality
        case disableCamera
    }
    
    let type: OptimizationType
    let targetAllocation: UUID?
    let value: Any?
    let reason: String
}

/// Optimization suggestion
public struct OptimizationSuggestion {
    let title: String
    let description: String
    let impact: String
    let priority: Int
}

/// Resource errors
public enum ResourceError: Error {
    case insufficientResources
    case thermalConstraints
    case allocationNotFound
    case hardwareNotSupported
}

// MARK: - Helpers

private func getResolution(for preset: AVCaptureSession.Preset) -> (width: Int, height: Int) {
    switch preset {
    case .hd4K3840x2160:
        return (3840, 2160)
    case .hd1920x1080:
        return (1920, 1080)
    case .hd1280x720:
        return (1280, 720)
    case .vga640x480:
        return (640, 480)
    default:
        return (1920, 1080)
    }
}

private func getBitsPerPixel(for pixelFormat: OSType) -> Int {
    switch pixelFormat {
    case kCVPixelFormatType_32BGRA:
        return 32
    case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
        return 12
    default:
        return 32
    }
}

// MARK: - ProcessInfo.ThermalState Extension

extension ProcessInfo.ThermalState {
    var description: String {
        switch self {
        case .nominal:
            return "Nominal"
        case .fair:
            return "Fair"
        case .serious:
            return "Serious"
        case .critical:
            return "Critical"
        @unknown default:
            return "Unknown"
        }
    }
}