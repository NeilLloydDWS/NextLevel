//
//  NextLevelThermalManager.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import os.log

/// Manages thermal state and provides adaptive responses
public class NextLevelThermalManager {
    
    // MARK: - Properties
    
    /// Thermal state monitor
    public let monitor: ThermalStateMonitor
    
    /// Thermal response strategies
    private var strategies: [ProcessInfo.ThermalState: ThermalStrategy] = [:]
    
    /// Active mitigations
    private var activeMitigations: [ThermalMitigation] = []
    
    /// Thermal history for predictive management
    private var thermalHistory: ThermalHistory
    
    /// Configuration
    private let configuration: ThermalConfiguration
    
    /// Delegate
    public weak var delegate: NextLevelMultiCameraV2Delegate?
    
    /// Logger
    private let logger = OSLog(subsystem: "com.nextlevel", category: "ThermalManager")
    
    /// Queue for thermal management
    private let thermalQueue: DispatchQueue
    
    // MARK: - Initialization
    
    public init(configuration: ThermalConfiguration = .default) {
        self.configuration = configuration
        self.monitor = ThermalStateMonitor()
        self.thermalHistory = ThermalHistory()
        self.thermalQueue = DispatchQueue(label: "com.nextlevel.thermal", qos: .userInitiated)
        
        setupStrategies()
        setupMonitoring()
    }
    
    // MARK: - Setup
    
    private func setupStrategies() {
        // Define strategies for each thermal state
        strategies[.nominal] = NominalStrategy()
        strategies[.fair] = FairStrategy()
        strategies[.serious] = SeriousStrategy()
        strategies[.critical] = CriticalStrategy()
    }
    
    private func setupMonitoring() {
        monitor.onThermalStateChange = { [weak self] newState in
            self?.handleThermalStateChange(newState)
        }
        
        monitor.startMonitoring()
    }
    
    // MARK: - Thermal State Management
    
    private func handleThermalStateChange(_ newState: ProcessInfo.ThermalState) {
        thermalQueue.async { [weak self] in
            guard let self = self else { return }
            
            os_log("Thermal state changed to: %@", log: self.logger, type: .info, newState.description)
            
            // Record in history
            self.thermalHistory.record(state: newState)
            
            // Get appropriate strategy
            guard let strategy = self.strategies[newState] else { return }
            
            // Generate mitigations
            let mitigations = strategy.generateMitigations(
                history: self.thermalHistory,
                configuration: self.configuration
            )
            
            // Apply mitigations
            self.applyMitigations(mitigations)
            
            // Notify delegate
            self.notifyThermalStateChange(newState, mitigations: mitigations)
        }
    }
    
    // MARK: - Mitigation Application
    
    private func applyMitigations(_ mitigations: [ThermalMitigation]) {
        // Remove previous mitigations that are superseded
        let supersededTypes = Set(mitigations.map { $0.type })
        activeMitigations.removeAll { supersededTypes.contains($0.type) }
        
        // Apply new mitigations
        for mitigation in mitigations {
            os_log("Applying thermal mitigation: %@", log: logger, type: .info, mitigation.description)
            
            switch mitigation.action {
            case .reduceFrameRate(let fps):
                applyFrameRateReduction(fps, priority: mitigation.priority)
                
            case .disableCamera(let priority):
                disableCamerasBelow(priority: priority)
                
            case .reduceResolution(let factor):
                applyResolutionReduction(factor)
                
            case .disableFeatures(let features):
                disableFeatures(features)
                
            case .enablePowerSaving:
                enablePowerSavingMode()
            }
            
            activeMitigations.append(mitigation)
        }
    }
    
    private func applyFrameRateReduction(_ targetFPS: Int, priority: CameraPriority) {
        // This would interface with the camera configurations
        // Implementation would update actual camera settings
        os_log("Reducing frame rate to %d fps for cameras below priority %d", 
               log: logger, type: .info, targetFPS, priority.rawValue)
    }
    
    private func disableCamerasBelow(priority: CameraPriority) {
        os_log("Disabling cameras below priority %d", log: logger, type: .default, priority.rawValue)
    }
    
    private func applyResolutionReduction(_ factor: Float) {
        os_log("Reducing resolution by factor %.2f", log: logger, type: .info, factor)
    }
    
    private func disableFeatures(_ features: Set<ThermalFeature>) {
        for feature in features {
            os_log("Disabling feature: %@", log: logger, type: .info, feature.rawValue)
        }
    }
    
    private func enablePowerSavingMode() {
        os_log("Enabling power saving mode", log: logger, type: .info)
    }
    
    // MARK: - Notification
    
