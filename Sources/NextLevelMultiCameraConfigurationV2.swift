//
//  NextLevelMultiCameraConfigurationV2.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

/// Multi-camera output mode
public enum MultiCameraOutputModeV2: Int {
    case separate       // Separate outputs for each camera
    case combined       // Picture-in-picture or side-by-side
    case custom        // User-defined composition
}

/// Multi-camera recording mode
public enum MultiCameraRecordingModeV2: Int {
    case separate      // Creates separate video files
    case combined      // Single file with multiple tracks
    case composited    // Single composed video file
}

/// Camera priority for resource management
public enum CameraPriority: Int {
    case essential = 100    // Never disabled
    case high = 75         // Disabled only in critical thermal state
    case medium = 50       // Disabled in serious thermal state
    case low = 25          // First to be disabled
}

/// Enhanced multi-camera configuration supporting independent camera settings
public class NextLevelMultiCameraConfigurationV2: NSObject {
    
    // MARK: - Properties
    
    /// Individual camera configurations mapped by position
    public var cameraConfigurations: [NextLevelDevicePosition: NextLevelCameraConfiguration] = [:]
    
    /// Camera priorities for thermal management
    public var cameraPriorities: [NextLevelDevicePosition: CameraPriority] = [:]
    
    /// Audio configuration (shared across all cameras)
    public var audioConfiguration: NextLevelAudioConfiguration?
    
    /// Audio source camera position
    public var audioSource: NextLevelDevicePosition? = .back
    
    /// Enable multiple audio sources (experimental)
    public var enableMultiAudioSources: Bool = false
    
    /// Output mode for multi-camera capture
    public var outputMode: MultiCameraOutputModeV2 = .separate
    
    /// Recording mode for video capture
    public var recordingMode: MultiCameraRecordingModeV2 = .separate
    
    /// Maximum number of simultaneous cameras (device dependent)
    public var maximumSimultaneousCameras: Int = 2
    
    /// Enable automatic thermal management
    public var enableThermalManagement: Bool = true
    
    /// Enable automatic resource optimization
    public var enableResourceOptimization: Bool = true
    
    /// Custom composition settings (for .custom output mode)
    public var customCompositionSettings: [String: Any]?
    
    // MARK: - Computed Properties
    
    /// All configured camera positions
    public var configuredPositions: Set<NextLevelDevicePosition> {
        return Set(cameraConfigurations.keys)
    }
    
    /// Number of configured cameras
    public var cameraCount: Int {
        return cameraConfigurations.count
    }
    
    /// Check if configuration has video cameras
    public var hasVideoCameras: Bool {
        return cameraConfigurations.values.contains { config in
            config.captureMode == .video || config.captureMode == .multiCameraWithoutAudio
        }
    }
    
