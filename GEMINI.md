# MacPolish — Gemini Agent Context

This file is read by Google Gemini CLI (and other Gemini-based agents) on every session in this repo. Mirrors `CLAUDE.md` so any AI agent picks up the same context.

## What this repo is

**MacPolish** is a native macOS desktop app — a CleanMyMac X clone — built solo and shipped via GitHub Releases.

It scans the user's Mac, surfaces junk/duplicates/large files/malware, and lets the user clean them safely. It also includes an **AI Assistant** chat panel powered by **OpenRouter** (the user supplies their own OpenRouter key).

The full implementation plan lives at:
**`/Users/kingsleyasah/.claude/plans/i-want-to-be-crispy-crystal.md`** — read it before making non-trivial architecture decisions.

## Stack & decisions (don't relitigate without asking)

- **Language / UI:** Swift + SwiftUI (target macOS 14+ Sonoma)
- **Architecture:** MVVM with `@Observable` macro + `actor` scan engines + `AsyncThrowingStream` for progress. **No TCA, no Combine.**
- **Project layout:** Single `MacPolish.xcodeproj` workspace + local SPM packages (`MPCore`, `MPUI`, `MPScanners`, `MPAI`, `MPHelperClient`)
- **Privileged actions:** A privileged helper tool registered via `SMAppService.daemon(...)`. IPC over `NSXPCConnection`. Hardcoded path allowlist + `SecCodeCheckValidity` on every connection.
- **AI:** OpenRouter (OpenAI-compatible API) — default model `anthropic/claude-opus-4.7`, user-switchable. Key in Keychain, never UserDefaults. Tool-use is scoped: read-only tools auto-execute; destructive tools (`clean_items`) always round-trip through a SwiftUI confirmation modal.
- **Sandbox:** **OFF.** A sandboxed cleaner is a contradiction. Documented in README.
- **Distribution:** Unsigned ad-hoc builds via GitHub Releases for now; pipeline ready for notarization once an Apple Developer account is in place.
- **Auto-update:** Sparkle 2 with EdDSA signatures (Apple cert not required for Sparkle's integrity check).

## Modules (v1, ~20)

Cleanup core: System Junk · Mail Attachments · Trash Bins · Time Machine Snapshots
Files: Space Lens · Large & Old Files · Duplicate Finder · Photo Library Cleaner · Shredder
Apps: Uninstaller · Updater · Extensions
Speed: Optimization · Maintenance · System Performance Monitor (menu bar) · Battery Health
Protection: Malware Removal · Privacy
AI: Smart Scan · Assistant chat · Onboarding Profile · Proactive Notifications · Shareable Reports · "What is this?" Inspector

Future versions documented in the plan file under "Future Versions Roadmap" (v1.1, v1.2, v2). **Do not implement deferred features without explicit go-ahead.**

## Build, test, ship

> The Xcode project doesn't exist yet — these are the commands once M1 (Skeleton) lands.

```bash
# Open in Xcode
open MacPolish.xcodeproj

# Headless build
xcodebuild -project MacPolish.xcodeproj -scheme MacPolish -configuration Debug build

# Headless archive (Release)
xcodebuild -project MacPolish.xcodeproj -scheme MacPolish -configuration Release \
  -archivePath build/MacPolish.xcarchive \
  -destination "generic/platform=macOS" \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual archive

# Run all SPM tests
swift test

# Verify universal binary after archive
lipo -info build/MacPolish.xcarchive/Products/Applications/MacPolish.app/Contents/MacOS/MacPolish
```

CI: `.github/workflows/release.yml` triggers on tag `v*.*.*` and uploads `.dmg` + `.zip` + `SHA256SUMS.txt` to a GitHub Release.

## Coding conventions

- **No emojis** in source code, comments, or commit messages unless the user explicitly asks.
- **Default to no comments.** Only write a comment when the *why* is non-obvious. Don't narrate what the code does.
- **No premature abstractions.** Three similar lines beats a half-baked helper.
- **No backwards-compat shims.** This is a greenfield app — change the code, don't add `// removed` markers.
- **Concurrency:** scan engines are `actor`s; ViewModels are `@Observable @MainActor`; cross-boundary progress is `AsyncThrowingStream`.
- **Destructive operations:** never `unlink` directly. Always quarantine first (`~/Library/Application Support/MacPolish/Quarantine/<timestamp>/`). User-driven "permanent delete" toggle gates real deletion after the 7-day quarantine window.
- **Helper tool:** never invoke a shell. Always direct binary + explicit argv. Validate every input path against the allowlist before doing anything.

## Things that will bite you (read this before debugging)

1. **TCC / Full Disk Access.** Scans return empty arrays without it, app looks broken. Detect grant via test-read of `/Library/Application Support/com.apple.TCC/TCC.db`. FDA can revoke when binary identity changes between updates.
2. **SIP-protected paths.** Even root can't write to `/System/`, most of `/usr/`. The `PathClassifier` in `MPCore` is the central authority — *use it before any write*.
3. **Helper not registered.** `SMAppService.daemon(...).status` returns `.requiresApproval` until the user toggles it on in System Settings → Login Items. Build a "Repair Helper" menu item that unregisters and re-registers.
4. **Apple Silicon vs Intel.** `system_profiler` keys differ. Battery IORegistry keys differ. Test on both.
5. **Browser SQLite.** Touching `History.db` while Safari/Chrome is open corrupts the user's profile. Always check open file handles via `lsof`-style logic before reading; refuse if open.
6. **OpenRouter spend.** **BYOK only — never ship your own OpenRouter key in the app binary.** Document costs during onboarding.

## What goes where

- `App/` — main app target (thin shell, just `@main` + `RootView` + entitlements + onboarding)
- `HelperTool/` — privileged daemon target (root). Tiny binary, links only `MPCore`.
- `Packages/MPCore/` — domain models, protocols, the shared `@objc HelperProtocol` for IPC, `PathClassifier`, `Quarantine`, `ProfileType`
- `Packages/MPUI/` — reusable SwiftUI components and design system (`ProgressRing`, `ItemList`, `ReportExporter`)
- `Packages/MPScanners/` — one folder per scanner module (e.g. `SystemJunk/`, `DuplicateFinder/`)
- `Packages/MPAI/` — `OpenRouterClient`, `ChatView`, `ProactiveDigest`, `InspectorPopover`, the Tool-use definitions
- `Packages/MPHelperClient/` — `NSXPCConnection` wrapper used by the app to talk to the helper

## When the user asks for changes

- **Cleaning behavior changes** → almost always require corresponding `PathClassifier` and `Quarantine` updates. Don't shortcut.
- **New scanner module** → folder under `Packages/MPScanners/Sources/<Name>/`, conform to `Scanner` protocol in `MPCore`, add to sidebar in `RootView`, add a smoke test under `Tests/MPScannersTests/`.
- **AI tool-use additions** → define the tool schema in `MPAI/Tools/`, wire it in `OpenRouterClient`, mark destructive tools with the confirmation-modal path.
- **Helper IPC additions** → update `MPCore/IPC/HelperProtocol.swift` (the shared interface), implement in `HelperTool/HelperListener.swift`, add allowlist entries if new paths are touched.

## Out of scope (don't propose unless asked)

VPN, clipboard manager, menu-bar icon manager, kernel-level real-time antivirus, App Sandbox enablement, App Store distribution.
