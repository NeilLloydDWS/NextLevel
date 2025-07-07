# NextLevel Independent Camera Configuration Implementation Plan

## Overview
This plan details the implementation steps to enable independent configuration of multiple cameras in NextLevel, allowing scenarios like simultaneous 4K video recording on one camera and HD photo capture on another.

## Phase 1: Architecture Design

### 1.1 Create Per-Camera Configuration System

#### New Data Structures
```swift
// Individual camera configuration
public struct NextLevelCameraConfiguration {
    public let cameraPosition: NextLevelDevicePosition
    public let lensType: NextLevelLensType
    public let captureMode: NextLevelCaptureMode // video or photo
    
    // Video-specific settings (optional)
    public var videoConfiguration: NextLevelVideoConfiguration?
    
    // Photo-specific settings (optional)
    public var photoConfiguration: NextLevelPhotoConfiguration?
    
    // Camera-specific settings
    public var exposureConfiguration: NextLevelExposureConfiguration?
    public var focusConfiguration: NextLevelFocusConfiguration?
    public var zoomFactor: Float = 1.0
    public var orientation: NextLevelOrientation?
}

// Updated multi-camera configuration
public class NextLevelMultiCameraConfigurationV2 {
    // Replace single configuration with per-camera configs
    public var cameraConfigurations: [NextLevelDevicePosition: NextLevelCameraConfiguration] = [:]
    
    // Shared settings
    public var audioConfiguration: NextLevelAudioConfiguration?
    public var audioSource: NextLevelDevicePosition? = .back
    
    // Output settings
    public var outputMode: MultiCameraOutputMode = .separate
    public var recordingMode: MultiCameraRecordingMode = .separate
    
    // Validation and optimization
    public func validate() -> (isValid: Bool, errors: [String])
    public func optimizeForDevice() 
}
```

### 1.2 Session Management Updates

#### Enhanced Session Controller
```swift
public class NextLevelMultiCameraSession {
    // Separate inputs and outputs per camera
    private var cameraInputs: [NextLevelDevicePosition: AVCaptureDeviceInput] = [:]
    private var videoOutputs: [NextLevelDevicePosition: AVCaptureVideoDataOutput] = [:]
    private var photoOutputs: [NextLevelDevicePosition: AVCapturePhotoOutput] = [:]
    private var movieOutputs: [NextLevelDevicePosition: AVCaptureMovieFileOutput] = [:]
    
    // Track active capture modes per camera
    private var activeModes: [NextLevelDevicePosition: NextLevelCaptureMode] = [:]
    
    // Resource management
    private var resourceManager: CameraResourceManager
}
```

## Phase 2: Core Implementation

### 2.1 Modify NextLevel Main Class

#### Key Changes
1. **Replace single configuration properties**
   ```swift
   // OLD
   public var videoConfiguration: NextLevelVideoConfiguration
   public var photoConfiguration: NextLevelPhotoConfiguration
   
   // NEW
   public var multiCameraConfigurationV2: NextLevelMultiCameraConfigurationV2?
   private var activeCameraConfigurations: [NextLevelDevicePosition: NextLevelCameraConfiguration] = [:]
   ```

2. **Update configuration methods**
   ```swift
   public func configureCamera(
       at position: NextLevelDevicePosition,
       with configuration: NextLevelCameraConfiguration
   ) throws
   
   public func updateCameraConfiguration(
       at position: NextLevelDevicePosition,
       changes: (inout NextLevelCameraConfiguration) -> Void
   ) throws
   ```

### 2.2 Session Configuration Logic

#### Independent Setup Flow
```swift
private func setupIndependentCameras() throws {
    guard let multiConfig = multiCameraConfigurationV2 else { return }
    
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    
    // Remove existing inputs/outputs
    clearSession()
    
    // Add each camera with its specific configuration
    for (position, cameraConfig) in multiConfig.cameraConfigurations {
        try addCameraInput(position: position, config: cameraConfig)
        
        switch cameraConfig.captureMode {
        case .video:
            try addVideoOutputs(position: position, config: cameraConfig)
        case .photo:
            try addPhotoOutput(position: position, config: cameraConfig)
        default:
            throw NextLevelError.invalidConfiguration
        }
        
        // Apply camera-specific settings
        try configureCameraDevice(position: position, config: cameraConfig)
    }
    
    // Add audio if needed
    if let audioConfig = multiConfig.audioConfiguration {
        try addAudioInput(config: audioConfig)
    }
}
```

### 2.3 Output Management

#### Separate Output Handlers
```swift
// Video output handling
private func handleVideoOutput(
    position: NextLevelDevicePosition,
    sampleBuffer: CMSampleBuffer
) {
    // Process based on camera-specific configuration
    let config = activeCameraConfigurations[position]
    // Apply resolution, bitrate, etc.
}

// Photo output handling  
private func handlePhotoCapture(
    position: NextLevelDevicePosition,
    photo: AVCapturePhoto
) {
    // Process based on camera-specific configuration
    let config = activeCameraConfigurations[position]
    // Apply photo settings
}
```

## Phase 3: Resource Management

### 3.1 Camera Resource Manager

```swift
public class CameraResourceManager {
    // Track resource usage
    private var activeResources: Set<CameraResource>
    private var thermalState: ProcessInfo.ThermalState
    
    // Validation methods
    func canAddCamera(config: NextLevelCameraConfiguration) -> Bool
    func validateConfigurations(_ configs: [NextLevelCameraConfiguration]) -> [ValidationError]
    
    // Dynamic adjustment
    func optimizeForThermalState() -> [ConfigurationAdjustment]
    func prioritizeConfigurations(_ configs: [NextLevelCameraConfiguration]) -> [NextLevelCameraConfiguration]
}
```

