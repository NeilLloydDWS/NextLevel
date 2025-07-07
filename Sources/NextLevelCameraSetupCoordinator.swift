//
//  NextLevelCameraSetupCoordinator.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import AVFoundation

/// Coordinates the setup of independent cameras with their specific configurations
public class NextLevelCameraSetupCoordinator {
    
    // MARK: - Properties
    
    private let session: AVCaptureMultiCamSession
    private let sessionQueue: DispatchQueue
    
    // MARK: - Initialization
    
    public init(session: AVCaptureMultiCamSession, sessionQueue: DispatchQueue) {
        self.session = session
        self.sessionQueue = sessionQueue
    }
    
    // MARK: - Camera Setup
    
    /// Setup independent cameras based on configuration
    public func setupIndependentCameras(configuration: NextLevelMultiCameraConfigurationV2) throws -> CameraSetupResult {
        var result = CameraSetupResult()
        
        // Begin session configuration
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        // Clear existing configuration
        clearSession()
        
        // Setup each camera independently
        for (position, cameraConfig) in configuration.cameraConfigurations {
            do {
                let setupInfo = try setupCamera(
                    position: position,
                    configuration: cameraConfig,
                    priority: configuration.cameraPriorities[position] ?? .medium
                )
                result.successfulCameras.append(setupInfo)
            } catch {
                result.failedCameras.append(
                    FailedCameraSetup(position: position, error: error)
                )
            }
        }
        
        // Setup audio if configured
        if let audioConfig = configuration.audioConfiguration,
           let audioSource = configuration.audioSource {
            do {
                try setupAudio(config: audioConfig, source: audioSource)
                result.audioSetup = true
            } catch {
                result.audioError = error
            }
        }
        
        return result
    }
    
    /// Setup a single camera with its configuration
    private func setupCamera(position: NextLevelDevicePosition,
                           configuration: NextLevelCameraConfiguration,
                           priority: CameraPriority) throws -> CameraSetupInfo {
        
        // Find the appropriate device
        guard let device = findDevice(for: configuration) else {
            throw NextLevelError.deviceNotAvailable
        }
        
        // Lock device for configuration
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        
        // Create input
        let input = try AVCaptureDeviceInput(device: device)
        
        guard session.canAddInput(input) else {
            throw NextLevelError.unableToAddInput
        }
        
        session.addInput(input)
        
        // Configure device settings
        try configureDevice(device, with: configuration)
        
        // Add appropriate outputs
        let outputs = try addOutputs(for: configuration, device: device)
        
        // Configure connections
        configureConnections(for: outputs, configuration: configuration)
        
        return CameraSetupInfo(
            position: position,
            device: device,
            input: input,
            outputs: outputs,
            configuration: configuration,
            priority: priority
        )
    }
    
    /// Find device matching configuration requirements
    private func findDevice(for configuration: NextLevelCameraConfiguration) -> AVCaptureDevice? {
        // Create discovery session for the specific lens type
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [configuration.lensType.avDeviceType],
            mediaType: .video,
            position: configuration.cameraPosition
        )
        
        let devices = discoverySession.devices
        
        // For now, just return the first matching device
        // Extended position handling would go here if implemented
        if false {
            // Handle extended positions (back2, back3, etc.)
            // Extended position handling would go here
            return nil
        }
        