    private func notifyThermalStateChange(_ state: ProcessInfo.ThermalState, mitigations: [ThermalMitigation]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let affectedCameras = self.getAffectedCameras(from: mitigations)
            self.delegate?.nextLevel(NextLevel.shared, didAdjustForThermalState: state, affectedCameras: affectedCameras)
        }
    }
    
    private func getAffectedCameras(from mitigations: [ThermalMitigation]) -> [NextLevelDevicePosition] {
        // This would be determined based on actual camera configurations
        return [.back, .front]
    }
    
    // MARK: - Public Methods
    
    /// Get current thermal state
    public var currentState: ProcessInfo.ThermalState {
        return monitor.currentState
    }
    
    /// Check if thermal state allows operation
    public func canPerformOperation(_ operation: ThermalOperation) -> Bool {
        let state = currentState
        
        switch state {
        case .nominal:
            return true
            
        case .fair:
            return operation != .enable4KRecording
            
        case .serious:
            return operation == .basicRecording || operation == .photoCapture
            
        case .critical:
            return operation == .photoCapture
            
        @unknown default:
            return false
        }
    }
    
    /// Get thermal headroom (0.0 - 1.0)
    public func thermalHeadroom() -> Float {
        switch currentState {
        case .nominal:
            return 1.0
        case .fair:
            return 0.7
        case .serious:
            return 0.3
        case .critical:
            return 0.1
        @unknown default:
            return 0.5
        }
    }
    
    /// Get active mitigations
    public func getActiveMitigations() -> [ThermalMitigation] {
        return activeMitigations
    }
    
    /// Predict thermal state
    public func predictThermalState(for duration: TimeInterval) -> ProcessInfo.ThermalState {
        return thermalHistory.predictState(after: duration)
    }
}

// MARK: - Thermal State Monitor

public class ThermalStateMonitor {
    
    public var onThermalStateChange: ((ProcessInfo.ThermalState) -> Void)?
    
    private(set) public var currentState: ProcessInfo.ThermalState = .nominal
    private var timer: Timer?
    private let processInfo = ProcessInfo.processInfo
    
    public func startMonitoring() {
        currentState = processInfo.thermalState
        
        // Monitor thermal state changes
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkThermalState()
        }
        
        // Also observe notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateDidChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }
    
    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self)
    }
    
    private func checkThermalState() {
        let newState = processInfo.thermalState
        if newState != currentState {
            currentState = newState
            onThermalStateChange?(newState)
        }
    }
    
    @objc private func thermalStateDidChange(_ notification: Notification) {
        checkThermalState()
    }
    
    public func canAccommodate(_ resources: RequiredResources) -> Bool {
        switch currentState {
        case .nominal:
            return true
            
        case .fair:
            // Allow up to 80% of max resources
            return resources.cpuUsage < 80 && resources.gpuUsage < 80
            
        case .serious:
            // Allow up to 50% of max resources
            return resources.cpuUsage < 50 && resources.gpuUsage < 50
            
        case .critical:
            // Minimal resources only
            return resources.cpuUsage < 20 && resources.gpuUsage < 20
            
        @unknown default:
            return false
        }
    }
}

// MARK: - Thermal Strategies

protocol ThermalStrategy {
    func generateMitigations(history: ThermalHistory, configuration: ThermalConfiguration) -> [ThermalMitigation]
}

struct NominalStrategy: ThermalStrategy {
    func generateMitigations(history: ThermalHistory, configuration: ThermalConfiguration) -> [ThermalMitigation] {
        // No mitigations needed in nominal state
        return []
    }
}

struct FairStrategy: ThermalStrategy {
    func generateMitigations(history: ThermalHistory, configuration: ThermalConfiguration) -> [ThermalMitigation] {
        var mitigations: [ThermalMitigation] = []
        
        // Reduce non-essential camera frame rates
        mitigations.append(
            ThermalMitigation(
                type: .frameRateReduction,
                action: .reduceFrameRate(fps: 24),
                priority: .medium,
                description: "Reduce frame rate to 24fps for medium priority cameras"
            )
        )
        
        // Disable power-hungry features
        mitigations.append(
            ThermalMitigation(
                type: .featureDisable,
                action: .disableFeatures([.hdr, .lowLightBoost]),
                priority: .low,
                description: "Disable HDR and low light boost"
            )
        )
        
        return mitigations
    }
}