### 3.2 Hardware Limitations Handling

```swift
struct HardwareLimitations {
    static func maximumSimultaneousVideoStreams(
        resolutions: [NextLevelResolution],
        frameRates: [Int]
    ) -> Int
    
    static func supportedCombinations(
        for device: AVCaptureDevice.DeviceType
    ) -> [CameraConfigurationCombination]
}
```

## Phase 4: API Updates

### 4.1 Public API Changes

```swift
extension NextLevel {
    // Configure individual camera
    public func configureCamera(
        position: NextLevelDevicePosition,
        lensType: NextLevelLensType,
        captureMode: NextLevelCaptureMode,
        videoSettings: NextLevelVideoConfiguration? = nil,
        photoSettings: NextLevelPhotoConfiguration? = nil
    ) throws
    
    // Start/stop individual camera capture
    public func startCapture(at position: NextLevelDevicePosition) throws
    public func stopCapture(at position: NextLevelDevicePosition)
    
    // Query camera status
    public func cameraStatus(at position: NextLevelDevicePosition) -> CameraStatus
    public func availableConfigurations() -> [CameraConfigurationOption]
}
```

### 4.2 Delegate Updates

```swift
public protocol NextLevelMultiCameraDelegate: AnyObject {
    // Per-camera callbacks
    func nextLevel(
        _ nextLevel: NextLevel,
        didUpdateVideoConfiguration config: NextLevelVideoConfiguration,
        forCamera position: NextLevelDevicePosition
    )
    
    func nextLevel(
        _ nextLevel: NextLevel,
        didCapturePhoto photo: AVCapturePhoto,
        fromCamera position: NextLevelDevicePosition
    )
    
    func nextLevel(
        _ nextLevel: NextLevel,
        didFinishRecordingVideo url: URL,
        fromCamera position: NextLevelDevicePosition
    )
}
```

## Phase 5: Implementation Steps

### Step 1: Foundation (Week 1)
1. Create new configuration structures
2. Design resource manager
3. Update protocol definitions
4. Create unit tests for configurations

### Step 2: Core Changes (Week 2-3)
1. Modify NextLevel session management
2. Implement independent camera setup
3. Update output handling
4. Add configuration validation

### Step 3: Resource Management (Week 4)
1. Implement CameraResourceManager
2. Add thermal throttling support
3. Handle hardware limitations
4. Test edge cases

### Step 4: API Integration (Week 5)
1. Update public APIs
2. Modify delegate callbacks
3. Ensure backward compatibility
4. Update documentation

### Step 5: Testing & Optimization (Week 6)
1. Comprehensive testing across devices
2. Performance profiling
3. Memory usage optimization
4. Bug fixes and refinements

## Phase 6: Usage Example

### Your Use Case Implementation
```swift
// Configure NextLevel for your requirements
let nextLevel = NextLevel.shared

// Configure 4K video on back wide camera
let videoConfig = NextLevelVideoConfiguration()
videoConfig.preset = .hd4K3840x2160
videoConfig.bitRate = 50_000_000 // 50 Mbps
videoConfig.frameRate = 30

let backVideoCamera = NextLevelCameraConfiguration(
    cameraPosition: .back,
    lensType: .wideAngleCamera,
    captureMode: .video,
    videoConfiguration: videoConfig
)

// Configure HD photo on back ultra-wide camera  
let photoConfig = NextLevelPhotoConfiguration()
photoConfig.preset = .photo
photoConfig.codec = .jpeg

let backPhotoCamera = NextLevelCameraConfiguration(
    cameraPosition: .back,
    lensType: .ultraWideAngleCamera,
    captureMode: .photo,
    photoConfiguration: photoConfig
)

// Setup multi-camera session
let multiConfig = NextLevelMultiCameraConfigurationV2()
multiConfig.cameraConfigurations[.back] = backVideoCamera
multiConfig.cameraConfigurations[.back2] = backPhotoCamera // New position enum

nextLevel.multiCameraConfigurationV2 = multiConfig

// Start session
try nextLevel.start()

// Start video recording on back camera
try nextLevel.startCapture(at: .back)

// Capture photo on ultra-wide while recording
nextLevel.capturePhoto(at: .back2)
```

## Technical Considerations

### 1. Memory Management
- Separate buffer pools per camera
- Optimize memory usage for 4K + HD simultaneous capture
- Implement buffer recycling

### 2. Performance
- GPU acceleration for video processing
- Efficient buffer handling
- Minimize CPU overhead

### 3. Compatibility
- Maintain backward compatibility
- Gradual migration path
- Feature detection for older devices

### 4. Error Handling
- Graceful degradation
- Clear error messages
- Recovery mechanisms

## Testing Strategy

### 1. Unit Tests
- Configuration validation
- Resource management logic
- API compatibility

### 2. Integration Tests
- Multi-camera scenarios
- Mixed capture modes
- Resource exhaustion

### 3. Device Testing
- Test on minimum supported devices
- Verify thermal behavior
- Performance benchmarks

## Migration Guide

### For Existing Users
1. Current single-camera code continues to work
2. Multi-camera v1 marked as deprecated
3. Clear upgrade path with examples
4. Migration tool/helper methods

## Risks and Mitigations

### 1. Hardware Limitations
**Risk**: Some devices may not support desired configurations
**Mitigation**: Clear capability detection and fallback options

### 2. Performance Impact
**Risk**: Increased CPU/GPU usage
**Mitigation**: Efficient resource management and optimization

### 3. API Complexity
**Risk**: More complex API surface
**Mitigation**: Helper methods and clear documentation

## Success Criteria

1. Support 4K video + HD photo simultaneously
2. Independent camera control
3. Maintain performance standards
4. Clear API and documentation
5. Backward compatibility
6. Comprehensive test coverage