//
//  NextLevelMultiCameraConfiguration.swift
//  NextLevel (http://github.com/NextLevel/)
//
//  Copyright (c) 2016-present patrick piemonte (http://patrickpiemonte.com)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import UIKit
import Foundation
import AVFoundation

// MARK: - types

/// Output mode for multi-camera capture
public enum MultiCameraOutputMode: Int, CustomStringConvertible {
    case separate      // Separate outputs for each camera
    case combined      // Picture-in-picture or side-by-side
    case custom        // User-defined composition
    
    public var description: String {
        switch self {
        case .separate:
            return "Separate outputs"
        case .combined:
            return "Combined output"
        case .custom:
            return "Custom composition"
        }
    }
}

/// Preview layout options for multi-camera
public enum MultiCameraPreviewLayout {
    case pictureInPicture(primaryRect: CGRect, secondaryRect: CGRect)
    case sideBySide(splitRatio: CGFloat) // 0.0-1.0 split ratio
    case topBottom(splitRatio: CGFloat)   // 0.0-1.0 split ratio
    case custom(layoutProvider: (CGSize) -> [NextLevelDevicePosition: CGRect])
}

/// Recording mode for multi-camera capture
public enum MultiCameraRecordingMode {
    case separate           // Separate files for each camera
    case combined           // Single file with multiple tracks
    case composited        // Single file with composed video
}

// MARK: - NextLevelMultiCameraConfiguration

/// NextLevelMultiCameraConfiguration, multi-camera capture configuration object
public class NextLevelMultiCameraConfiguration: NextLevelConfiguration {
    
    // MARK: - properties
    
    /// Primary camera position (default: back)
    public var primaryCameraPosition: NextLevelDevicePosition = .back {
        didSet {
            if primaryCameraPosition == secondaryCameraPosition {
                secondaryCameraPosition = primaryCameraPosition == .back ? .front : .back
            }
        }
    }
    
    /// Secondary camera position (default: front)
    public var secondaryCameraPosition: NextLevelDevicePosition = .front {
        didSet {
            if secondaryCameraPosition == primaryCameraPosition {
                primaryCameraPosition = secondaryCameraPosition == .back ? .front : .back
            }
        }
    }
    
    /// Set of enabled camera positions
    public var enabledCameras: Set<NextLevelDevicePosition> = [.back, .front]
    
    /// Output mode for multi-camera capture
    public var outputMode: MultiCameraOutputMode = .separate
    
    /// Preview layout for multi-camera
    public var previewLayout: MultiCameraPreviewLayout = .pictureInPicture(
        primaryRect: CGRect(x: 0, y: 0, width: 1, height: 1),
        secondaryRect: CGRect(x: 0.65, y: 0.02, width: 0.33, height: 0.25)
    )
    
    /// Recording mode for multi-camera
    public var recordingMode: MultiCameraRecordingMode = .separate
    
    /// Maximum number of simultaneous cameras (device dependent)
    public var maxSimultaneousCameras: Int = 2
    
    /// Enable hardware synchronization when available
    public var enableHardwareSynchronization: Bool = true
    
    /// Video stabilization mode for multi-camera
    public var videoStabilizationMode: NextLevelVideoStabilizationMode = .auto
    
    /// Frame rate for multi-camera capture (may be limited by device)
    public var preferredFrameRate: Int = 30
    
    /// Enable dynamic frame rate adjustment based on thermal state
    public var dynamicFrameRateAdjustment: Bool = true
    
    /// Audio source selection for multi-camera recording
    public var audioSource: NextLevelDevicePosition? = .back
    
    /// Enable audio recording from multiple sources
    public var enableMultiAudioSources: Bool = false
    
    // MARK: - object lifecycle
    
    override public init() {
        super.init()
    }
    
    // MARK: - validation
    
    /// Validates the current configuration
    public func validate() -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        // Check enabled cameras count
        if enabledCameras.isEmpty {
            errors.append("At least one camera must be enabled")
        }
        
        if enabledCameras.count > maxSimultaneousCameras {
            errors.append("Too many cameras enabled. Maximum is \(maxSimultaneousCameras)")
        }
        
        // Validate camera positions
        if primaryCameraPosition == secondaryCameraPosition && enabledCameras.count > 1 {
            errors.append("Primary and secondary cameras must have different positions")
        }
        
