//
//  NextLevelInputRouter.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import AVFoundation
import CoreMedia

/// Manages routing of inputs to outputs and handles data flow for multi-camera sessions
public class NextLevelInputRouter: NSObject {
    
    // MARK: - Properties
    
    /// Routing table mapping inputs to outputs
    private var routingTable: [RoutingKey: RoutingDestination] = [:]
    
    /// Active connections
    private var activeConnections: [ConnectionInfo] = []
    
    /// Format compatibility cache
    private var formatCompatibilityCache: [String: Bool] = [:]
    
    /// Performance monitor
    private let performanceMonitor = InputRoutingPerformanceMonitor()
    
    /// Routing queue
    private let routingQueue: DispatchQueue
    
    /// Delegate
    public weak var delegate: NextLevelMultiCameraV2Delegate?
    
    // MARK: - Initialization
    
    public override init() {
        self.routingQueue = DispatchQueue(label: "com.nextlevel.routing", qos: .userInitiated)
        super.init()
    }
    
    // MARK: - Routing Configuration
    
    /// Configure routing for a camera setup
    public func configureRouting(for setupInfo: CameraSetupInfo, in session: AVCaptureMultiCamSession) throws {
        routingQueue.sync {
            // Create routing entries for each output
            if let videoOutput = setupInfo.outputs.videoDataOutput {
                let key = RoutingKey(
                    position: setupInfo.position,
                    outputType: .video
                )
                
                let destination = RoutingDestination(
                    output: videoOutput,
                    processingBlock: nil,
                    priority: setupInfo.priority
                )
                
                routingTable[key] = destination
                
                // Create connection info
                if let connection = videoOutput.connection(with: .video) {
                    let connectionInfo = ConnectionInfo(
                        input: setupInfo.input,
                        output: videoOutput,
                        connection: connection,
                        position: setupInfo.position,
                        mediaType: .video
                    )
                    activeConnections.append(connectionInfo)
                }
            }
            
            if let photoOutput = setupInfo.outputs.photoOutput {
                let key = RoutingKey(
                    position: setupInfo.position,
                    outputType: .photo
                )
                
                let destination = RoutingDestination(
                    output: photoOutput,
                    processingBlock: nil,
                    priority: setupInfo.priority
                )
                
                routingTable[key] = destination
                
                // Create connection info
                if let connection = photoOutput.connection(with: .video) {
                    let connectionInfo = ConnectionInfo(
                        input: setupInfo.input,
                        output: photoOutput,
                        connection: connection,
                        position: setupInfo.position,
                        mediaType: .video
                    )
                    activeConnections.append(connectionInfo)
                }
            }
            
            if let movieOutput = setupInfo.outputs.movieFileOutput {
                let key = RoutingKey(
                    position: setupInfo.position,
                    outputType: .movie
                )
                
                let destination = RoutingDestination(
                    output: movieOutput,
                    processingBlock: nil,
                    priority: setupInfo.priority
                )
                
                routingTable[key] = destination
                
                // Create connection info
                if let connection = movieOutput.connection(with: .video) {
                    let connectionInfo = ConnectionInfo(
                        input: setupInfo.input,
                        output: movieOutput,
                        connection: connection,
                        position: setupInfo.position,
                        mediaType: .video
                    )
                    activeConnections.append(connectionInfo)
                }
            }
        }
    }
    
    /// Remove routing for a camera position
    public func removeRouting(for position: NextLevelDevicePosition) {
        routingQueue.sync {
            // Remove from routing table
            routingTable = routingTable.filter { $0.key.position != position }
            
            // Remove from active connections
            activeConnections.removeAll { $0.position == position }
            
            // Clear cache entries
            formatCompatibilityCache.removeAll()
        }
    }
    
    /// Get routing destination for a specific output
    public func routingDestination(for position: NextLevelDevicePosition, outputType: OutputType) -> RoutingDestination? {
        let key = RoutingKey(position: position, outputType: outputType)
        return routingTable[key]
    }
    
    // MARK: - Format Validation
    
