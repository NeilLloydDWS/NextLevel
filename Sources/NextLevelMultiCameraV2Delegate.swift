//
//  NextLevelMultiCameraV2Delegate.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import AVFoundation
import CoreMedia

/// Delegate protocol for multi-camera v2 with per-camera callbacks
public protocol NextLevelMultiCameraV2Delegate: AnyObject {
    
    // MARK: - Configuration Updates
    
    /// Called when a camera configuration is updated
    func nextLevel(_ nextLevel: NextLevel,
                   didUpdateConfiguration configuration: NextLevelCameraConfiguration,
                   forCamera position: NextLevelDevicePosition)
    
    /// Called when a camera is added to the session
    func nextLevel(_ nextLevel: NextLevel,
                   didAddCamera position: NextLevelDevicePosition,
                   with configuration: NextLevelCameraConfiguration)
    
    /// Called when a camera is removed from the session
    func nextLevel(_ nextLevel: NextLevel,
                   didRemoveCamera position: NextLevelDevicePosition)
    
    // MARK: - Video Capture
    
    /// Called when video recording starts for a specific camera
    func nextLevel(_ nextLevel: NextLevel,
                   didStartVideoRecording atPosition: NextLevelDevicePosition)
    
    /// Called when video recording pauses for a specific camera
    func nextLevel(_ nextLevel: NextLevel,
                   didPauseVideoRecording atPosition: NextLevelDevicePosition)
    
    /// Called when video recording resumes for a specific camera
    func nextLevel(_ nextLevel: NextLevel,
                   didResumeVideoRecording atPosition: NextLevelDevicePosition)
    
    /// Called when video recording completes for a specific camera
    func nextLevel(_ nextLevel: NextLevel,
                   didCompleteVideoRecording atPosition: NextLevelDevicePosition,
                   url: URL?)
    
    /// Called when video frame is processed for a specific camera
    func nextLevel(_ nextLevel: NextLevel,
                   didProcessVideoFrame sampleBuffer: CMSampleBuffer,
                   fromCamera position: NextLevelDevicePosition,
                   timestamp: TimeInterval)
    
    /// Called when video recording progress updates for a specific camera
    func nextLevel(_ nextLevel: NextLevel,
                   didUpdateVideoRecordingProgress progress: Float,
                   duration: CMTime,
                   forCamera position: NextLevelDevicePosition)
    
    // MARK: - Photo Capture
    
    /// Called when photo capture begins for a specific camera
    func nextLevel(_ nextLevel: NextLevel,
                   willCapturePhoto atPosition: NextLevelDevicePosition)
    
    /// Called when photo is captured for a specific camera
    func nextLevel(_ nextLevel: NextLevel,
                   didCapturePhoto photo: AVCapturePhoto,
                   fromCamera position: NextLevelDevicePosition)
    
    /// Called when photo processing completes for a specific camera
    func nextLevel(_ nextLevel: NextLevel,
                   didProcessPhoto photoData: Data?,
                   fromCamera position: NextLevelDevicePosition,
                   metadata: [String: Any]?)
    
    // MARK: - Camera State
    
    /// Called when camera zoom changes
    func nextLevel(_ nextLevel: NextLevel,
                   didUpdateZoom zoomFactor: Float,
                   forCamera position: NextLevelDevicePosition)
    
    /// Called when camera exposure changes
    func nextLevel(_ nextLevel: NextLevel,
                   didUpdateExposure mode: NextLevelExposureMode,
                   customExposure: (iso: Float, duration: CMTime)?,
                   forCamera position: NextLevelDevicePosition)
    
    /// Called when camera focus changes
    func nextLevel(_ nextLevel: NextLevel,
                   didUpdateFocus mode: NextLevelFocusMode,
                   focusPoint: CGPoint?,
                   forCamera position: NextLevelDevicePosition)
    
    /// Called when camera becomes available/unavailable
    func nextLevel(_ nextLevel: NextLevel,
                   camera position: NextLevelDevicePosition,
                   didChangeAvailability isAvailable: Bool)
    
