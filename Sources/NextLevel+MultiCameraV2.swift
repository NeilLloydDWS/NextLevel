//
//  NextLevel+MultiCameraV2.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import AVFoundation
import CoreMedia

// MARK: - Multi-Camera V2 Extension

extension NextLevel {
    
    // MARK: - Properties
    
    // Properties are defined in NextLevel.swift
    
    // Delegate is defined in NextLevel.swift
    
    // Internal properties defined in NextLevel.swift
    
    // MARK: - Multi-Camera V2 Control
    
    /// Configure session for multi-camera V2 mode
    public func configureMultiCameraV2(completion: @escaping (Error?) -> Void) {
        guard let configuration = self.multiCameraConfigurationV2 else {
            completion(NextLevelError.multiCameraNotConfigured)
            return
        }
        
        self._sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Validate configuration
                let validation = configuration.validate()
                if !validation.isValid {
                    throw NextLevelError.invalidConfiguration(validation.errors.joined(separator: ", "))
                }
                
                // Stop current session if running
                if self._captureSession?.isRunning ?? false {
                    self._captureSession?.stopRunning()
                }
                
                // Switch to multi-camera session if needed
                if !self._isMultiCamSession {
                    try self.switchToMultiCameraSession()
                }
                
                // Configure session with V2 coordinator
                guard let multiCamSession = self._captureSession as? AVCaptureMultiCamSession else {
                    throw NextLevelError.unknown
                }
                
                let multiCameraSession = NextLevelMultiCameraSession()
                multiCameraSession.delegate = self.multiCameraV2Delegate
                
                multiCameraSession.configure(with: configuration) { error in
                    if let error = error {
                        DispatchQueue.main.async {
                            completion(error)
                        }
                    } else {
                        // Store session reference
                        self._multiCameraSessionV2 = multiCameraSession
                        
                        // Update capture mode
                        self.captureMode = .multiCamera
                        
                        // Store active configurations
                        self._activeCameraConfigurations = configuration.cameraConfigurations
                        
                        DispatchQueue.main.async {
                            completion(nil)
                        }
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }
    
    /// Configure individual camera in multi-camera V2 mode
    public func configureCamera(position: NextLevelDevicePosition,
                              lensType: NextLevelLensType,
                              captureMode: NextLevelCaptureMode,
                              videoSettings: NextLevelVideoConfiguration? = nil,
                              photoSettings: NextLevelPhotoConfiguration? = nil,
                              completion: @escaping (Error?) -> Void) {
        
        self._sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Create camera configuration
                var cameraConfig = NextLevelCameraConfiguration(
                    cameraPosition: position,
                    lensType: lensType,
                    captureMode: captureMode
                )
                
                // Apply settings
                cameraConfig.videoConfiguration = videoSettings
                cameraConfig.photoConfiguration = photoSettings
                
                // Validate configuration
                let validation = cameraConfig.validate()
                if !validation.isValid {
                    throw NextLevelError.invalidConfiguration(validation.errors.joined(separator: ", "))
                }
                
                // Add to multi-camera session
                guard let multiCameraSession = self._multiCameraSessionV2 else {
                    throw NextLevelError.unknown
                }
                
                try multiCameraSession.addCamera(at: position, with: cameraConfig)
                
                // Update active configurations
                self._activeCameraConfigurations[position] = cameraConfig
                
                DispatchQueue.main.async {
                    completion(nil)
                }
                
            } catch {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }
    
    /// Update camera configuration
    public func updateCameraConfiguration(at position: NextLevelDevicePosition,
                                        changes: @escaping (inout NextLevelCameraConfiguration) -> Void,
                                        completion: @escaping (Error?) -> Void) {
        
        self._sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                guard var config = self._activeCameraConfigurations[position] else {
                    throw NextLevelError.deviceNotAvailable
                }
                
                // Apply changes
                changes(&config)
                
                // Validate updated configuration
                let validation = config.validate()
                if !validation.isValid {
                    throw NextLevelError.invalidConfiguration(validation.errors.joined(separator: ", "))
                }
                
                // Update in session
                guard let multiCameraSession = self._multiCameraSessionV2 else {
                    throw NextLevelError.unknown
                }
                
                try multiCameraSession.updateCameraConfiguration(at: position, configuration: config)
                
                // Update stored configuration
                self._activeCameraConfigurations[position] = config
                
                DispatchQueue.main.async {
                    completion(nil)
                }
                
            } catch {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }
    
    // removeCamera is already defined in NextLevelMultiCameraAPI.swift
    
    // MARK: - Camera Control
    
    /// Start capture for specific camera
    public func startCapture(at position: NextLevelDevicePosition) throws {
        guard let config = self._activeCameraConfigurations[position] else {
            throw NextLevelError.deviceNotAvailable
        }
        
        switch config.captureMode {
        case .video, .multiCameraWithoutAudio:
            try self.startVideoRecording(at: position)
        case .photo:
            // Photo capture is triggered separately
            break
        default:
            throw NextLevelError.unknown
        }
    }
    
    /// Stop capture for specific camera
    public func stopCapture(at position: NextLevelDevicePosition) {
        guard let config = self._activeCameraConfigurations[position] else { return }
        
        switch config.captureMode {
        case .video, .multiCameraWithoutAudio:
            self.stopVideoRecording(at: position)
        case .photo:
            // Photo capture stops automatically
            break
        default:
            break
        }
    }
    
    /// Start video recording for specific camera
    private func startVideoRecording(at position: NextLevelDevicePosition) throws {
        // Implementation will be added in Sprint 3
    }
    
    /// Stop video recording for specific camera
    private func stopVideoRecording(at position: NextLevelDevicePosition) {
        // Implementation will be added in Sprint 3
    }
    
    /// Capture photo from specific camera
    public func capturePhoto(at position: NextLevelDevicePosition) {
        // Implementation will be added in Sprint 3
    }
    
    // MARK: - Camera Status
    
    /// Get status of specific camera
    public func cameraStatus(at position: NextLevelDevicePosition) -> NextLevelCameraStatus? {
        guard let config = self._activeCameraConfigurations[position] else {
            return nil
        }
        
        return NextLevelCameraStatus(
            position: position,
            lensType: config.lensType,
            isAvailable: true, // TODO: Check actual availability
            isRecording: false, // TODO: Check recording state
            captureMode: config.captureMode,
            currentZoom: config.zoomFactor,
            thermalState: ProcessInfo.processInfo.thermalState,
            frameRate: config.preferredFrameRate,
            droppedFrames: 0, // TODO: Track dropped frames
            recordingDuration: nil
        )
    }
    
    /// Get all available camera configurations
    public func availableConfigurations() -> [NextLevelCameraConfigurationOption] {
        let deviceMappings = NextLevelDeviceMapping.availableCameraConfigurations()
        
        return deviceMappings.map { mapping in
            let device = mapping.device
            
            // Get supported resolutions
            let resolutions = device.formats.compactMap { format -> String? in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return "\(dimensions.width)x\(dimensions.height)"
            }
            
            // Get supported frame rates
            let frameRates = Set(device.formats.flatMap { format in
                format.videoSupportedFrameRateRanges.flatMap { range in
                    [Int(range.minFrameRate), Int(range.maxFrameRate)]
                }
            }).sorted()
            
            return NextLevelCameraConfigurationOption(
                position: mapping.position.avPosition,
                lensType: mapping.lensType,
                supportedCaptureModes: [.video, .photo],
                supportedResolutions: Array(Set(resolutions)),
                supportedFrameRates: frameRates,
                minZoom: Float(device.minAvailableVideoZoomFactor),
                maxZoom: Float(device.maxAvailableVideoZoomFactor),
                supportsHDR: device.activeFormat.isVideoHDRSupported,
                supportsLowLightBoost: device.isLowLightBoostSupported,
                supportsStabilization: device.activeFormat.isVideoStabilizationModeSupported(.auto)
            )
        }
    }
    
    // MARK: - Private Methods
    
    /// Switch to multi-camera session
    private func switchToMultiCameraSession() throws {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            throw NextLevelError.multiCamNotSupported
        }
        
        // Remove all existing inputs and outputs
        if let session = self._captureSession {
            self.removeInputs(session: session)
            self.removeOutputs(session: session)
        }
        
        // Create new multi-camera session
        let multiCamSession = AVCaptureMultiCamSession()
        
        // Copy basic settings
        if let session = self._captureSession {
            multiCamSession.automaticallyConfiguresApplicationAudioSession = session.automaticallyConfiguresApplicationAudioSession
            multiCamSession.usesApplicationAudioSession = session.usesApplicationAudioSession
        }
        
        // Replace session
        self._captureSession = multiCamSession
        self._multiCamSession = multiCamSession
        
        // Update preview layer
        self.previewLayer.session = multiCamSession
    }
    
    /// Check if configuration should use multi-camera V2
    internal func shouldUseMultiCameraV2() -> Bool {
        return self.multiCameraConfigurationV2 != nil &&
               self.captureMode == .multiCamera &&
               self._multiCameraSessionV2 != nil
    }
}

// MARK: - Additional Internal Properties

extension NextLevel {
    
