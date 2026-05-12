# MacPolish

A powerful native macOS cleaner with AI-driven insights. Built with Swift + SwiftUI, targeting macOS 14+ Sonoma.

## What It Does

MacPolish scans your Mac, surfaces junk files, duplicates, large/old files, and malware, then lets you clean them safely with a quarantine-first approach. It also includes an AI Assistant powered by OpenRouter for intelligent cleanup recommendations.

## Features (v1 Target)

**Cleanup:** System Junk, Mail Attachments, Trash Bins, Time Machine Snapshots
**Files:** Space Lens, Large & Old Files, Duplicate Finder, Photo Library Cleaner, Shredder
**Applications:** Uninstaller, Updater, Extensions
**Speed:** Optimization, Maintenance, System Performance Monitor, Battery Health
**Protection:** Malware Removal, Privacy
**AI:** Smart Scan, AI Assistant, Onboarding Profile, Proactive Notifications, Shareable Reports, "What is this?" Inspector

## Requirements

- macOS 14.0 Sonoma or later
- Xcode 15+ (for building)
- XcodeGen (`brew install xcodegen`)

## Building

```bash
# Generate the Xcode project
xcodegen generate

# Open in Xcode
open MacPolish.xcodeproj

# Or build from command line
xcodebuild -project MacPolish.xcodeproj -scheme MacPolish -configuration Debug build
```

## Project Structure

```
App/                    Main app target (thin shell)
HelperTool/             Privileged daemon for root operations
Packages/
  MPCore/               Domain models, protocols, IPC contract
  MPUI/                 Design system and reusable components
  MPScanners/           All scan engine modules
  MPAI/                 OpenRouter client, chat, AI tools
  MPHelperClient/       XPC wrapper for app-to-helper IPC
Tools/                  Build scripts
.github/workflows/      CI pipeline
```

## Important: Unsigned Binary

This app is currently distributed as an unsigned binary. On first launch:

1. Right-click the app
2. Select "Open"
3. Click "Open" in the dialog

macOS will remember your choice for future launches.

## Full Disk Access

MacPolish requires Full Disk Access to scan system caches, logs, and other cleanup targets. The app will guide you through granting this permission on first launch.

## AI Assistant (BYOK)

The AI Assistant uses OpenRouter (Bring Your Own Key). You pay OpenRouter directly for API usage. MacPolish never stores or transmits your billing information. Get a key at https://openrouter.ai/keys.

## License

All rights reserved.