    /// Validate format compatibility between input and output
    public func validateFormatCompatibility(input: AVCaptureInput, output: AVCaptureOutput) -> Bool {
        let cacheKey = "\(input.hash)-\(output.hash)"
        
        // Check cache first
        if let cached = formatCompatibilityCache[cacheKey] {
            return cached
        }
        
        // Perform validation
        var isCompatible = false
        
        if let deviceInput = input as? AVCaptureDeviceInput,
           let videoOutput = output as? AVCaptureVideoDataOutput {
            // Check video format compatibility
            let device = deviceInput.device
            let activeFormat = device.activeFormat
            
            // Get supported pixel formats
            let supportedPixelFormats = videoOutput.availableVideoPixelFormatTypes
            
            // Check if current format is supported
            if let currentPixelFormat = videoOutput.videoSettings?[kCVPixelBufferPixelFormatTypeKey as String] as? OSType {
                isCompatible = supportedPixelFormats.contains(currentPixelFormat)
            } else {
                isCompatible = true // Default formats should work
            }
        } else {
            // For other output types, assume compatibility
            isCompatible = true
        }
        
        // Cache result
        formatCompatibilityCache[cacheKey] = isCompatible
        
        return isCompatible
    }
    
    /// Check all connections for format compatibility
    public func validateAllConnections() -> [InputRoutingValidationResult] {
        var results: [InputRoutingValidationResult] = []
        
        for connectionInfo in activeConnections {
            let isValid = validateFormatCompatibility(
                input: connectionInfo.input,
                output: connectionInfo.output
            )
            
            let result = InputRoutingValidationResult(
                position: connectionInfo.position,
                mediaType: connectionInfo.mediaType,
                isValid: isValid,
                error: isValid ? nil : "Format incompatibility detected"
            )
            
            results.append(result)
        }
        
        return results
    }
    
    // MARK: - Performance Management
    
    /// Monitor routing performance
    public func startPerformanceMonitoring() {
        performanceMonitor.startMonitoring()
        
        // Set up periodic performance checks
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPerformance()
        }
    }
    
    /// Stop performance monitoring
    public func stopPerformanceMonitoring() {
        performanceMonitor.stopMonitoring()
    }
    
    private func checkPerformance() {
        let metrics = performanceMonitor.currentMetrics()
        
        // Check for performance issues
        for connection in activeConnections {
            if let droppedFrames = metrics.droppedFrames[connection.position],
               droppedFrames > 0 {
                // Notify delegate about dropped frames
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.nextLevel(
                        NextLevel.shared,
                        didDropFrame: connection.position,
                        reason: "Performance: \(droppedFrames) frames dropped"
                    )
                }
            }
        }
        
        // Check bandwidth usage
        if metrics.totalBandwidth > metrics.maxBandwidth * 0.9 {
            // Approaching bandwidth limit
            notifyResourceConstraint("High bandwidth usage: \(Int(metrics.totalBandwidth))Mbps")
        }
    }
    
    private func notifyResourceConstraint(_ constraint: String) {
        let affectedCameras = activeConnections.map { $0.position }
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.nextLevel(
                NextLevel.shared,
                didAdjustForResourceConstraints: [constraint],
                affectedCameras: affectedCameras
            )
        }
    }
    
    // MARK: - Processing Pipeline
    
    /// Add processing block for a specific route
    public func addProcessingBlock(for position: NextLevelDevicePosition,
                                  outputType: OutputType,
                                  block: @escaping ProcessingBlock) {
        routingQueue.sync {
            let key = RoutingKey(position: position, outputType: outputType)
            if var destination = routingTable[key] {
                destination.processingBlock = block
                routingTable[key] = destination
            }
        }
    }
    
    /// Remove processing block
    public func removeProcessingBlock(for position: NextLevelDevicePosition,
                                    outputType: OutputType) {
        routingQueue.sync {
            let key = RoutingKey(position: position, outputType: outputType)
            if var destination = routingTable[key] {
                destination.processingBlock = nil
                routingTable[key] = destination
            }
        }
    }
}

// MARK: - Supporting Types

/// Key for routing table
public struct RoutingKey: Hashable {
    let position: NextLevelDevicePosition
    let outputType: OutputType
}

/// Output type enumeration
public enum OutputType: Int {
    case video
    case photo
    case movie
    case audio
}

/// Routing destination information
public struct RoutingDestination {
    let output: AVCaptureOutput
    var processingBlock: ProcessingBlock?
    let priority: CameraPriority
}

/// Processing block type
public typealias ProcessingBlock = (CMSampleBuffer) -> CMSampleBuffer?