    // MARK: - Performance & Resources
    
    /// Called when thermal state affects camera configuration
    func nextLevel(_ nextLevel: NextLevel,
                   didAdjustForThermalState state: ProcessInfo.ThermalState,
                   affectedCameras: [NextLevelDevicePosition])
    
    /// Called when resource constraints change camera configuration
    func nextLevel(_ nextLevel: NextLevel,
                   didAdjustForResourceConstraints constraints: [String],
                   affectedCameras: [NextLevelDevicePosition])
    
    /// Called when frame is dropped for a specific camera
    func nextLevel(_ nextLevel: NextLevel,
                   didDropFrame forCamera: NextLevelDevicePosition,
                   reason: String)
    
    // MARK: - Errors
    
    /// Called when an error occurs for a specific camera
    func nextLevel(_ nextLevel: NextLevel,
                   camera position: NextLevelDevicePosition,
                   didEncounterError error: Error)
    
    /// Called when capture session runtime error occurs
    func nextLevel(_ nextLevel: NextLevel,
                   didEncounterRuntimeError error: Error,
                   forCamera position: NextLevelDevicePosition?)
}

// MARK: - Default Implementations

public extension NextLevelMultiCameraV2Delegate {
    
    // Configuration
    func nextLevel(_ nextLevel: NextLevel,
                   didUpdateConfiguration configuration: NextLevelCameraConfiguration,
                   forCamera position: NextLevelDevicePosition) {}
    
    func nextLevel(_ nextLevel: NextLevel,
                   didAddCamera position: NextLevelDevicePosition,
                   with configuration: NextLevelCameraConfiguration) {}
    
    func nextLevel(_ nextLevel: NextLevel,
                   didRemoveCamera position: NextLevelDevicePosition) {}
    
    // Video
    func nextLevel(_ nextLevel: NextLevel,
                   didStartVideoRecording atPosition: NextLevelDevicePosition) {}
    
    func nextLevel(_ nextLevel: NextLevel,
                   didPauseVideoRecording atPosition: NextLevelDevicePosition) {}
    
    func nextLevel(_ nextLevel: NextLevel,
                   didResumeVideoRecording atPosition: NextLevelDevicePosition) {}
    
    func nextLevel(_ nextLevel: NextLevel,
                   didCompleteVideoRecording atPosition: NextLevelDevicePosition,
                   url: URL?) {}
    
    func nextLevel(_ nextLevel: NextLevel,
                   didProcessVideoFrame sampleBuffer: CMSampleBuffer,
                   fromCamera position: NextLevelDevicePosition,
                   timestamp: TimeInterval) {}
    
    func nextLevel(_ nextLevel: NextLevel,
                   didUpdateVideoRecordingProgress progress: Float,
                   duration: CMTime,
                   forCamera position: NextLevelDevicePosition) {}
    
    // Photo
    func nextLevel(_ nextLevel: NextLevel,
                   willCapturePhoto atPosition: NextLevelDevicePosition) {}
    
    func nextLevel(_ nextLevel: NextLevel,
                   didCapturePhoto photo: AVCapturePhoto,
                   fromCamera position: NextLevelDevicePosition) {}
    
    func nextLevel(_ nextLevel: NextLevel,
                   didProcessPhoto photoData: Data?,
                   fromCamera position: NextLevelDevicePosition,
                   metadata: [String: Any]?) {}
    
    // Camera State
    func nextLevel(_ nextLevel: NextLevel,
                   didUpdateZoom zoomFactor: Float,
                   forCamera position: NextLevelDevicePosition) {}
    
    func nextLevel(_ nextLevel: NextLevel,
                   didUpdateExposure mode: NextLevelExposureMode,
                   customExposure: (iso: Float, duration: CMTime)?,
                   forCamera position: NextLevelDevicePosition) {}
    
    func nextLevel(_ nextLevel: NextLevel,
                   didUpdateFocus mode: NextLevelFocusMode,
                   focusPoint: CGPoint?,
                   forCamera position: NextLevelDevicePosition) {}
    
