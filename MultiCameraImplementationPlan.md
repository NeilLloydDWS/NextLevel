# NextLevel Multi-Camera Capture Implementation Plan

## Overview

This document outlines a comprehensive plan to add multi-camera capture functionality to the NextLevel media capture library. The implementation will leverage AVCaptureMultiCamSession, introduced in iOS 13, to enable simultaneous capture from multiple cameras.

## Current Architecture Analysis

### NextLevel Core Structure
- **Main Class**: `NextLevel` - Singleton pattern with AVFoundation abstraction
- **Session Management**: Currently uses single `AVCaptureSession`
- **Input/Output Management**: Single video/audio input and output configurations
- **Configuration**: Separate configuration objects for video, audio, and photo
- **Delegation Pattern**: Multiple protocol delegates for different aspects of capture

### Key Limitations to Address
1. Single `_captureSession` instance
2. Single `_videoInput` and `_audioInput` references
3. Single video/audio output configurations
4. Preview layer designed for single camera

## Implementation Phases

### Phase 1: Foundation and Configuration

#### 1.1 Create Multi-Camera Configuration
```swift
// NextLevelMultiCameraConfiguration.swift
public class NextLevelMultiCameraConfiguration: NextLevelConfiguration {
    public var primaryCameraPosition: NextLevelDevicePosition = .back
    public var secondaryCameraPosition: NextLevelDevicePosition = .front
    public var enabledCameras: Set<NextLevelDevicePosition> = [.back, .front]
    public var videoStabilizationMode: NextLevelVideoStabilizationMode = .auto
    public var outputMode: MultiCameraOutputMode = .separate
    
    public enum MultiCameraOutputMode {
        case separate      // Separate outputs for each camera
        case combined      // Picture-in-picture or side-by-side
        case custom        // User-defined composition
    }
}
```

#### 1.2 Add Multi-Camera Capture Mode
```swift
// In NextLevel.swift
public enum NextLevelCaptureMode: Int {
    // ... existing modes ...
    case multiCamera
    case multiCameraWithoutAudio
}
```

### Phase 2: Core Implementation

#### 2.1 Multi-Camera Session Management
```swift
// Extensions to NextLevel.swift

// Replace single session with session abstraction
internal var _captureSession: AVCaptureSession?
internal var _multiCamSession: AVCaptureMultiCamSession?

// Multiple input management
internal var _videoInputs: [NextLevelDevicePosition: AVCaptureDeviceInput] = [:]
internal var _videoOutputs: [NextLevelDevicePosition: AVCaptureVideoDataOutput] = [:]

// Multi-camera specific properties
public var multiCameraConfiguration: NextLevelMultiCameraConfiguration
public var isMultiCameraSupported: Bool {
    return AVCaptureMultiCamSession.isMultiCamSupported
}
```

#### 2.2 Session Configuration Methods
```swift
// New methods for multi-camera setup
internal func configureMultiCameraSession() {
    guard isMultiCameraSupported else {
        // Fallback to single camera mode
        return
    }
    
    self._multiCamSession = AVCaptureMultiCamSession()
    
    self.beginConfiguration()
    
    // Add multiple inputs
    for position in multiCameraConfiguration.enabledCameras {
        if let device = self.captureDevice(withPosition: position, forMultiCam: true) {
            self.addMultiCameraInput(device: device, position: position)
        }
    }
    
    // Add multiple outputs
    for position in multiCameraConfiguration.enabledCameras {
        self.addMultiCameraVideoOutput(position: position)
    }
    
    // Configure connections
    self.configureMultiCameraConnections()
    
    self.commitConfiguration()
}
```

### Phase 3: Preview Layer Architecture

#### 3.1 Multiple Preview Support
```swift
// NextLevelMultiCameraPreview.swift
public class NextLevelMultiCameraPreview {
    public var primaryPreviewLayer: AVCaptureVideoPreviewLayer
    public var secondaryPreviewLayer: AVCaptureVideoPreviewLayer?
    public var previewLayers: [NextLevelDevicePosition: AVCaptureVideoPreviewLayer] = [:]
    
    public enum PreviewLayout {
        case pictureInPicture(primary: CGRect, secondary: CGRect)
        case sideBySide(split: CGFloat) // 0.0-1.0 split ratio
        case custom(layoutProvider: (CGSize) -> [NextLevelDevicePosition: CGRect])
    }
    
    public var layout: PreviewLayout = .pictureInPicture(
        primary: CGRect(x: 0, y: 0, width: 1, height: 1),
        secondary: CGRect(x: 0.7, y: 0.7, width: 0.3, height: 0.3)
    )
}
```

### Phase 4: Output Processing

#### 4.1 Multi-Camera Data Handling
```swift
// Extension to handle multiple video outputs
extension NextLevel: AVCaptureVideoDataOutputSampleBufferDelegate {
    // Modified to handle multiple outputs
    public func captureOutput(_ output: AVCaptureOutput,
                            didOutput sampleBuffer: CMSampleBuffer,
                            from connection: AVCaptureConnection) {
        
        // Identify which camera this output is from
        if let position = self.cameraPosition(for: output) {
            // Route to appropriate delegate method
            self.processVideoSampleBuffer(sampleBuffer, from: position)
        }
    }
}
```

