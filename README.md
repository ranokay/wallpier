# Wallpier

**Dynamic Wallpaper Cycling for macOS**

A fast, elegant, and memory-efficient macOS application that automatically cycles through your favorite wallpapers with intelligent multi-monitor support, built with SwiftUI.

![Wallpier Main Interface](screenshots/main-interface.png)

## ✨ Features

### 🖼️ **Smart Wallpaper Management**

- **Recursive folder scanning** - Automatically finds images in subfolders
- **Multiple format support** - JPEG, PNG, HEIC, BMP, TIFF, GIF, WebP
- **Intelligent caching** - Memory-efficient image preloading and management
- **Real-time monitoring** - Automatically detects new images added to folders

### 🖥️ **Multi-Monitor Excellence**

- **Independent wallpapers** - Different images on each monitor
- **Synchronized mode** - Same wallpaper across all displays
- **Per-screen controls** - Manual wallpaper selection for individual monitors
- **Dynamic detection** - Automatically adapts to monitor configuration changes

### ⚡ **Performance Optimized**

- **Memory efficient** - Intelligent caching with configurable limits (50MB default)
- **Background processing** - Non-blocking file operations
- **Smart preloading** - Loads next wallpaper in advance for seamless transitions
- **Aggressive optimization** - Memory pressure monitoring and cleanup

### 🎛️ **Flexible Controls**

- **Customizable intervals** - From 10 seconds to 24 hours
- **Shuffle mode** - Random wallpaper selection
- **Manual navigation** - Previous/next controls
- **Sorting options** - Name, date, size, random
- **Scaling modes** - Fill, fit, stretch, center, tile

### 📱 **Menu Bar Integration**

- **Native menu bar controls** - Start/stop, navigate, browse
- **Real-time status** - Current image, countdown timer, memory usage
- **Quick actions** - Folder selection, gallery browser, settings
- **System integration** - Launch at startup, dock hiding options

## 📋 Requirements

- **macOS 11.0+** (Big Sur or later)
- **Apple Silicon** or Intel Mac
- **File system permissions** for selected wallpaper folders

## 🚀 Installation

### Option 1: Build from Source

```bash
git clone https://github.com/yourusername/wallpier.git
cd wallpier
open wallpier.xcodeproj
```

Build and run using Xcode 14.0+

### Option 2: Download Release

Download the latest release from [Releases](https://github.com/yourusername/wallpier/releases)

## 📖 Usage

### Getting Started

1. **Launch Wallpier** and grant necessary permissions
2. **Select a folder** containing your wallpaper images
3. **Configure settings** - Set interval, enable shuffle, choose scaling
4. **Start cycling** and enjoy automatic wallpaper changes

### Multi-Monitor Setup

- **Same wallpaper**: Check "Use same wallpaper on all monitors"
- **Different wallpapers**: Uncheck the option for independent images per screen
- **Manual selection**: Use "Browse Wallpapers" → click monitor previews

### Menu Bar Controls

- **Green icon** = Running, **Red icon** = Error, **Gray icon** = Stopped
- **Click for menu** with start/stop, navigation, and settings
- **Inline controls** for quick previous/start/stop/next actions

## 🏗️ Architecture

### **MVVM Pattern**

- **Models**: `WallpaperSettings`, `ImageFile`, `CycleConfiguration`
- **ViewModels**: `WallpaperViewModel`, `SettingsViewModel`
- **Views**: SwiftUI interface with native macOS controls

### **Core Services**

- **WallpaperService** - System integration for setting wallpapers
- **ImageScannerService** - Recursive folder scanning and file discovery
- **ImageCacheService** - Memory-efficient image caching and preloading
- **FileMonitorService** - Real-time folder change detection
- **SystemService** - macOS system integration and permissions

### **Performance Features**

- **Async/await** for all file operations
- **Combine framework** for reactive state management
- **Background queues** for non-blocking processing
- **Smart memory management** with automatic cleanup

## ⚙️ Configuration

### **Cycling Settings**

```swift
// Interval range
10 seconds - 24 hours

// Supported formats
.jpg, .jpeg, .png, .heic, .bmp, .tiff, .gif, .webp

// Scaling modes
Fill, Fit, Stretch, Center, Tile
```

### **Performance Tuning**

- **Cache size**: Configurable memory limit (default: 50MB)
- **Preload distance**: Number of images to preload (default: 1)
- **Memory pressure**: Automatic cleanup at 300MB app usage
- **Image optimization**: Auto-downsample to 2MP for previews

### **Multi-Monitor Options**

- **Independent cycling**: Different images per screen
- **Synchronized mode**: Same wallpaper across displays
- **Per-screen scaling**: Individual scaling modes per monitor

## 🔧 Development

### **Building**

```bash
# Clone repository
git clone https://github.com/yourusername/wallpier.git
cd wallpier

# Open in Xcode
open wallpier.xcodeproj

# Build for release
xcodebuild -project wallpier.xcodeproj -scheme wallpier -configuration Release build
```

### **Testing**

```bash
# Run tests
xcodebuild test -project wallpier.xcodeproj -scheme wallpier -destination 'platform=macOS'
```

### **Code Style**

- Swift 5.7+ modern syntax
- SwiftUI for interface, AppKit for system integration
- Async/await for concurrent operations
- Comprehensive error handling

## 📊 Performance Benchmarks

- **Startup time**: < 2 seconds
- **Memory usage**: < 100MB steady state
- **Folder scan**: < 1000ms for 500 images
- **Wallpaper change**: < 500ms average
- **Cache hit rate**: > 70% target efficiency

## 🔒 Privacy & Permissions

Wallpier respects your privacy:

- **Local operation only** - No network activity
- **User-selected folders only** - Access only to chosen directories
- **Sandboxed application** - macOS security compliance
- **No data collection** - All processing happens locally

## 🐛 Troubleshooting

### Common Issues

**Wallpaper not changing**

- Check folder permissions
- Verify image file formats
- Ensure cycling is active (green menu bar icon)

**High memory usage**

- Reduce cache size in advanced settings
- Use smaller image files
- Enable memory pressure monitoring

**Multi-monitor issues**

- Check "Use same wallpaper" setting
- Verify monitor detection in settings
- Restart app after monitor changes

### **Debug Information**

- Menu bar shows real-time memory usage
- Performance statistics in advanced view
- Detailed logging available in settings

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### **Development Setup**

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with [SwiftUI](https://developer.apple.com/xcode/swiftui/) and [Combine](https://developer.apple.com/documentation/combine)
- Uses [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace) for wallpaper integration
- Performance monitoring via [mach_task_basic_info](https://developer.apple.com/documentation/kernel/mach_task_basic_info)

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/wallpier/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/wallpier/discussions)
- **Wiki**: [Project Wiki](https://github.com/yourusername/wallpier/wiki)

---

**Made with ❤️ for macOS users who love beautiful wallpapers**
