//
//  NextLevelDevicePositionExtended.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import AVFoundation

/// Extended device position to support multiple cameras at the same physical position
public enum NextLevelDevicePositionExtended: Int, CaseIterable {
    case back = 1
    case front = 2
    case unspecified = 0
    
    // Extended positions for multiple cameras at same location
    case back2 = 3  // Secondary back camera (e.g., ultra-wide)
    case back3 = 4  // Tertiary back camera (e.g., telephoto)
    case front2 = 5 // Secondary front camera
    
    /// Convert to AVFoundation position
    public var avPosition: AVCaptureDevice.Position {
        switch self {
        case .back, .back2, .back3:
            return .back
        case .front, .front2:
            return .front
        case .unspecified:
            return .unspecified
        }
    }
    
    /// Convert from AVFoundation position (returns primary position)
    public init(avPosition: AVCaptureDevice.Position) {
        switch avPosition {
        case .back:
            self = .back
        case .front:
            self = .front
        case .unspecified:
            self = .unspecified
        @unknown default:
            self = .unspecified
        }
    }
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .back:
            return "Back Camera"
        case .front:
            return "Front Camera"
        case .unspecified:
            return "Unspecified"
        case .back2:
            return "Back Camera 2"
        case .back3:
            return "Back Camera 3"
        case .front2:
            return "Front Camera 2"
        }
    }
    
    /// Check if this is a primary camera position
    public var isPrimary: Bool {
        switch self {
        case .back, .front:
            return true
        default:
            return false
        }
    }
    
    /// Get the primary position for this extended position
    public var primaryPosition: NextLevelDevicePositionExtended {
        switch self {
        case .back, .back2, .back3:
            return .back
        case .front, .front2:
            return .front
        case .unspecified:
            return .unspecified
        }
    }
}

/// Lens type enumeration for camera selection
public enum NextLevelLensType: Int, CaseIterable {
    case wideAngleCamera = 0
    case ultraWideAngleCamera
    case telephotoCamera
    case dualCamera
    case dualWideCamera
    case tripleCamera
    #if USE_TRUE_DEPTH
    case trueDepthCamera
    #endif
    
    /// Convert to AVFoundation device type
    public var avDeviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .wideAngleCamera:
            return .builtInWideAngleCamera
        case .ultraWideAngleCamera:
            return .builtInUltraWideCamera
        case .telephotoCamera:
            return .builtInTelephotoCamera
        case .dualCamera:
            return .builtInDualCamera
        case .dualWideCamera:
            return .builtInDualWideCamera
        case .tripleCamera:
            return .builtInTripleCamera
        #if USE_TRUE_DEPTH
        case .trueDepthCamera:
            return .builtInTrueDepthCamera
        #endif
        }
    }
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .wideAngleCamera:
            return "Wide Angle"
        case .ultraWideAngleCamera:
            return "Ultra Wide Angle"
        case .telephotoCamera:
            return "Telephoto"
        case .dualCamera:
            return "Dual Camera"
        case .dualWideCamera:
            return "Dual Wide Camera"
        case .tripleCamera:
            return "Triple Camera"
        #if USE_TRUE_DEPTH
        case .trueDepthCamera:
            return "TrueDepth Camera"
        #endif
        }
    }
    
    /// Typical focal length equivalent (35mm)
    public var focalLengthEquivalent: Int? {
        switch self {
        case .ultraWideAngleCamera:
            return 13
        case .wideAngleCamera:
            return 26
        case .telephotoCamera:
            return 52
        default:
            return nil
        }
    }
}

/// Extension to support extended positions in existing code
extension AVCaptureDevice.Position {
    
    /// Initialize from extended position
    public init(extended: NextLevelDevicePositionExtended) {
        self = extended.avPosition
    }
}

/// Mapping helper for device discovery
public struct NextLevelDeviceMapping {
    
    /// Find a device matching the extended position and lens type
    public static func device(for position: NextLevelDevicePositionExtended,
                            lensType: NextLevelLensType) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [lensType.avDeviceType],
            mediaType: .video,
            position: position.avPosition
        )
        
        let devices = discoverySession.devices
        
        // For primary positions, return first matching device
        if position.isPrimary {
            return devices.first
        }
        
        // For extended positions, we need more complex logic
        switch position {
        case .back2:
            // Look for ultra-wide on back
            if lensType == .ultraWideAngleCamera {
                return devices.first
            }
            // Otherwise, return second device if available
            return devices.count > 1 ? devices[1] : nil
            
        case .back3:
            // Look for telephoto on back
            if lensType == .telephotoCamera {
                return devices.first
            }
            // Otherwise, return third device if available
            return devices.count > 2 ? devices[2] : nil
            
        case .front2:
            // Return second front device if available
            return devices.count > 1 ? devices[1] : nil
            
        default:
            return devices.first
        }
    }
    
    /// Get all available camera configurations for the device
    public static func availableCameraConfigurations() -> [(position: NextLevelDevicePositionExtended, 
                                                           lensType: NextLevelLensType,
                                                           device: AVCaptureDevice)] {
        var configurations: [(NextLevelDevicePositionExtended, NextLevelLensType, AVCaptureDevice)] = []
        
        // Check all lens types
        for lensType in NextLevelLensType.allCases {
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [lensType.avDeviceType],
                mediaType: .video,
                position: .unspecified
            )
            
            for device in discoverySession.devices {
                // Map to extended position based on device position and count
                let basePosition = NextLevelDevicePositionExtended(avPosition: device.position)
                
                // Check if this combination already exists
                let exists = configurations.contains { config in
                    config.1 == lensType && config.2.position == device.position
                }
                
                if !exists {
                    configurations.append((basePosition, lensType, device))
                } else {
                    // Add as extended position
                    switch basePosition {
                    case .back:
                        if !configurations.contains(where: { $0.0 == .back2 }) {
                            configurations.append((.back2, lensType, device))
                        } else if !configurations.contains(where: { $0.0 == .back3 }) {
                            configurations.append((.back3, lensType, device))
                        }
                    case .front:
                        if !configurations.contains(where: { $0.0 == .front2 }) {
                            configurations.append((.front2, lensType, device))
                        }
                    default:
                        break
                    }
                }
            }
        }
        
        return configurations
    }
}

/// Convenience extension for NextLevel
extension NextLevelDevicePosition {
    
    /// Convert standard position to extended position
    public var extended: NextLevelDevicePositionExtended {
        return NextLevelDevicePositionExtended(avPosition: self)
    }
}

/// Update configuration classes to use extended positions
extension NextLevelCameraConfiguration {
    
    /// Convenience initializer using extended position
    public init(extendedPosition: NextLevelDevicePositionExtended,
                lensType: NextLevelLensType,
                captureMode: NextLevelCaptureMode) {
        self.init(cameraPosition: extendedPosition.avPosition,
                  lensType: lensType,
                  captureMode: captureMode)
    }
}

/// Store extended position information
private var extendedPositionKey: UInt8 = 0

extension NextLevelCameraConfiguration {
    
    /// Extended position for this configuration
    public var extendedPosition: NextLevelDevicePositionExtended {
        get {
            if let stored = objc_getAssociatedObject(self, &extendedPositionKey) as? NextLevelDevicePositionExtended {
                return stored
            }
            return NextLevelDevicePositionExtended(avPosition: cameraPosition)
        }
        set {
            objc_setAssociatedObject(self, &extendedPositionKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}