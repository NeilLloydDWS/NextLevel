//
//  NextLevelMultiCameraBuilder.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import AVFoundation

// MARK: - Multi-Camera Configuration Builder

/// Builder pattern for creating multi-camera configurations
public class NextLevelMultiCameraBuilder {
    
    private var configuration = NextLevelMultiCameraConfigurationV2()
    private var validationErrors: [String] = []
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Camera Configuration
    
    /// Add a camera with video configuration
    /// - Parameters:
    ///   - position: Camera position
    ///   - lensType: Lens type
    ///   - preset: Video preset
    ///   - bitRate: Video bit rate
    ///   - frameRate: Frame rate
    ///   - priority: Camera priority
    /// - Returns: Builder instance for chaining
    @discardableResult
    public func addVideoCamera(position: NextLevelDevicePosition,
                              lensType: NextLevelLensType = .wideAngleCamera,
                              preset: AVCaptureSession.Preset = .hd1920x1080,
                              bitRate: Int = 10_000_000,
                              frameRate: Int = 30,
                              priority: CameraPriority = .medium) -> Self {
        var cameraConfig = NextLevelCameraConfiguration(
            cameraPosition: position,
            lensType: lensType,
            captureMode: .video
        )
        
        let videoConfig = NextLevelVideoConfiguration()
        videoConfig.preset = preset
        videoConfig.bitRate = bitRate
        cameraConfig.videoConfiguration = videoConfig
        cameraConfig.preferredFrameRate = frameRate
        
        configuration.setCamera(cameraConfig, priority: priority)
        
        return self
    }
    
    /// Add a camera with photo configuration
    /// - Parameters:
    ///   - position: Camera position
    ///   - lensType: Lens type
    ///   - preset: Photo preset
    ///   - priority: Camera priority
    /// - Returns: Builder instance for chaining
    @discardableResult
    public func addPhotoCamera(position: NextLevelDevicePosition,
                              lensType: NextLevelLensType = .wideAngleCamera,
                              codec: AVVideoCodecType = .hevc,
                              priority: CameraPriority = .medium) -> Self {
        var cameraConfig = NextLevelCameraConfiguration(
            cameraPosition: position,
            lensType: lensType,
            captureMode: .photo
        )
        
        let photoConfig = NextLevelPhotoConfiguration()
        photoConfig.codec = codec
        cameraConfig.photoConfiguration = photoConfig
        
        configuration.setCamera(cameraConfig, priority: priority)
        
        return self
    }
    
    /// Add a camera with mixed video/photo configuration
    /// - Parameters:
    ///   - position: Camera position
    ///   - lensType: Lens type
    ///   - videoPreset: Video preset
    ///   - photoPreset: Photo preset
    ///   - priority: Camera priority
    /// - Returns: Builder instance for chaining
    @discardableResult
    public func addMixedCamera(position: NextLevelDevicePosition,
                              lensType: NextLevelLensType = .wideAngleCamera,
                              videoPreset: AVCaptureSession.Preset = .hd1920x1080,
                              photoCodec: AVVideoCodecType = .hevc,
                              priority: CameraPriority = .medium) -> Self {
        var cameraConfig = NextLevelCameraConfiguration(
            cameraPosition: position,
            lensType: lensType,
            captureMode: .video
        )
        
        let videoConfig = NextLevelVideoConfiguration()
        videoConfig.preset = videoPreset
        cameraConfig.videoConfiguration = videoConfig
        
        let photoConfig = NextLevelPhotoConfiguration()
        photoConfig.codec = photoCodec
        cameraConfig.photoConfiguration = photoConfig
        
        configuration.setCamera(cameraConfig, priority: priority)
        
        return self
    }
    
    // MARK: - Camera Features
    
    /// Enable HDR for camera
    /// - Parameter position: Camera position
    /// - Returns: Builder instance for chaining
    @discardableResult
    public func enableHDR(for position: NextLevelDevicePosition) -> Self {
        if var camera = configuration.cameraConfigurations[position] {
            camera.isHDREnabled = true
            configuration.cameraConfigurations[position] = camera
        }
        return self
    }
    
    /// Set zoom factor for camera
    /// - Parameters:
    ///   - factor: Zoom factor
    ///   - position: Camera position
    /// - Returns: Builder instance for chaining
    @discardableResult
    public func setZoom(_ factor: Float, for position: NextLevelDevicePosition) -> Self {
        if var camera = configuration.cameraConfigurations[position] {
            camera.zoomFactor = factor
            configuration.cameraConfigurations[position] = camera
        }
        return self
    }
    
    /// Set stabilization mode
    /// - Parameters:
    ///   - mode: Stabilization mode
    ///   - position: Camera position
    /// - Returns: Builder instance for chaining
    @discardableResult
    public func setStabilization(_ mode: AVCaptureVideoStabilizationMode,
                                for position: NextLevelDevicePosition) -> Self {
        if var camera = configuration.cameraConfigurations[position] {
            camera.videoStabilizationMode = mode
            configuration.cameraConfigurations[position] = camera
        }
        return self
    }
    
    // MARK: - Global Settings
    
    /// Set maximum simultaneous cameras
    /// - Parameter count: Maximum camera count
    /// - Returns: Builder instance for chaining
    @discardableResult
    public func setMaxCameras(_ count: Int) -> Self {
        // configuration.maxSimultaneousCameras = count // TODO: Add this property
        return self
    }
    
