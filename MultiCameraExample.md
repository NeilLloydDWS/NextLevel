# NextLevel Multi-Camera Usage Examples

## Basic Setup

```swift
import NextLevel
import AVFoundation

class MultiCameraViewController: UIViewController {
    
    private let nextLevel = NextLevel.shared
    private var multiCameraPreview: NextLevelMultiCameraPreview!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configure NextLevel for multi-camera
        setupMultiCamera()
        
        // Setup preview
        setupPreview()
    }
    
    private func setupMultiCamera() {
        // Check if multi-camera is supported
        guard nextLevel.isMultiCameraSupported else {
            print("Multi-camera not supported on this device")
            return
        }
        
        // Set capture mode
        nextLevel.captureMode = .multiCamera
        
        // Configure multi-camera settings
        let config = nextLevel.multiCameraConfiguration
        config.primaryCameraPosition = .back
        config.secondaryCameraPosition = .front
        config.enabledCameras = [.back, .front]
        config.outputMode = .separate
        config.recordingMode = .separate
        config.preferredFrameRate = 30
        
        // Optimize for device
        config.optimizeForDevice()
        
        // Set delegates
        nextLevel.delegate = self
        nextLevel.multiCameraDelegate = self
        nextLevel.videoDelegate = self
    }
    
    private func setupPreview() {
        // Create multi-camera preview
        multiCameraPreview = NextLevelMultiCameraPreview(frame: view.bounds)
        multiCameraPreview.configuration = nextLevel.multiCameraConfiguration
        multiCameraPreview.session = nextLevel.session
        
        // Configure preview layout
        multiCameraPreview.layout = .pictureInPicture(
            primaryRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            secondaryRect: CGRect(x: 0.65, y: 0.05, width: 0.3, height: 0.2)
        )
        
        // Add to view
        view.addSubview(multiCameraPreview)
        multiCameraPreview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        do {
            try nextLevel.start()
        } catch {
            print("Failed to start multi-camera: \(error)")
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        nextLevel.stop()
    }
}
```

## Multi-Camera Recording

### Separate Files Recording

```swift
extension MultiCameraViewController {
    
    @IBAction func recordButtonTapped() {
        if nextLevel.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        // Configure for separate file recording
        nextLevel.multiCameraConfiguration.recordingMode = .separate
        
        do {
            try nextLevel.startMultiCameraRecording()
            updateUI(recording: true)
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    private func stopRecording() {
        nextLevel.stopMultiCameraRecording { [weak self] urls, error in
            if let urls = urls {
                print("Recording saved to:")
                for url in urls {
                    print("- \(url.lastPathComponent)")
                }
                self?.processRecordedVideos(urls)
            } else if let error = error {
                print("Recording failed: \(error)")
            }
            
            self?.updateUI(recording: false)
        }
    }
}
```

### Combined Multi-Track Recording

```swift
private func startCombinedRecording() {
    // Configure for combined file with multiple tracks
    nextLevel.multiCameraConfiguration.recordingMode = .combined
    
    do {
        try nextLevel.startMultiCameraRecording()
    } catch {
        print("Failed to start combined recording: \(error)")
    }
}
```

### Composed Video Recording (Picture-in-Picture)

```swift
private func startComposedRecording() {
    // Configure for composed video output
    nextLevel.multiCameraConfiguration.recordingMode = .composited
    
    do {
        try nextLevel.startMultiCameraRecording()
    } catch {
        print("Failed to start composed recording: \(error)")
    }
}
```

## Multi-Camera Delegate Implementation

```swift
extension MultiCameraViewController: NextLevelMultiCameraDelegate {
    
    func nextLevel(_ nextLevel: NextLevel, 
                   didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                   from position: NextLevelDevicePosition) {
        // Handle raw sample buffers from each camera
        // This is called on a background queue
        
        // Example: Apply different processing to each camera
        switch position {
        case .front:
            // Process front camera frames (e.g., face detection)
            processFrontCameraFrame(sampleBuffer)
        case .back:
            // Process back camera frames (e.g., object detection)
            processBackCameraFrame(sampleBuffer)
        default:
            break
        }
    }
    
    func nextLevel(_ nextLevel: NextLevel,
                   didOutputPixelBuffer pixelBuffer: CVPixelBuffer,
                   from position: NextLevelDevicePosition,
                   timestamp: TimeInterval) {
        // Handle pixel buffers for easier image processing
        
        // Example: Apply Core Image filters
        if position == .front {
            let filtered = applyBeautyFilter(to: pixelBuffer)
            // Use filtered buffer...
        }
    }
    
    func nextLevel(_ nextLevel: NextLevel,
                   didStartMultiCameraSession positions: Set<NextLevelDevicePosition>) {
        print("Multi-camera session started with cameras: \(positions)")
    }
    
    func nextLevel(_ nextLevel: NextLevel,
                   didStopMultiCameraSession positions: Set<NextLevelDevicePosition>) {
        print("Multi-camera session stopped")
    }
}
```