    /// Check if configuration has photo cameras
    public var hasPhotoCameras: Bool {
        return cameraConfigurations.values.contains { config in
            config.captureMode == .photo
        }
    }
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
        setupDefaultPriorities()
    }
    
    private func setupDefaultPriorities() {
        // Set default priorities based on position
        cameraPriorities[.back] = .essential
        cameraPriorities[.front] = .medium
    }
    
    // MARK: - Configuration Management
    
    /// Add or update a camera configuration
    public func setCamera(_ configuration: NextLevelCameraConfiguration,
                         priority: CameraPriority = .medium) {
        cameraConfigurations[configuration.cameraPosition] = configuration
        cameraPriorities[configuration.cameraPosition] = priority
    }
    
    /// Remove a camera configuration
    public func removeCamera(at position: NextLevelDevicePosition) {
        cameraConfigurations.removeValue(forKey: position)
        cameraPriorities.removeValue(forKey: position)
    }
    
    /// Get camera configuration for a position
    public func cameraConfiguration(at position: NextLevelDevicePosition) -> NextLevelCameraConfiguration? {
        return cameraConfigurations[position]
    }
    
    /// Update camera configuration
    public func updateCamera(at position: NextLevelDevicePosition,
                           changes: (inout NextLevelCameraConfiguration) -> Void) {
        guard var config = cameraConfigurations[position] else { return }
        changes(&config)
        cameraConfigurations[position] = config
    }
    
    // MARK: - Validation
    
    /// Validates the entire configuration
    public func validate() -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        // Check camera count
        if cameraConfigurations.isEmpty {
            errors.append("No cameras configured")
        }
        
        if cameraConfigurations.count > maximumSimultaneousCameras {
            errors.append("Too many cameras configured. Maximum is \(maximumSimultaneousCameras)")
        }
        
        // Validate individual camera configurations
        for (position, config) in cameraConfigurations {
            let (isValid, configErrors) = config.validate()
            if !isValid {
                errors.append(contentsOf: configErrors.map { "\(position): \($0)" })
            }
        }
        
        // Check for mixed capture modes compatibility
        if hasVideoCameras && hasPhotoCameras {
            if outputMode != .separate {
                errors.append("Mixed video/photo capture requires separate output mode")
            }
        }
        
        // Validate audio configuration
        if let audioSource = audioSource {
            if !configuredPositions.contains(audioSource) {
                errors.append("Audio source camera not configured")
            }
        }
        
        // Check for duplicate lens types at same position
        var positionLensMap: [NextLevelDevicePosition: Set<NextLevelLensType>] = [:]
        for (position, config) in cameraConfigurations {
            if positionLensMap[position] == nil {
                positionLensMap[position] = Set()
            }
            if positionLensMap[position]!.contains(config.lensType) {
                errors.append("Duplicate lens type \(config.lensType) at position \(position)")
            }
            positionLensMap[position]!.insert(config.lensType)
        }
        
        return (errors.isEmpty, errors)
    }
    
    // MARK: - Device Optimization
    
    /// Optimizes configuration for current device capabilities
    public func optimizeForDevice() {
        guard enableResourceOptimization else { return }
        
        let device = UIDevice.current
        let deviceModel = device.model
        
        // Adjust maximum cameras based on device
        if deviceModel.contains("iPhone") {
            if device.userInterfaceIdiom == UIUserInterfaceIdiom.phone {
                // iPhone 15 Pro and later support 3+ cameras
                if isNeweriPhone() {
                    maximumSimultaneousCameras = 3
                } else {
                    maximumSimultaneousCameras = 2
                }
            }
        }
        
        // Optimize individual camera settings
        for (position, var config) in cameraConfigurations {
            // Reduce frame rate for secondary cameras if needed
            if position != .back && config.preferredFrameRate > 30 {
                config.preferredFrameRate = 30
                cameraConfigurations[position] = config
            }
            
            // Disable HDR on secondary cameras to save resources
            if cameraPriorities[position]?.rawValue ?? 50 < CameraPriority.high.rawValue {
                config.isHDREnabled = false
                cameraConfigurations[position] = config
            }
        }
    }
    
    /// Adjusts configuration based on thermal state
    public func adjustForThermalState(_ state: ProcessInfo.ThermalState) {
        guard enableThermalManagement else { return }
        
        switch state {
        case .nominal:
            // No adjustments needed
            break
            
        case .fair:
            // Reduce non-essential camera frame rates
            reduceCameraFrameRates(below: .high, to: 24)
            
        case .serious:
            // Disable low priority cameras
            disableCameras(below: .high)
            // Reduce remaining camera frame rates
            reduceCameraFrameRates(below: .essential, to: 15)
            
        case .critical:
            // Keep only essential cameras
            disableCameras(below: .essential)
            // Minimize frame rates
            reduceCameraFrameRates(below: .essential, to: 15)
            
        @unknown default:
            break
        }
    }
    
    // MARK: - Helper Methods
    
    private func isNeweriPhone() -> Bool {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        // iPhone 15 Pro and later
        return identifier.contains("iPhone16") || identifier.contains("iPhone17")
    }
    
    private func reduceCameraFrameRates(below priority: CameraPriority, to frameRate: Int) {
        for (position, config) in cameraConfigurations {
            guard let cameraPriority = cameraPriorities[position],
                  cameraPriority.rawValue < priority.rawValue else { continue }
            
            var updatedConfig = config
            updatedConfig.preferredFrameRate = min(updatedConfig.preferredFrameRate, frameRate)
            cameraConfigurations[position] = updatedConfig
        }
    }
    
    private func disableCameras(below priority: CameraPriority) {
        let positionsToRemove = cameraConfigurations.keys.filter { position in
            guard let cameraPriority = cameraPriorities[position] else { return false }
            return cameraPriority.rawValue < priority.rawValue
        }
        
        for position in positionsToRemove {
            cameraConfigurations.removeValue(forKey: position)
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Creates a configuration for 4K video + HD photo capture
    public static func video4KPlusHDPhoto() -> NextLevelMultiCameraConfigurationV2 {
        let config = NextLevelMultiCameraConfigurationV2()
        
        // 4K video on back wide camera
        let videoCamera = NextLevelCameraConfiguration.video4K(position: .back,
                                                               lensType: .wideAngleCamera)
        config.setCamera(videoCamera, priority: .essential)
        
        // HD photo on back camera (different lens type)
        let photoCamera = NextLevelCameraConfiguration.photoHD(position: .back,
                                                               lensType: .ultraWideAngleCamera)
        config.setCamera(photoCamera, priority: .high)
        
        // Configure audio from video camera
        config.audioSource = .back
        
        // Use separate outputs for different capture modes
        config.outputMode = .separate
        
        return config
    }
    
    /// Creates a configuration for dual video recording
    public static func dualVideoRecording() -> NextLevelMultiCameraConfigurationV2 {
        let config = NextLevelMultiCameraConfigurationV2()
        
        // Back camera at 4K
        let backCamera = NextLevelCameraConfiguration.video4K(position: .back,
                                                             lensType: .wideAngleCamera)
        config.setCamera(backCamera, priority: .essential)
        
        // Front camera at 1080p
        var frontCamera = NextLevelCameraConfiguration(cameraPosition: .front,
                                                       lensType: .wideAngleCamera,
                                                       captureMode: .video)
        let videoConfig = NextLevelVideoConfiguration()
        videoConfig.preset = .hd1920x1080
        videoConfig.bitRate = 10_000_000 // 10 Mbps
        frontCamera.videoConfiguration = videoConfig
        config.setCamera(frontCamera, priority: .medium)
        
        // Combined output mode for dual recording
        config.outputMode = .combined
        config.recordingMode = .composited
        
        return config
    }
}

// MARK: - Debugging

extension NextLevelMultiCameraConfigurationV2 {
    
    /// Debug description of configuration
    public override var description: String {
        var desc = "NextLevelMultiCameraConfigurationV2:\n"
        desc += "  Cameras: \(cameraCount)\n"
        desc += "  Output Mode: \(outputMode)\n"
        desc += "  Recording Mode: \(recordingMode)\n"
        
        for (position, config) in cameraConfigurations {
            desc += "  \(position): \(config.lensType) - \(config.captureMode)\n"
            if let priority = cameraPriorities[position] {
                desc += "    Priority: \(priority)\n"
            }
        }
        
        return desc
    }
}