        // Validate frame rate
        if preferredFrameRate < 1 || preferredFrameRate > 240 {
            errors.append("Preferred frame rate must be between 1 and 240")
        }
        
        // Validate audio source
        if let audioSource = audioSource, !enabledCameras.contains(audioSource) {
            errors.append("Audio source must be from an enabled camera")
        }
        
        return (errors.isEmpty, errors)
    }
    
    /// Checks if configuration is compatible with device
    public func isCompatibleWithDevice() -> Bool {
        // This will be implemented when we add device capability detection
        return AVCaptureMultiCamSession.isMultiCamSupported
    }
    
    /// Returns optimal configuration for current device
    public func optimizeForDevice() {
        if !AVCaptureMultiCamSession.isMultiCamSupported {
            // Fallback to single camera
            enabledCameras = [primaryCameraPosition]
            maxSimultaneousCameras = 1
            return
        }
        
        // Adjust based on thermal state
        adjustForThermalState()
        
        // Optimize based on device model
        optimizeForDeviceModel()
    }
    
    /// Adjust configuration based on thermal state
    public func adjustForThermalState() {
        let thermalState = ProcessInfo.processInfo.thermalState
        
        switch thermalState {
        case .nominal:
            // No adjustments needed
            break
            
        case .fair:
            // Minor adjustments
            preferredFrameRate = min(preferredFrameRate, 30)
            
        case .serious:
            // Significant adjustments
            preferredFrameRate = min(preferredFrameRate, 24)
            if enabledCameras.count > 2 {
                enabledCameras = [primaryCameraPosition, secondaryCameraPosition]
            }
            
        case .critical:
            // Emergency adjustments
            preferredFrameRate = min(preferredFrameRate, 15)
            enabledCameras = [primaryCameraPosition]
            
        @unknown default:
            break
        }
    }
    
    /// Optimize for specific device models
    private func optimizeForDeviceModel() {
        _ = UIDevice.current
        
        // Get device model identifier
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                ptr in String.init(validatingUTF8: ptr)
            }
        }
        
        // Adjust based on device capabilities
        // iPhone 11 and newer have better multi-camera support
        if let model = modelCode {
            if model.contains("iPhone12") || model.contains("iPhone13") || 
               model.contains("iPhone14") || model.contains("iPhone15") {
                // Newer devices can handle higher quality
                maxSimultaneousCameras = 2
            } else if model.contains("iPhone11") {
                // iPhone 11 series
                maxSimultaneousCameras = 2
                preferredFrameRate = min(preferredFrameRate, 30)
            } else {
                // Older devices or unknown
                maxSimultaneousCameras = 1
            }
        }
    }
    
    // MARK: - helpers
    
    /// Returns preview rect for given camera position based on current layout
    public func previewRect(for position: NextLevelDevicePosition, in bounds: CGSize) -> CGRect {
        switch previewLayout {
        case .pictureInPicture(let primaryRect, let secondaryRect):
            if position == primaryCameraPosition {
                return CGRect(
                    x: primaryRect.origin.x * bounds.width,
                    y: primaryRect.origin.y * bounds.height,
                    width: primaryRect.width * bounds.width,
                    height: primaryRect.height * bounds.height
                )
            } else {
                return CGRect(
                    x: secondaryRect.origin.x * bounds.width,
                    y: secondaryRect.origin.y * bounds.height,
                    width: secondaryRect.width * bounds.width,
                    height: secondaryRect.height * bounds.height
                )
            }
            
        case .sideBySide(let splitRatio):
            let primaryWidth = bounds.width * splitRatio
            if position == primaryCameraPosition {
                return CGRect(x: 0, y: 0, width: primaryWidth, height: bounds.height)
            } else {
                return CGRect(x: primaryWidth, y: 0, width: bounds.width - primaryWidth, height: bounds.height)
            }
            
        case .topBottom(let splitRatio):
            let primaryHeight = bounds.height * splitRatio
            if position == primaryCameraPosition {
                return CGRect(x: 0, y: 0, width: bounds.width, height: primaryHeight)
            } else {
                return CGRect(x: 0, y: primaryHeight, width: bounds.width, height: bounds.height - primaryHeight)
            }
            
        case .custom(let layoutProvider):
            let rects = layoutProvider(bounds)
            return rects[position] ?? CGRect.zero
        }
    }
}