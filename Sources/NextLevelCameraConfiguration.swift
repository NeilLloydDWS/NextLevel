//
//  NextLevelCameraConfiguration.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import AVFoundation

/// Individual camera configuration for multi-camera sessions
public struct NextLevelCameraConfiguration {
    
    // MARK: - Properties
    
    /// Camera position (back, front, etc.)
    public let cameraPosition: NextLevelDevicePosition
    
    /// Lens type (wide, ultra-wide, telephoto)
    public let lensType: NextLevelLensType
    
    /// Capture mode for this camera
    public let captureMode: NextLevelCaptureMode
    
    /// Video configuration (optional, required if captureMode is .video)
    public var videoConfiguration: NextLevelVideoConfiguration?
    
    /// Photo configuration (optional, required if captureMode is .photo)
    public var photoConfiguration: NextLevelPhotoConfiguration?
    
    /// Camera-specific exposure mode
    public var exposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure
    
    /// Camera-specific focus mode  
    public var focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus
    
    /// Zoom factor for this camera
    public var zoomFactor: Float = 1.0
    
    /// Camera orientation override
    public var orientation: AVCaptureVideoOrientation = .portrait
    
    /// Video stabilization mode for this camera
    public var videoStabilizationMode: AVCaptureVideoStabilizationMode = .auto
    
    /// Frame rate for this camera (video mode only)
    public var preferredFrameRate: Int = 30
    
    /// Maximum recording duration for this camera (video mode only)
    public var maximumRecordingDuration: CMTime?
    
    /// Enable HDR for this camera
    public var isHDREnabled: Bool = false
    
    /// Enable low light boost for this camera
    public var isLowLightBoostEnabled: Bool = false
    
    // MARK: - Initialization
    
    public init(cameraPosition: NextLevelDevicePosition,
                lensType: NextLevelLensType,
                captureMode: NextLevelCaptureMode) {
        self.cameraPosition = cameraPosition
        self.lensType = lensType
        self.captureMode = captureMode
    }
    
    // MARK: - Validation
    
    /// Validates the configuration
    /// - Returns: Tuple with validation result and error messages
    public func validate() -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        // Validate capture mode requirements
        switch captureMode {
        case .video, .multiCameraWithoutAudio:
            if videoConfiguration == nil {
                errors.append("Video configuration is required for video capture mode")
            }
            
            // Validate frame rate
            if preferredFrameRate < 15 || preferredFrameRate > 240 {
                errors.append("Frame rate must be between 15 and 240 fps")
            }
            
        case .photo:
            if photoConfiguration == nil {
                errors.append("Photo configuration is required for photo capture mode")
            }
            
        case .multiCamera:
            errors.append("Use video or photo mode for individual cameras in multi-camera session")
            
        default:
            errors.append("Unsupported capture mode for individual camera configuration")
        }
        
        // Validate zoom factor
        if zoomFactor < 0.5 || zoomFactor > 100.0 {
            errors.append("Zoom factor must be between 0.5 and 100.0")
        }
        
        // Exposure and focus modes are validated by AVFoundation
        // No additional validation needed here
        
        return (errors.isEmpty, errors)
    }
    
    /// Creates a copy with video configuration
    public func withVideoConfiguration(_ config: NextLevelVideoConfiguration) -> NextLevelCameraConfiguration {
        var copy = self
        copy.videoConfiguration = config
        return copy
    }
    
    /// Creates a copy with photo configuration
    public func withPhotoConfiguration(_ config: NextLevelPhotoConfiguration) -> NextLevelCameraConfiguration {
        var copy = self
        copy.photoConfiguration = config
        return copy
    }
    
    /// Creates a copy with exposure mode
    public func withExposureMode(_ mode: AVCaptureDevice.ExposureMode) -> NextLevelCameraConfiguration {
        var copy = self
        copy.exposureMode = mode
        return copy
    }
    
    /// Creates a copy with focus mode
    public func withFocusMode(_ mode: AVCaptureDevice.FocusMode) -> NextLevelCameraConfiguration {
        var copy = self
        copy.focusMode = mode
        return copy
    }
}

// MARK: - Equatable