        return devices.first
    }
    
    /// Select device for extended position
    private func selectDeviceForExtendedPosition(devices: [AVCaptureDevice],
                                               extendedPosition: NextLevelDevicePositionExtended,
                                               lensType: NextLevelLensType) -> AVCaptureDevice? {
        switch extendedPosition {
        case .back2:
            // For back2, prefer ultra-wide if available
            if lensType == .ultraWideAngleCamera {
                return devices.first
            }
            return devices.count > 1 ? devices[1] : nil
            
        case .back3:
            // For back3, prefer telephoto if available
            if lensType == .telephotoCamera {
                return devices.first
            }
            return devices.count > 2 ? devices[2] : nil
            
        case .front2:
            return devices.count > 1 ? devices[1] : nil
            
        default:
            return devices.first
        }
    }
    
    /// Configure device with camera-specific settings
    private func configureDevice(_ device: AVCaptureDevice, with configuration: NextLevelCameraConfiguration) throws {
        // Apply format selection
        if let format = selectOptimalFormat(for: device, configuration: configuration) {
            device.activeFormat = format
        }
        
        // Apply frame rate
        if configuration.captureMode == .video || configuration.captureMode == .multiCameraWithoutAudio {
            let frameRate = configuration.preferredFrameRate
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
        }
        
        // Apply zoom
        let zoomFactor = CGFloat(configuration.zoomFactor)
        if zoomFactor >= device.minAvailableVideoZoomFactor &&
           zoomFactor <= device.maxAvailableVideoZoomFactor {
            device.videoZoomFactor = zoomFactor
        }
        
        // Apply HDR
        if configuration.isHDREnabled && device.activeFormat.isVideoHDRSupported {
            device.automaticallyAdjustsVideoHDREnabled = false
            device.isVideoHDREnabled = true
        }
        
        // Apply low light boost
        if configuration.isLowLightBoostEnabled && device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = true
        }
        
        // Apply exposure settings
        applyExposureMode(configuration.exposureMode, to: device)
        
        // Apply focus settings
        applyFocusMode(configuration.focusMode, to: device)
        
        // Apply stabilization mode
        // Note: Stabilization is applied at the connection level, not device level
    }
    
    /// Select optimal format for device and configuration
    private func selectOptimalFormat(for device: AVCaptureDevice, configuration: NextLevelCameraConfiguration) -> AVCaptureDevice.Format? {
        let formats = device.formats
        
        // Get target resolution
        var targetWidth = 1920
        var targetHeight = 1080
        
        if let videoConfig = configuration.videoConfiguration {
            switch videoConfig.preset {
            case .hd4K3840x2160:
                targetWidth = 3840
                targetHeight = 2160
            case .hd1920x1080:
                targetWidth = 1920
                targetHeight = 1080
            case .hd1280x720:
                targetWidth = 1280
                targetHeight = 720
            default:
                break
            }
        }
        
        // Find best matching format
        return formats.first { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            
            // Check resolution match
            if dimensions.width != targetWidth || dimensions.height != targetHeight {
                return false
            }
            
            // Check frame rate support
            let supportsFrameRate = format.videoSupportedFrameRateRanges.contains { range in
                let fps = Float(configuration.preferredFrameRate)
                return fps >= Float(range.minFrameRate) && fps <= Float(range.maxFrameRate)
            }
            
            if !supportsFrameRate {
                return false
            }
            
            // Check HDR support if needed
            if configuration.isHDREnabled && !format.isVideoHDRSupported {
                return false
            }
            
            return true
        }
    }
    
    /// Apply exposure mode to device
    private func applyExposureMode(_ mode: AVCaptureDevice.ExposureMode, to device: AVCaptureDevice) {
        guard device.isExposureModeSupported(mode) else { return }
        
        device.exposureMode = mode
    }
    
    /// Apply focus mode to device
    private func applyFocusMode(_ mode: AVCaptureDevice.FocusMode, to device: AVCaptureDevice) {
        guard device.isFocusModeSupported(mode) else { return }
        
        device.focusMode = mode
    }
    
    /// Add outputs based on capture mode
    private func addOutputs(for configuration: NextLevelCameraConfiguration, device: AVCaptureDevice) throws -> CameraOutputs {
        var outputs = CameraOutputs()
        
        switch configuration.captureMode {
        case .video, .multiCameraWithoutAudio:
            // Add video data output
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            
            // Configure video output settings
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            guard session.canAddOutput(videoOutput) else {
                throw NextLevelError.unableToAddOutput
            }
            
            session.addOutput(videoOutput)
            outputs.videoDataOutput = videoOutput
            
            // Add movie file output for recording
            let movieOutput = AVCaptureMovieFileOutput()
            
            if let maxDuration = configuration.maximumRecordingDuration {
                movieOutput.maxRecordedDuration = maxDuration
            }
            
            guard session.canAddOutput(movieOutput) else {
                throw NextLevelError.unableToAddOutput
            }
            
            session.addOutput(movieOutput)
            outputs.movieFileOutput = movieOutput
            
        case .photo:
            // Add photo output
            let photoOutput = AVCapturePhotoOutput()
            
            if let photoConfig = configuration.photoConfiguration {
                photoOutput.isHighResolutionCaptureEnabled = photoConfig.isHighResolutionEnabled
                
                if photoOutput.availablePhotoCodecTypes.contains(photoConfig.codec) {
                    photoOutput.maxPhotoQualityPrioritization = .quality
                }
            }
            
            guard session.canAddOutput(photoOutput) else {
                throw NextLevelError.unableToAddOutput
            }
            
            session.addOutput(photoOutput)
            outputs.photoOutput = photoOutput
            
        default:
            throw NextLevelError.unknown
        }
        
        return outputs
    }
    
    /// Configure connections for outputs
    private func configureConnections(for outputs: CameraOutputs, configuration: NextLevelCameraConfiguration) {
        // Configure video connection
        if let videoOutput = outputs.videoDataOutput,
           let connection = videoOutput.connection(with: .video) {
            
            // Apply stabilization
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = configuration.videoStabilizationMode
            }
            
            // Apply orientation
            connection.videoOrientation = configuration.orientation
            
            // Apply mirroring for front cameras
            if configuration.cameraPosition == .front {
                connection.isVideoMirrored = true
            }
        }
        
        // Configure movie connection
        if let movieOutput = outputs.movieFileOutput,
           let connection = movieOutput.connection(with: .video) {
            
            // Apply stabilization
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = configuration.videoStabilizationMode
            }
            
            // Apply orientation
            connection.videoOrientation = configuration.orientation
        }
        
        // Configure photo connection
        if let photoOutput = outputs.photoOutput,
           let connection = photoOutput.connection(with: .video) {
            
            // Apply orientation
            connection.videoOrientation = configuration.orientation
            
            // Apply mirroring for front cameras
            if configuration.cameraPosition == .front {
                connection.isVideoMirrored = true
            }
        }
    }
    
    /// Setup audio input
    private func setupAudio(config: NextLevelAudioConfiguration, source: NextLevelDevicePosition) throws {
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            throw NextLevelError.deviceNotAvailable
        }
        
        let audioInput = try AVCaptureDeviceInput(device: audioDevice)
        
        guard session.canAddInput(audioInput) else {
            throw NextLevelError.unableToAddInput
        }
        
        session.addInput(audioInput)
        
        // Add audio data output if needed
        let audioOutput = AVCaptureAudioDataOutput()
        
        guard session.canAddOutput(audioOutput) else {
            throw NextLevelError.unableToAddOutput
        }
        
        session.addOutput(audioOutput)
    }
    
    /// Clear all inputs and outputs from session
    private func clearSession() {
        // Remove all inputs
        for input in session.inputs {
            session.removeInput(input)
        }
        
        // Remove all outputs
        for output in session.outputs {
            session.removeOutput(output)
        }
    }
}

// MARK: - Supporting Types

/// Result of camera setup operation
public struct CameraSetupResult {
    var successfulCameras: [CameraSetupInfo] = []
    var failedCameras: [FailedCameraSetup] = []
    var audioSetup: Bool = false
    var audioError: Error?
    
    var allSuccessful: Bool {
        return failedCameras.isEmpty && audioError == nil
    }
}

/// Information about successfully setup camera
public struct CameraSetupInfo {
    let position: NextLevelDevicePosition
    let device: AVCaptureDevice
    let input: AVCaptureDeviceInput
    let outputs: CameraOutputs
    let configuration: NextLevelCameraConfiguration
    let priority: CameraPriority
}

/// Information about failed camera setup
public struct FailedCameraSetup {
    let position: NextLevelDevicePosition
    let error: Error
}

/// Container for camera outputs
public struct CameraOutputs {
    var videoDataOutput: AVCaptureVideoDataOutput?
    var photoOutput: AVCapturePhotoOutput?
    var movieFileOutput: AVCaptureMovieFileOutput?
    var audioDataOutput: AVCaptureAudioDataOutput?
}