## Preview Layout Options

### Picture-in-Picture

```swift
multiCameraPreview.layout = .pictureInPicture(
    primaryRect: CGRect(x: 0, y: 0, width: 1, height: 1),
    secondaryRect: CGRect(x: 0.65, y: 0.05, width: 0.3, height: 0.2)
)
```

### Side-by-Side

```swift
multiCameraPreview.layout = .sideBySide(splitRatio: 0.5)
```

### Top-Bottom

```swift
multiCameraPreview.layout = .topBottom(splitRatio: 0.5)
```

### Custom Layout

```swift
multiCameraPreview.layout = .custom { size in
    return [
        .back: CGRect(x: 0, y: 0, width: size.width * 0.7, height: size.height),
        .front: CGRect(x: size.width * 0.7, y: size.height * 0.2, 
                      width: size.width * 0.3, height: size.height * 0.6)
    ]
}
```

## Advanced Features

### Camera Switching

```swift
@IBAction func switchCamerasTapped() {
    // Animate camera position swap
    multiCameraPreview.switchCameras(animated: true)
}
```

### Dynamic Configuration

```swift
// Change recording mode on the fly
@IBAction func recordingModeChanged(_ sender: UISegmentedControl) {
    switch sender.selectedSegmentIndex {
    case 0:
        nextLevel.multiCameraConfiguration.recordingMode = .separate
    case 1:
        nextLevel.multiCameraConfiguration.recordingMode = .combined
    case 2:
        nextLevel.multiCameraConfiguration.recordingMode = .composited
    default:
        break
    }
}
```

### Thermal State Handling

```swift
extension MultiCameraViewController: NextLevelDelegate {
    
    func nextLevel(_ nextLevel: NextLevel, didUpdateVideoConfiguration videoConfiguration: NextLevelVideoConfiguration) {
        // Configuration was updated (possibly due to thermal state)
        DispatchQueue.main.async {
            self.updateQualityIndicator()
        }
    }
}

private func updateQualityIndicator() {
    let thermalState = ProcessInfo.processInfo.thermalState
    
    switch thermalState {
    case .nominal:
        qualityLabel.text = "Quality: High"
        qualityLabel.textColor = .green
    case .fair:
        qualityLabel.text = "Quality: Medium"
        qualityLabel.textColor = .yellow
    case .serious:
        qualityLabel.text = "Quality: Low"
        qualityLabel.textColor = .orange
    case .critical:
        qualityLabel.text = "Quality: Minimal"
        qualityLabel.textColor = .red
        showThermalWarning()
    @unknown default:
        break
    }
}
```

### Focus and Exposure

```swift
override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let touch = touches.first else { return }
    
    let location = touch.location(in: multiCameraPreview)
    
    // Determine which camera was tapped
    if let position = multiCameraPreview.cameraPosition(at: location) {
        // Focus at point for specific camera
        multiCameraPreview.focus(at: location, for: position)
        
        // Show focus indicator
        showFocusIndicator(at: location, for: position)
    }
}
```

## Best Practices

1. **Check Device Support**
   ```swift
   guard NextLevel.shared.isMultiCameraSupported else {
       // Fallback to single camera mode
       return
   }
   ```

2. **Handle Thermal States**
   ```swift
   // Monitor thermal state and adjust quality
   NotificationCenter.default.addObserver(
       self,
       selector: #selector(thermalStateChanged),
       name: ProcessInfo.thermalStateDidChangeNotification,
       object: nil
   )
   ```

3. **Optimize Performance**
   ```swift
   // Use lower resolution for multi-camera
   config.preferredFrameRate = 30  // Not 60
   config.videoConfiguration.preset = .hd1280x720  // Not 4K
   ```

4. **Memory Management**
   ```swift
   // Process frames efficiently
   func nextLevel(_ nextLevel: NextLevel, 
                  didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                  from position: NextLevelDevicePosition) {
       autoreleasepool {
           // Process frame
           processFrame(sampleBuffer)
       }
   }
   ```

5. **Error Handling**
   ```swift
   do {
       try nextLevel.startMultiCameraRecording()
   } catch NextLevelError.notReadyToRecord {
       // Handle not ready state
   } catch MultiCameraRecordingError.invalidConfiguration {
       // Handle configuration issues
   } catch {
       // Handle other errors
   }
   ```

## Troubleshooting

### Common Issues

1. **Multi-camera not starting**
   - Check device compatibility (iPhone XS/XR or newer)
   - Ensure no other app is using the camera
   - Check thermal state isn't critical

2. **Poor performance**
   - Lower frame rate to 24 or 30 fps
   - Use smaller resolution (720p instead of 1080p)
   - Disable video stabilization

3. **Recording fails**
   - Check available storage space
   - Ensure proper permissions
   - Verify output directory exists

4. **Preview issues**
   - Update preview after session configuration
   - Check preview layer connections
   - Verify camera positions are correct