    func nextLevel(_ nextLevel: NextLevel,
                   camera position: NextLevelDevicePosition,
                   didChangeAvailability isAvailable: Bool) {}
    
    // Performance
    func nextLevel(_ nextLevel: NextLevel,
                   didAdjustForThermalState state: ProcessInfo.ThermalState,
                   affectedCameras: [NextLevelDevicePosition]) {}
    
    func nextLevel(_ nextLevel: NextLevel,
                   didAdjustForResourceConstraints constraints: [String],
                   affectedCameras: [NextLevelDevicePosition]) {}
    
    func nextLevel(_ nextLevel: NextLevel,
                   didDropFrame forCamera: NextLevelDevicePosition,
                   reason: String) {}
    
    // Errors
    func nextLevel(_ nextLevel: NextLevel,
                   camera position: NextLevelDevicePosition,
                   didEncounterError error: Error) {}
    
    func nextLevel(_ nextLevel: NextLevel,
                   didEncounterRuntimeError error: Error,
                   forCamera position: NextLevelDevicePosition?) {}
}

// MARK: - Camera Status

/// Status information for an individual camera
public struct NextLevelCameraStatus {
    public let position: NextLevelDevicePosition
    public let lensType: NextLevelLensType
    public let isAvailable: Bool
    public let isRecording: Bool
    public let captureMode: NextLevelCaptureMode
    public let currentZoom: Float
    public let thermalState: ProcessInfo.ThermalState
    public let frameRate: Int
    public let droppedFrames: Int
    public let recordingDuration: CMTime?
    
    public init(position: NextLevelDevicePosition,
                lensType: NextLevelLensType,
                isAvailable: Bool,
                isRecording: Bool,
                captureMode: NextLevelCaptureMode,
                currentZoom: Float,
                thermalState: ProcessInfo.ThermalState,
                frameRate: Int,
                droppedFrames: Int,
                recordingDuration: CMTime?) {
        self.position = position
        self.lensType = lensType
        self.isAvailable = isAvailable
        self.isRecording = isRecording
        self.captureMode = captureMode
        self.currentZoom = currentZoom
        self.thermalState = thermalState
        self.frameRate = frameRate
        self.droppedFrames = droppedFrames
        self.recordingDuration = recordingDuration
    }
}

// MARK: - Configuration Options

/// Available configuration options for a camera
public struct NextLevelCameraConfigurationOption {
    public let position: NextLevelDevicePosition
    public let lensType: NextLevelLensType
    public let supportedCaptureModes: [NextLevelCaptureMode]
    public let supportedResolutions: [String]
    public let supportedFrameRates: [Int]
    public let minZoom: Float
    public let maxZoom: Float
    public let supportsHDR: Bool
    public let supportsLowLightBoost: Bool
    public let supportsStabilization: Bool
    
    public init(position: NextLevelDevicePosition,
                lensType: NextLevelLensType,
                supportedCaptureModes: [NextLevelCaptureMode],
                supportedResolutions: [String],
                supportedFrameRates: [Int],
                minZoom: Float,
                maxZoom: Float,
                supportsHDR: Bool,
                supportsLowLightBoost: Bool,
                supportsStabilization: Bool) {
        self.position = position
        self.lensType = lensType
        self.supportedCaptureModes = supportedCaptureModes
        self.supportedResolutions = supportedResolutions
        self.supportedFrameRates = supportedFrameRates
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.supportsHDR = supportsHDR
        self.supportsLowLightBoost = supportsLowLightBoost
        self.supportsStabilization = supportsStabilization
    }
}

// MARK: - Helper Types

/// Configuration adjustment for thermal/resource management
public struct NextLevelConfigurationAdjustment {
    public let position: NextLevelDevicePosition
    public let adjustmentType: AdjustmentType
    public let oldValue: Any
    public let newValue: Any
    public let reason: String
    
    public enum AdjustmentType {
        case frameRate
        case resolution
        case disabled
        case quality
        case stabilization
    }
}