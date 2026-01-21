# Tech Stack

## Platform

- macOS 14.0+ (Sonoma)
- Swift 5.9+
- SwiftUI + AppKit (NSViewRepresentable for Metal/AVPlayer views)
- Xcode 15+ project (objectVersion 77) with file system-based source discovery
- No external dependencies

## Core Frameworks

| Framework | Purpose |
|-----------|---------|
| AVFoundation | Video/audio composition, playback, export |
| CoreImage | Image processing, CIFilter effects |
| Metal | GPU compute shaders for real-time effects |
| CoreMedia | Time types (CMTime, CMTimeRange) |
| Photos | Apple Photos library integration |
| CoreAudio | Audio device management |

## Data

- **Settings**: JSON in `~/Library/Application Support/Hypnograph/`
- **Recipes**: `.hypno|.hypnogram format (PNG with embedded JSON metadata)