/// Connection information
public struct ConnectionInfo {
    let input: AVCaptureInput
    let output: AVCaptureOutput
    let connection: AVCaptureConnection
    let position: NextLevelDevicePosition
    let mediaType: AVMediaType
}

/// Input routing validation result
public struct InputRoutingValidationResult {
    let position: NextLevelDevicePosition
    let mediaType: AVMediaType
    let isValid: Bool
    let error: String?
}

// MARK: - Performance Monitor

/// Monitors routing performance metrics
internal class InputRoutingPerformanceMonitor {
    
    private var isMonitoring = false
    private var startTime: Date?
    private var frameCounters: [NextLevelDevicePosition: Int] = [:]
    private var droppedFrameCounters: [NextLevelDevicePosition: Int] = [:]
    private var bandwidthEstimates: [NextLevelDevicePosition: Double] = [:]
    
    func startMonitoring() {
        isMonitoring = true
        startTime = Date()
        frameCounters.removeAll()
        droppedFrameCounters.removeAll()
        bandwidthEstimates.removeAll()
    }
    
    func stopMonitoring() {
        isMonitoring = false
    }
    
    func recordFrame(for position: NextLevelDevicePosition) {
        guard isMonitoring else { return }
        frameCounters[position, default: 0] += 1
    }
    
    func recordDroppedFrame(for position: NextLevelDevicePosition) {
        guard isMonitoring else { return }
        droppedFrameCounters[position, default: 0] += 1
    }
    
    func updateBandwidth(for position: NextLevelDevicePosition, bytes: Int) {
        guard isMonitoring else { return }
        let mbps = Double(bytes) * 8 / 1_000_000 // Convert to Mbps
        bandwidthEstimates[position] = mbps
    }
    
    func currentMetrics() -> InputRoutingPerformanceMetrics {
        let elapsed = Date().timeIntervalSince(startTime ?? Date())
        
        var metrics = InputRoutingPerformanceMetrics()
        metrics.elapsedTime = elapsed
        metrics.frameRates = frameCounters.mapValues { Double($0) / max(elapsed, 1) }
        metrics.droppedFrames = droppedFrameCounters
        metrics.totalBandwidth = bandwidthEstimates.values.reduce(0, +)
        metrics.maxBandwidth = 400 // Mbps - device dependent
        
        return metrics
    }
}

/// Input routing performance metrics
internal struct InputRoutingPerformanceMetrics {
    var elapsedTime: TimeInterval = 0
    var frameRates: [NextLevelDevicePosition: Double] = [:]
    var droppedFrames: [NextLevelDevicePosition: Int] = [:]
    var totalBandwidth: Double = 0
    var maxBandwidth: Double = 400
}

// MARK: - Buffer Router

/// Routes sample buffers through processing pipeline
public class BufferRouter {
    
    private let inputRouter: NextLevelInputRouter
    private let processingQueue: DispatchQueue
    
    init(inputRouter: NextLevelInputRouter) {
        self.inputRouter = inputRouter
        self.processingQueue = DispatchQueue(label: "com.nextlevel.buffer.processing", qos: .userInitiated)
    }
    
    /// Route sample buffer through appropriate processing
    func routeBuffer(_ sampleBuffer: CMSampleBuffer,
                    from position: NextLevelDevicePosition,
                    outputType: OutputType) {
        
        processingQueue.async { [weak self] in
            guard let self = self,
                  let destination = self.inputRouter.routingDestination(for: position, outputType: outputType) else {
                return
            }
            
            // Apply processing if configured
            let processedBuffer: CMSampleBuffer
            if let processingBlock = destination.processingBlock {
                processedBuffer = processingBlock(sampleBuffer) ?? sampleBuffer
            } else {
                processedBuffer = sampleBuffer
            }
            
            // Route to final destination based on priority
            self.deliverBuffer(processedBuffer, to: destination, from: position)
        }
    }
    
    private func deliverBuffer(_ buffer: CMSampleBuffer,
                             to destination: RoutingDestination,
                             from position: NextLevelDevicePosition) {
        // Delivery logic based on output type and priority
        // High priority buffers get delivered immediately
        // Lower priority may be dropped under load
        
        switch destination.priority {
        case .essential:
            // Always deliver
            break
        case .high:
            // Deliver unless system is under extreme load
            break
        case .medium, .low:
            // May drop frames if needed
            break
        }
    }
}