    /// Enable automatic thermal management
    /// - Returns: Builder instance for chaining
    @discardableResult
    public func enableThermalManagement() -> Self {
        configuration.enableThermalManagement = true
        return self
    }
    
    /// Enable automatic resource optimization
    /// - Returns: Builder instance for chaining
    @discardableResult
    public func enableResourceOptimization() -> Self {
        configuration.enableResourceOptimization = true
        return self
    }
    
    // MARK: - Presets
    
    /// Apply dual camera preset
    /// - Returns: Builder instance for chaining
    @discardableResult
    public func applyDualCameraPreset() -> Self {
        return addVideoCamera(position: NextLevelDevicePosition.back, priority: CameraPriority.high)
            .addVideoCamera(position: NextLevelDevicePosition.front, priority: CameraPriority.medium)
    }
    
    /// Apply professional video preset
    /// - Returns: Builder instance for chaining
    @discardableResult
    public func applyProfessionalVideoPreset() -> Self {
        return addVideoCamera(position: NextLevelDevicePosition.back,
                            lensType: NextLevelLensType.wideAngleCamera,
                            preset: AVCaptureSession.Preset.hd4K3840x2160,
                            bitRate: 50_000_000,
                            frameRate: 30,
                            priority: CameraPriority.high)
            .addVideoCamera(position: NextLevelDevicePosition.back,
                          lensType: NextLevelLensType.ultraWideAngleCamera,
                          preset: AVCaptureSession.Preset.hd1920x1080,
                          bitRate: 20_000_000,
                          frameRate: 30,
                          priority: CameraPriority.high)
            .enableHDR(for: NextLevelDevicePosition.back)
            .setStabilization(.cinematic, for: NextLevelDevicePosition.back)
    }
    
    /// Apply action camera preset
    /// - Returns: Builder instance for chaining
    @discardableResult
    public func applyActionCameraPreset() -> Self {
        return addVideoCamera(position: NextLevelDevicePosition.back,
                            preset: AVCaptureSession.Preset.hd1920x1080,
                            frameRate: 60,
                            priority: CameraPriority.high)
            .addVideoCamera(position: NextLevelDevicePosition.front,
                          preset: AVCaptureSession.Preset.hd1280x720,
                          frameRate: 30,
                          priority: CameraPriority.medium)
            .setStabilization(.standard, for: NextLevelDevicePosition.back)
            .setStabilization(.standard, for: NextLevelDevicePosition.front)
    }
    
    // MARK: - Validation
    
    /// Validate configuration
    /// - Returns: Validation result
    public func validate() -> ValidationResult {
        let detector = HardwareCapabilityDetector()
        let capabilities = detector.detectCapabilities()
        let limitationManager = HardwareLimitationManager(capabilities: capabilities)
        
        return limitationManager.validateConfiguration(configuration)
    }
    
    // MARK: - Build
    
    /// Build the configuration
    /// - Returns: Built configuration
    /// - Throws: Validation errors
    public func build() throws -> NextLevelMultiCameraConfigurationV2 {
        let validationResult = validate()
        
        if !validationResult.isValid {
            throw NextLevelError.invalidConfiguration(validationResult.errors.joined(separator: ", "))
        }
        
        return configuration
    }
    
    /// Build with fallback for unsupported configurations
    /// - Returns: Built configuration (with fallbacks applied if needed)
    public func buildWithFallback() -> NextLevelMultiCameraConfigurationV2 {
        let validationResult = validate()
        
        if validationResult.isValid {
            return configuration
        } else {
            // Apply fallback
            let detector = HardwareCapabilityDetector()
            let capabilities = detector.detectCapabilities()
            let limitationManager = HardwareLimitationManager(capabilities: capabilities)
            
            return limitationManager.getFallbackConfiguration(for: configuration)
        }
    }
}

// MARK: - Usage Examples

extension NextLevelMultiCameraBuilder {
    
    /// Example: Basic dual camera setup
    public static func basicDualCamera() throws -> NextLevelMultiCameraConfigurationV2 {
        return try NextLevelMultiCameraBuilder()
            .applyDualCameraPreset()
            .enableThermalManagement()
            .build()
    }
    
    /// Example: Professional video setup
    public static func professionalVideo() throws -> NextLevelMultiCameraConfigurationV2 {
        return try NextLevelMultiCameraBuilder()
            .applyProfessionalVideoPreset()
            .enableThermalManagement()
            .enableResourceOptimization()
            .setMaxCameras(2)
            .build()
    }
    
    /// Example: Custom setup for specific use case
    public static func customSetup() throws -> NextLevelMultiCameraConfigurationV2 {
        return try NextLevelMultiCameraBuilder()
            .addVideoCamera(position: NextLevelDevicePosition.back,
                          lensType: .wideAngleCamera,
                          preset: AVCaptureSession.Preset.hd4K3840x2160,
                          bitRate: 50_000_000,
                          frameRate: 30,
                          priority: CameraPriority.high)
            .addPhotoCamera(position: NextLevelDevicePosition.back,
                          lensType: NextLevelLensType.ultraWideAngleCamera,
                          codec: AVVideoCodecType.hevc,
                          priority: CameraPriority.high)
            .enableHDR(for: NextLevelDevicePosition.back)
            .setZoom(1.5, for: NextLevelDevicePosition.back)
            .enableThermalManagement()
            .build()
    }
}