extension NextLevelCameraConfiguration: Equatable {
    public static func == (lhs: NextLevelCameraConfiguration, rhs: NextLevelCameraConfiguration) -> Bool {
        return lhs.cameraPosition == rhs.cameraPosition &&
               lhs.lensType == rhs.lensType &&
               lhs.captureMode == rhs.captureMode &&
               lhs.zoomFactor == rhs.zoomFactor &&
               lhs.preferredFrameRate == rhs.preferredFrameRate &&
               lhs.videoStabilizationMode == rhs.videoStabilizationMode &&
               lhs.isHDREnabled == rhs.isHDREnabled &&
               lhs.isLowLightBoostEnabled == rhs.isLowLightBoostEnabled
    }
}

// MARK: - Helper Extensions

extension NextLevelCameraConfiguration {
    
    /// Checks if this configuration is compatible with a device
    public func isCompatibleWith(device: AVCaptureDevice) -> Bool {
        // Check if device supports the requested capture mode
        switch captureMode {
        case .video, .multiCameraWithoutAudio:
            guard device.hasMediaType(.video) else { return false }
            
            // Check frame rate support
            let format = device.activeFormat
            if true {
                let supportsFrameRate = format.videoSupportedFrameRateRanges.contains { range in
                    return Float(preferredFrameRate) >= Float(range.minFrameRate) &&
                           Float(preferredFrameRate) <= Float(range.maxFrameRate)
                }
                if !supportsFrameRate { return false }
            }
            
        case .photo:
            guard device.hasMediaType(.video) else { return false }
            
        default:
            return false
        }
        
        // Check zoom factor support
        if zoomFactor < Float(device.minAvailableVideoZoomFactor) ||
           zoomFactor > Float(device.maxAvailableVideoZoomFactor) {
            return false
        }
        
        // Check HDR support
        if isHDREnabled && !device.isVideoHDREnabled {
            return false
        }
        
        // Check low light boost support
        if isLowLightBoostEnabled && !device.isLowLightBoostSupported {
            return false
        }
        
        return true
    }
    
    /// Apply this configuration to a capture device
    public func applyTo(device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        
        // Apply zoom
        device.videoZoomFactor = CGFloat(zoomFactor)
        
        // Apply frame rate for video modes
        if captureMode == .video || captureMode == .multiCameraWithoutAudio {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(preferredFrameRate))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(preferredFrameRate))
        }
        
        // Apply HDR if supported
        if device.activeFormat.isVideoHDRSupported {
            device.automaticallyAdjustsVideoHDREnabled = false
            device.isVideoHDREnabled = isHDREnabled
        }
        
        // Apply low light boost if supported
        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = isLowLightBoostEnabled
        }
        
        // Apply exposure mode
        if device.isExposureModeSupported(exposureMode) {
            device.exposureMode = exposureMode
        }
        
        // Apply focus mode
        if device.isFocusModeSupported(focusMode) {
            device.focusMode = focusMode
        }
    }
}

// MARK: - Convenience Initializers

extension NextLevelCameraConfiguration {
    
    /// Creates a 4K video configuration
    public static func video4K(position: NextLevelDevicePosition,
                               lensType: NextLevelLensType) -> NextLevelCameraConfiguration {
        var config = NextLevelCameraConfiguration(cameraPosition: position,
                                                  lensType: lensType,
                                                  captureMode: .video)
        
        let videoConfig = NextLevelVideoConfiguration()
        videoConfig.preset = .hd4K3840x2160
        videoConfig.bitRate = 50_000_000 // 50 Mbps
        config.videoConfiguration = videoConfig
        config.preferredFrameRate = 30
        
        return config
    }
    
    /// Creates an HD photo configuration
    public static func photoHD(position: NextLevelDevicePosition,
                               lensType: NextLevelLensType) -> NextLevelCameraConfiguration {
        var config = NextLevelCameraConfiguration(cameraPosition: position,
                                                  lensType: lensType,
                                                  captureMode: .photo)
        
        let photoConfig = NextLevelPhotoConfiguration()
        photoConfig.preset = .photo
        photoConfig.codec = .jpeg
        config.photoConfiguration = photoConfig
        
        return config
    }
}