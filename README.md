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
# First-time setup: copy the env template and add your OpenRouter key.
# (.env is gitignored. Release builds never embed this key.)
cp .env.example .env
$EDITOR .env

# Generate the dev-key Swift file from .env, then generate the Xcode project.
Tools/generate-dev-key.sh
xcodegen generate

# Open in Xcode
open MacPolish.xcodeproj

# Or build from command line
xcodebuild -project MacPolish.xcodeproj -scheme MacPolish -configuration Debug build
```

The build pre-script regenerates `App/Generated/DevAPIKey.swift` from `.env`
on every build, so editing `.env` is enough — no manual rerun needed after
the first setup.

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

## AI Assistant

The AI Assistant is powered by OpenRouter. Release builds ship with the
developer's bundled key (provisioned at build time from a server-side
proxy in the future); the AI is enabled automatically on first launch.

For local development, set `OPENROUTER_API_KEY` in `.env` (see Building
above). The key is embedded only in Debug builds; Release builds with
no proxy configured fall back to a Bring Your Own Key flow in Settings.

## License

All rights reserved.
