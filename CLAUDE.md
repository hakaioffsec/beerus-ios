# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Beerus Framework is an iOS security testing app for jailbroken devices. It provides tools for dynamic analysis, memory inspection, IPA extraction, Frida scripting, and more.

## Build Commands

```bash
./init build                    # Build .deb package
./init deploy --ip <IP>         # Build + install on device
./init install --ip <IP>        # Install existing .deb
./init clean                    # Remove build artifacts
./init deploy --rootless        # For palera1n/dopamine jailbreaks
```

Default SSH: 127.0.0.1:2222 (typical iproxy setup)

## Architecture

### Daemon (Daemon/)
Root-privileged C daemon (`beerusd`) that runs as a launchd service. App communicates via Unix socket at `/var/run/beerus.sock`. Handles:
- Frida server management (install/restart/uninstall)
- Root shell execution
- IPA installation
- Proxy configuration

Swift side: `RootExec` enum wraps socket communication. Use `RootExec.exec()` for simple commands, `RootExec.shell()` for streaming output with exit codes.

### App Structure (BEERUS Framework/Sources/)
- **Main/**: AppDelegate, SceneDelegate, ContainerViewController (side menu navigation)
- **Shared/**: Utilities, extensions, base classes, ViewCode protocol
- **Modules/**: Feature screens (Home, Frida, IPAExtractor, MemoryDump, LLDBServer, Proxy, Terminal, PlistReader, ScriptEditor, AppStore)

### UI Pattern
All view controllers use `ViewCode` protocol for programmatic UI:
```swift
protocol ViewCode {
    func buildViewHierarchy()   // addSubview calls
    func setupConstraints()     // NSLayoutConstraint.activate
    func setupAdditionalConfiguration()
}
```
Call `applyViewCode()` in viewDidLoad.

### Navigation
`ContainerViewController` manages side menu and module switching. View controllers implement `MenuButtonDelegate` to toggle menu. Each module lazy-loads its root VC.

## Key Files

- `Daemon/BeerusDaemon.c` - Root daemon implementation
- `Shared/Utils/RootExec.swift` - Daemon IPC client
- `Shared/Utils/FridaManager.swift` - Frida server lifecycle
- `Shared/Utils/AppManager.swift` - Installed app enumeration
- `Main/ViewController/ContainerViewController.swift` - Navigation hub

## Build Requirements

- Xcode with iOS SDK
- `ldid` for code signing
- `dpkg-deb` for packaging
- SSH access to jailbroken device