    /// Multi-camera V2 configuration storage
    internal var _multiCameraConfigurationV2: NextLevelMultiCameraConfigurationV2? {
        get {
            return objc_getAssociatedObject(self, &multiCameraConfigV2Key) as? NextLevelMultiCameraConfigurationV2
        }
        set {
            objc_setAssociatedObject(self, &multiCameraConfigV2Key, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    /// Multi-camera V2 delegate storage
    internal var _multiCameraV2Delegate: NextLevelMultiCameraV2Delegate? {
        get {
            return objc_getAssociatedObject(self, &multiCameraV2DelegateKey) as? NextLevelMultiCameraV2Delegate
        }
        set {
            objc_setAssociatedObject(self, &multiCameraV2DelegateKey, newValue, .OBJC_ASSOCIATION_ASSIGN)
        }
    }
    
    /// Multi-camera session V2 storage
    internal var _multiCameraSessionV2: NextLevelMultiCameraSession? {
        get {
            return objc_getAssociatedObject(self, &multiCameraSessionV2Key) as? NextLevelMultiCameraSession
        }
        set {
            objc_setAssociatedObject(self, &multiCameraSessionV2Key, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    /// Active camera configurations storage
    internal var _activeCameraConfigurations: [NextLevelDevicePosition: NextLevelCameraConfiguration] {
        get {
            return objc_getAssociatedObject(self, &activeCameraConfigsKey) as? [NextLevelDevicePosition: NextLevelCameraConfiguration] ?? [:]
        }
        set {
            objc_setAssociatedObject(self, &activeCameraConfigsKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    /// Check if using multi-camera session
    internal var _isMultiCamSession: Bool {
        get {
            return self._captureSession is AVCaptureMultiCamSession
        }
        set {
            // Handled by session replacement
        }
    }
}

// MARK: - Associated Object Keys

private var multiCameraConfigV2Key: UInt8 = 0
private var multiCameraV2DelegateKey: UInt8 = 0
private var multiCameraSessionV2Key: UInt8 = 0
private var activeCameraConfigsKey: UInt8 = 0

// MARK: - Errors

// Error cases are already defined in NextLevel.swift