struct SeriousStrategy: ThermalStrategy {
    func generateMitigations(history: ThermalHistory, configuration: ThermalConfiguration) -> [ThermalMitigation] {
        var mitigations: [ThermalMitigation] = []
        
        // Disable low priority cameras
        mitigations.append(
            ThermalMitigation(
                type: .cameraDisable,
                action: .disableCamera(priority: .low),
                priority: .low,
                description: "Disable low priority cameras"
            )
        )
        
        // Reduce frame rate for all cameras
        mitigations.append(
            ThermalMitigation(
                type: .frameRateReduction,
                action: .reduceFrameRate(fps: 15),
                priority: .high,
                description: "Reduce frame rate to 15fps for all cameras"
            )
        )
        
        // Reduce resolution if needed
        if configuration.allowResolutionReduction {
            mitigations.append(
                ThermalMitigation(
                    type: .resolutionReduction,
                    action: .reduceResolution(factor: 0.75),
                    priority: .medium,
                    description: "Reduce resolution by 25%"
                )
            )
        }
        
        return mitigations
    }
}

struct CriticalStrategy: ThermalStrategy {
    func generateMitigations(history: ThermalHistory, configuration: ThermalConfiguration) -> [ThermalMitigation] {
        var mitigations: [ThermalMitigation] = []
        
        // Keep only essential cameras
        mitigations.append(
            ThermalMitigation(
                type: .cameraDisable,
                action: .disableCamera(priority: .medium),
                priority: .medium,
                description: "Disable all non-essential cameras"
            )
        )
        
        // Minimal frame rate
        mitigations.append(
            ThermalMitigation(
                type: .frameRateReduction,
                action: .reduceFrameRate(fps: 10),
                priority: .essential,
                description: "Reduce frame rate to 10fps"
            )
        )
        
        // Enable power saving
        mitigations.append(
            ThermalMitigation(
                type: .powerSaving,
                action: .enablePowerSaving,
                priority: .essential,
                description: "Enable aggressive power saving"
            )
        )
        
        return mitigations
    }
}

// MARK: - Supporting Types

/// Thermal mitigation action
public struct ThermalMitigation {
    enum MitigationType {
        case frameRateReduction
        case cameraDisable
        case resolutionReduction
        case featureDisable
        case powerSaving
    }
    
    enum Action {
        case reduceFrameRate(fps: Int)
        case disableCamera(priority: CameraPriority)
        case reduceResolution(factor: Float)
        case disableFeatures(Set<ThermalFeature>)
        case enablePowerSaving
    }
    
    let type: MitigationType
    let action: Action
    let priority: CameraPriority
    let description: String
}

/// Thermal features that can be disabled
public enum ThermalFeature: String {
    case hdr = "HDR"
    case lowLightBoost = "Low Light Boost"
    case stabilization = "Video Stabilization"
    case highFrameRate = "High Frame Rate"
    case depth = "Depth Capture"
}

/// Thermal operations
public enum ThermalOperation {
    case enable4KRecording
    case enableMultiCamera
    case enableHDR
    case basicRecording
    case photoCapture
}

/// Thermal configuration
public struct ThermalConfiguration {
    var allowResolutionReduction: Bool = true
    var allowFeatureDisabling: Bool = true
    var minimumFrameRate: Int = 10
    var priorityThreshold: CameraPriority = .medium
    
    public static let `default` = ThermalConfiguration()
}

/// Thermal history tracking
public class ThermalHistory {
    private var history: [(state: ProcessInfo.ThermalState, timestamp: Date)] = []
    private let maxHistorySize = 100
    
    func record(state: ProcessInfo.ThermalState) {
        history.append((state, Date()))
        
        // Trim history if needed
        if history.count > maxHistorySize {
            history.removeFirst()
        }
    }
    
    func predictState(after duration: TimeInterval) -> ProcessInfo.ThermalState {
        // Simple prediction based on recent trend
        guard history.count >= 2 else { return .nominal }
        
        let recentStates = history.suffix(10)
        let criticalCount = recentStates.filter { $0.state == .critical }.count
        let seriousCount = recentStates.filter { $0.state == .serious }.count
        
        if criticalCount > 5 {
            return .critical
        } else if seriousCount > 5 {
            return .serious
        } else if recentStates.last?.state == .fair {
            return .fair
        }
        
        return .nominal
    }
    
    func averageDuration(in state: ProcessInfo.ThermalState) -> TimeInterval {
        var durations: [TimeInterval] = []
        var startTime: Date?
        var currentState: ProcessInfo.ThermalState?
        
        for entry in history {
            if entry.state == state && currentState != state {
                startTime = entry.timestamp
                currentState = state
            } else if entry.state != state && currentState == state, let start = startTime {
                durations.append(entry.timestamp.timeIntervalSince(start))
                currentState = entry.state
            }
        }
        
        guard !durations.isEmpty else { return 0 }
        return durations.reduce(0, +) / Double(durations.count)
    }
}