#### 4.2 New Delegate Methods
```swift
// NextLevelProtocols.swift additions
public protocol NextLevelMultiCameraDelegate: AnyObject {
    func nextLevel(_ nextLevel: NextLevel, 
                   didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                   from position: NextLevelDevicePosition)
    
    func nextLevel(_ nextLevel: NextLevel,
                   didOutputPixelBuffer pixelBuffer: CVPixelBuffer,
                   from position: NextLevelDevicePosition,
                   timestamp: TimeInterval)
    
    func nextLevel(_ nextLevel: NextLevel,
                   didStartMultiCameraSession positions: Set<NextLevelDevicePosition>)
    
    func nextLevel(_ nextLevel: NextLevel,
                   didStopMultiCameraSession positions: Set<NextLevelDevicePosition>)
}
```

### Phase 5: Recording Support

#### 5.1 Multi-Stream Recording
```swift
// NextLevelMultiCameraRecording.swift
public class NextLevelMultiCameraRecording {
    // Options for recording multiple streams
    public enum RecordingMode {
        case separate           // Separate files for each camera
        case combined           // Single file with multiple tracks
        case composited        // Single file with composed video
    }
    
    // Asset writers for each stream
    private var assetWriters: [NextLevelDevicePosition: AVAssetWriter] = [:]
    private var videoInputs: [NextLevelDevicePosition: AVAssetWriterInput] = [:]
    private var audioInputs: [NextLevelDevicePosition: AVAssetWriterInput] = [:]
}
```

### Phase 6: Advanced Features

#### 6.1 Synchronized Capture
```swift
// Ensure frame synchronization between cameras
public class NextLevelSynchronizedCapture {
    private var frameSync = CMClockGetHostTimeClock()
    private var masterClock: CMClock?
    
    public func synchronizeCapture(for session: AVCaptureMultiCamSession) {
        // Configure hardware synchronization if available
        if #available(iOS 13.0, *) {
            session.hardwareCost = 1.0 // Maximum quality
        }
    }
}
```

#### 6.2 Performance Optimization
```swift
// Performance management for multi-camera
public struct NextLevelMultiCameraPerformance {
    public var maxSimultaneousCameras: Int = 2
    public var preferredFrameRate: Int = 30
    public var dynamicFrameRateAdjustment: Bool = true
    
    public func optimalConfiguration(for devices: [AVCaptureDevice]) -> [String: Any] {
        // Return optimal settings based on device capabilities
    }
}
```

## Implementation Checklist

### Core Features
- [ ] AVCaptureMultiCamSession integration
- [ ] Multiple input device management
- [ ] Multiple output configuration
- [ ] Multi-camera preview support
- [ ] Frame synchronization
- [ ] Performance optimization

### Configuration
- [ ] NextLevelMultiCameraConfiguration class
- [ ] Device compatibility checking
- [ ] Format validation for multi-cam
- [ ] Dynamic configuration updates

### Delegate Support
- [ ] NextLevelMultiCameraDelegate protocol
- [ ] Modified existing delegates for multi-camera
- [ ] Per-camera callbacks
- [ ] Synchronized frame callbacks

### Recording Features
- [ ] Separate file recording
- [ ] Combined track recording
- [ ] Composed video recording
- [ ] Audio routing options

### UI/Preview
- [ ] Multiple preview layer management
- [ ] Layout options (PiP, side-by-side)
- [ ] Preview transitions
- [ ] Touch-to-focus per camera

### Error Handling
- [ ] Device availability checking
- [ ] Graceful fallback to single camera
- [ ] Resource limitation handling
- [ ] Thermal state monitoring

## Migration Strategy

### Backward Compatibility
1. Maintain existing API surface
2. Add multi-camera as new capture mode
3. Provide convenience methods for common scenarios
4. Default to single camera on unsupported devices

### Usage Example
```swift
// Simple multi-camera setup
let nextLevel = NextLevel.shared
nextLevel.captureMode = .multiCamera
nextLevel.multiCameraConfiguration.enabledCameras = [.back, .front]
nextLevel.multiCameraConfiguration.outputMode = .pictureInPicture

// Start capture
try nextLevel.start()

// Handle output
nextLevel.multiCameraDelegate = self

// Recording
nextLevel.record(mode: .combined) // Single file with both streams
```

## Technical Considerations

### Device Requirements
- iPhone XS/XR or later (A12 Bionic)
- iPad Pro (3rd generation) or later
- iOS 13.0+

### Performance Impact
- Increased thermal load
- Higher battery consumption
- Memory usage considerations
- Frame rate limitations

### Limitations
- Maximum 2 simultaneous cameras on most devices
- Format restrictions for multi-cam
- No multi-camera across multiple apps
- Single session limitation

## Testing Strategy

### Unit Tests
- Configuration validation
- Device compatibility checks
- Format support verification
- Delegate callback testing

### Integration Tests
- Multi-camera session lifecycle
- Recording functionality
- Preview synchronization
- Performance benchmarks

### Device Testing Matrix
- iPhone 11 Pro (Triple camera)
- iPhone 12/13/14/15 series
- iPad Pro with LiDAR
- Thermal testing scenarios

## Future Enhancements

### Phase 2 Features
- AR integration with multi-camera
- Depth data from multiple cameras
- Advanced composition effects
- Machine learning integration

### Potential APIs
- Real-time video effects
- Custom video compositor
- Advanced synchronization
- Multi-camera portrait mode

## Conclusion

This implementation plan provides a comprehensive approach to adding multi-camera capture support to NextLevel. The phased approach ensures backward compatibility while introducing powerful new capabilities for modern iOS devices. The architecture is designed to be extensible and maintainable, following the existing patterns in NextLevel while adding the complexity required for multi-camera scenarios.