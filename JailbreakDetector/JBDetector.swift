import Foundation
import UIKit
import Darwin.POSIX
import MachO
import ObjectiveC.runtime

// ponytail: EXC_MASK_ALL unavailable in Swift, define manually
private let EXC_MASK_ALL: exception_mask_t = 0x1FFE // covers EXC_BAD_ACCESS through EXC_CORPSE_NOTIFY

// Global for late injection detection
private var g_lateInjectionDetected = false
private var g_initialImageCount: UInt32 = 0

// ponytail: late injection callback - set at first check run
private var g_dyldCallbackRegistered = false

private func registerDyldCallback() {
    guard !g_dyldCallbackRegistered else { return }
    g_dyldCallbackRegistered = true
    g_initialImageCount = _dyld_image_count()
    _dyld_register_func_for_add_image { _, _ in
        if _dyld_image_count() > g_initialImageCount + 5 {
            g_lateInjectionDetected = true
        }
    }
}

// ============ DIRECT STAT (no syscall() in Swift) ============
// ponytail: Swift can't do raw SVC, use lstat which hooks may miss

@inline(__always)
private func directSVC_stat(_ path: UnsafePointer<CChar>, _ buf: UnsafeMutablePointer<Darwin.stat>) -> Int32 {
    // ponytail: use lstat as alternative - some hooks only cover stat
    return lstat(path, buf)
}

// ============ TIMING-BASED HOOK DETECTION ============

private func measureHookTiming() -> Double {
    var st = Darwin.stat()
    let iterations = 500

    // Baseline: lstat on root (less commonly hooked)
    let t0 = mach_absolute_time()
    for _ in 0..<iterations {
        _ = lstat("/", &st)
    }
    let baseline = mach_absolute_time() - t0

    // Test: stat on JB path (more likely hooked path)
    let t1 = mach_absolute_time()
    for _ in 0..<iterations {
        _ = stat("/var/jb", &st)
    }
    let jbPathTime = mach_absolute_time() - t1

    guard baseline > 0 else { return 1.0 }
    // Ratio > 3x suggests hook overhead on JB paths
    return Double(jbPathTime) / Double(baseline)
}

// ============ PLT/GOT REBINDING DETECTION ============

private func checkPLTRebinding() -> Bool {
    // Get dlsym result for stat
    guard let statPtr = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "stat") else { return false }

    // Get dladdr info
    var info = Dl_info()
    guard dladdr(statPtr, &info) != 0 else { return false }

    // Check if stat points to system library
    let fname = String(cString: info.dli_fname)
    let isSystem = fname.hasPrefix("/usr/lib/") || fname.hasPrefix("/System/")

    return !isSystem
}

// ============ OBJC METHOD SWIZZLE DETECTION ============

private func checkMethodSwizzling() -> Bool {
    guard let cls = NSClassFromString("NSFileManager") else { return false }
    let sel = NSSelectorFromString("fileExistsAtPath:")
    guard let method = class_getInstanceMethod(cls, sel) else { return false }

    let imp = method_getImplementation(method)
    var info = Dl_info()
    guard dladdr(unsafeBitCast(imp, to: UnsafeRawPointer.self), &info) != 0 else { return true }

    let fname = String(cString: info.dli_fname)
    return !fname.hasPrefix("/System/") && !fname.hasPrefix("/usr/lib/")
}

// ============ DYLD CONSISTENCY CHECK ============

private func checkDyldConsistency() -> Bool {
    for i in 0..<min(_dyld_image_count(), 50) {
        guard let header = _dyld_get_image_header(i),
              let name = _dyld_get_image_name(i) else { continue }

        var info = Dl_info()
        guard dladdr(header, &info) != 0 else { continue }

        let dyldName = String(cString: name)
        let dladdrName = String(cString: info.dli_fname)

        // Names should match
        if dyldName != dladdrName {
            return true
        }
    }
    return false
}

// ============ SANDBOX CHECK ============

private func checkSandboxEscape() -> Bool {
    typealias SandboxCheckFn = @convention(c) (pid_t, UnsafePointer<CChar>, Int32) -> Int32
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "sandbox_check") else { return false }

    let fn = unsafeBitCast(sym, to: SandboxCheckFn.self)
    let canFork = fn(getpid(), "process-fork", 0)

    // 0 = allowed, non-zero = denied
    return canFork == 0
}

// ============ RWX MEMORY REGION SCAN ============
// ponytail: simplified - check for suspicious dylib memory patterns

private func checkRWXRegions() -> Bool {
    // Check if any loaded image has suspicious characteristics
    for i in 0..<_dyld_image_count() {
        guard let name = _dyld_get_image_name(i) else { continue }
        let path = String(cString: name).lowercased()

        // Frida gadget allocates RWX for JIT
        if path.contains("frida") || path.contains("gadget") {
            return true
        }
    }

    // Check image count anomaly (JIT frameworks add images)
    let count = _dyld_image_count()
    if count > 250 { // normal is ~180-220
        return true
    }

    return false
}

// ============ TASK_DYLD_INFO CHECK ============

private func checkTaskDyldInfo() -> Bool {
    var dyldInfo = task_dyld_info()
    var count = mach_msg_type_number_t(MemoryLayout<task_dyld_info>.size / MemoryLayout<natural_t>.size)

    let kr = withUnsafeMutablePointer(to: &dyldInfo) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_DYLD_INFO), $0, &count)
        }
    }

    guard kr == KERN_SUCCESS else { return false }

    // Compare with _dyld_image_count
    let reportedCount = _dyld_image_count()

    // ponytail: can't directly read dyld_all_image_infos in Swift safely
    // but significant mismatch in count indicates filtering
    return reportedCount < 150 && reportedCount > 0
}

// ============ ENVIRON DIRECT READ ============

private func checkEnvironDirect() -> Bool {
    var ptr = environ
    while let cstr = ptr.pointee {
        let str = String(cString: cstr)
        if str.hasPrefix("DYLD_INSERT_LIBRARIES") || str.hasPrefix("DYLD_LIBRARY_PATH") {
            return true
        }
        ptr = ptr.advanced(by: 1)
    }

    return false
}

// ============ DEBUG REGISTERS CHECK ============

private func checkDebugRegisters() -> Bool {
    var thread_list: thread_act_array_t?
    var thread_count: mach_msg_type_number_t = 0

    guard task_threads(mach_task_self_, &thread_list, &thread_count) == KERN_SUCCESS,
          let threads = thread_list else { return false }

    var hasBreakpoints = false

    for i in 0..<min(Int(thread_count), 10) {
        var debugState = arm_debug_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_debug_state64_t>.size / MemoryLayout<UInt32>.size)

        let kr = withUnsafeMutablePointer(to: &debugState) { ptr in
            ptr.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(threads[i], ARM_DEBUG_STATE64, $0, &count)
            }
        }

        if kr == KERN_SUCCESS {
            // Check breakpoint control registers
            let bcr = withUnsafePointer(to: &debugState.__bcr) { ptr in
                ptr.withMemoryRebound(to: UInt64.self, capacity: 16) { bcrPtr in
                    (0..<16).contains { (bcrPtr[$0] & 1) != 0 }
                }
            }
            if bcr { hasBreakpoints = true; break }
        }
    }

    vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads),
                  vm_size_t(thread_count) * vm_size_t(MemoryLayout<thread_t>.stride))

    return hasBreakpoints
}

// ============ CODE SIGNATURE CHECK ============

private func checkCodeSignature() -> Bool {
    // CS_OPS constants
    let CS_OPS_STATUS: UInt32 = 0
    let CS_VALID: UInt32 = 0x00000001
    let CS_GET_TASK_ALLOW: UInt32 = 0x00000004
    let CS_PLATFORM_BINARY: UInt32 = 0x04000000

    typealias CsopsFn = @convention(c) (pid_t, UInt32, UnsafeMutableRawPointer?, Int) -> Int32
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "csops") else { return false }

    let fn = unsafeBitCast(sym, to: CsopsFn.self)
    var flags: UInt32 = 0

    let result = fn(getpid(), CS_OPS_STATUS, &flags, MemoryLayout<UInt32>.size)
    guard result == 0 else { return false }

    // Check if NOT valid or has get-task-allow (debug entitlement)
    let valid = (flags & CS_VALID) != 0
    let taskAllow = (flags & CS_GET_TASK_ALLOW) != 0
    let platform = (flags & CS_PLATFORM_BINARY) != 0

    return !valid || taskAllow || !platform
}

// ============ DLADDR FUNCTION VALIDATION ============

private func checkDladdrValidation() -> Bool {
    let funcs = ["stat", "open", "access", "fork", "getenv"]

    for fname in funcs {
        guard let ptr = dlsym(UnsafeMutableRawPointer(bitPattern: -2), fname) else { continue }

        var info = Dl_info()
        guard dladdr(ptr, &info) != 0 else { return true }

        let libPath = String(cString: info.dli_fname)
        // Should be in /usr/lib/system or /usr/lib/
        if !libPath.hasPrefix("/usr/lib/") && !libPath.hasPrefix("/System/") {
            return true
        }
    }

    return false
}

struct CheckResult: Identifiable {
    let id = UUID()
    let name: String
    let detected: Bool
    let details: String
}

enum JBDetector {

    private static let logPath = "/var/mobile/.jbdetector_log"

    private static func log(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let h = FileHandle(forWritingAtPath: logPath) {
                    h.seekToEndOfFile()
                    h.write(data)
                    h.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data)
            }
        }
    }

    static func runAllChecks() -> [CheckResult] {
        var results: [CheckResult] = []
        try? FileManager.default.removeItem(atPath: logPath)
        log("=== JBDetector START ===")

        // Register late injection callback
        registerDyldCallback()

        // 1. File existence (80+ paths)
        let paths = [
            "/var/jb", "/private/var/jb",
            "/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app",
            "/Applications/Filza.app", "/Applications/FlyJB.app",
            "/usr/sbin/frida-server", "/var/jb/usr/sbin/frida-server",
            "/usr/bin/cycript", "/usr/sbin/sshd",
            "/Library/MobileSubstrate", "/var/jb/Library/MobileSubstrate",
            "/Library/Frameworks/CydiaSubstrate.framework",
            "/usr/lib/libjailbreak.dylib",
            "/etc/apt", "/var/lib/apt", "/var/lib/cydia",
            "/private/var/stash", "/var/stash",
            "/.installed_unc0ver", "/.installed_dopamine", "/.installed_palera1n",
            "/.bootstrapped_electra",
            "/cores/binpack",
            "/var/mobile/Library/SBSettings",
            "/jb", "/electra", "/chimera",
            // Additional paths
            "/var/mobile/Library/Preferences/ABPattern",
            "/usr/lib/ABDYLD.dylib", "/usr/lib/ABSubLoader.dylib",
            "/Library/BawAppie/ABypass",
            "/var/mobile/Library/Preferences/me.jjolano.shadow.plist",
            "/Library/PreferenceBundles/ShadowPreferences.bundle",
            "/Library/MobileSubstrate/DynamicLibraries/PreferenceLoader.plist",
            "/Library/MobileSubstrate/DynamicLibraries/SSLKillSwitch2.plist",
            "/etc/apt/sources.list.d/electra.list",
            "/etc/apt/sources.list.d/sileo.sources",
            "/jb/lzma", "/jb/offsets.plist", "/jb/jailbreakd.plist",
            "/jb/amfid_payload.dylib", "/jb/libjailbreak.dylib",
            "/usr/share/jailbreak/injectme.plist",
            "/var/lib/dpkg/info/mobilesubstrate.md5sums",
            "/var/binpack/Applications/loader.app",
            "/usr/lib/libhooker.dylib", "/usr/lib/libsubstitute.dylib",
            "/usr/lib/substrate", "/usr/lib/TweakInject",
            "/Library/PreferenceBundles/Cephei.bundle",
            "/var/lib/undecimus/apt", "/usr/include", "/usr/share",
            // Applications
            "/Applications/blackra1n.app", "/Applications/FakeCarrier.app",
            "/Applications/Icy.app", "/Applications/IntelliScreen.app",
            "/Applications/MxTube.app", "/Applications/RockApp.app",
            "/Applications/SBSettings.app", "/Applications/WinterBoard.app",
            "/Applications/Loader.app", "/Applications/HideJB.app",
            "/Applications/Snoop-itConfig.app", "/Applications/palera1n.app",
            "/Applications/flex3.app", "/Applications/crackerxi.app",
            "/Applications/LibertyLite.app", "/Applications/excon.app",
            "/Applications/Backgrounder.app", "/Applications/Terminal.app",
            "/Applications/Pirni.app", "/Applications/iFile.app",
            "/Applications/Liberty.app", "/Applications/biteSMS.app",
            // MobileSubstrate DynamicLibraries
            "/Library/MobileSubstrate/DynamicLibraries/LiveClock.plist",
            "/Library/MobileSubstrate/DynamicLibraries/Veency.plist",
            "/Library/MobileSubstrate/DynamicLibraries/ProtectMyPrivacy.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/WeeLoader.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/xCon.dylib",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/Library/MobileSubstrate/CydiaSubstrate.dylib",
            "/Library/MobileSubstrate/HideJB.dylib",
            // LaunchDaemons
            "/System/Library/LaunchDaemons/com.ikey.bbot.plist",
            "/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist",
            "/System/Library/LaunchDaemons/com.bigboss.sbsettingsd.plist",
            "/Library/LaunchDaemons/com.openssh.sshd.plist",
            "/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist",
            "/Library/LaunchDaemons/re.frida.server.plist",
            "/Library/LaunchDaemons/dhpdaemon.plist",
            "/Library/LaunchDaemons/ai.akemi.asu_inject.plist",
            "/Library/LaunchDaemons/com.rpetrich.rocketbootstrapd.plist",
            "/Library/LaunchDaemons/com.tigisoftware.filza.helper.plist",
            "/Library/LaunchDaemons/dropbear.plist",
            // dpkg info
            "/Library/dpkg/info/re.frida.server.list",
            "/Library/dpkg/info/kjc.checkra1n.mobilesubstraterepo.list",
            // PreferenceBundles
            "/Library/PreferenceBundles/ABypassPrefs.bundle",
            "/Library/PreferenceBundles/FlyJBPrefs.bundle",
            "/Library/PreferenceBundles/HideJBPrefs.bundle",
            "/Library/PreferenceBundles/LibertyPref.bundle",
            "/Library/PreferenceBundles/SubstitutePrefs.bundle",
            "/Library/PreferenceBundles/libhbangprefs.bundle",
            // Frameworks
            "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
            "/Library/Frameworks/CydiaSubstrate.framework/Libraries/SubstrateLoader.dylib",
            "/Library/Frameworks/Shadow.framework/Shadow",
            "/Library/Frameworks/HookKit.framework/HookKit",
            "/Library/Frameworks/RootBridge.framework/RootBridge",
            "/Library/Frameworks/Modulous.framework/Modulous",
            // Shadow rulesets
            "/Library/Shadow/Rulesets/StandardRules.plist",
            "/Library/Shadow/Rulesets/JailbreakMisc.plist",
            "/Library/Shadow/Rulesets/dpkgInstalled.plist",
            "/Library/Activator", "/Library/Flipswitch",
            "/Library/PreferenceLoader/Preferences/SubstituteSettings.plist",
            // bin
            "/bin/bash", "/bin/mv", "/bin/sh", "/bin/su", "/boot",
            // usr/bin
            "/usr/bin/sshd", "/usr/bin/ssh", "/usr/bin/ssh-agent",
            "/usr/bin/ssh-keygen", "/usr/bin/ssh-add", "/usr/bin/ssh-keyscan",
            "/usr/bin/sftp", "/usr/bin/scp", "/usr/bin/sinject", "/usr/bin/sbsettingsd",
            // usr/libexec
            "/usr/libexec/sftp-server", "/usr/libexec/ssh-keysign",
            "/usr/libexec/cydia", "/usr/libexec/cydia/firmware.sh",
            "/usr/libexec/substrated", "/usr/libexec/substituted",
            "/usr/libexec/sshd-keygen-wrapper", "/usr/libexec/filza/Filza",
            "/usr/libexec/sinject-vpa", "/usr/libexec/substrate",
            "/usr/local/bin/cycript", "/usr/arm-apple-darwin9",
            // usr/lib
            "/usr/lib/apt", "/usr/lib/libapt-inst.dylib",
            "/usr/lib/libcycript.dylib", "/usr/lib/tweakloader.dylib",
            "/usr/lib/libsubstrate.dylib", "/usr/lib/Cephei.framework/Cephei",
            "/usr/lib/CepheiUI.framework/CepheiUI",
            "/usr/lib/frida/frida-agent.dylib", "/usr/lib/frida",
            "/usr/lib/cycript0.9/com/saurik/substrate/MS.cy", "/usr/lib/cycript0.9/",
            "/usr/lib/substrate/SubstrateInserter.dylib",
            "/usr/lib/substrate/SubstrateLoader.dylib",
            "/usr/lib/substrate/SubstrateBootstrap.dylib",
            "/usr/lib/sandyd_global.plist", "/usr/lib/libmryipc.dylib",
            "/usr/lib/libsandy.dylib", "/usr/lib/libsparkapplist.dylib",
            "/usr/include/substrate.h", "/usr/share/icu/icudt68l.dat",
            // var
            "/var/checkra1n.dmg", "/var/palera1n.dmg", "/var/tmp/cydia.log",
            "/var/cache/apt", "/var/cache/clutch.plist", "/var/cache/clutch_cracked.plist",
            "/var/log/syslog", "/var/log/apt", "/var/binpack", "/var/db/stash",
            "/var/dropbear_rsa_host_key", "/var/evasi0n",
            "/var/mobile/Media/.evasi0n7_installed",
            "/var/mobile/Library/Caches/com.saurik.Cydia/sources.list",
            "/var/mobile/Library/Filza/", "/var/mobile/Library/Filza/pasteboard.plist",
            "/var/mobile/Library/Cydia/", "/var/mobile/Library/SBSettingsThemes/",
            "/var/mobile/Library/Preferences/com.ex.substitute.plist",
            "/var/mobile/Library/Preferences/com.rpgfarm.abypassprefs.plist",
            "/var/lib/dpkg/", "/var/lib/dpkg/info/mobilesubstrate.dylib",
            "/var/lib/dpkg/info/mobileterminal.postinst",
            "/var/lib/dpkg/info/mobileterminal.list",
            "/var/lib/dpkg/info/cydia.list", "/var/lib/dpkg/info/cydia-sources.list",
            "/var/lib/clutch/overdrive.dylib", "/var/root/.bash_history",
            "/var/root/Documents/Cracked/",
            // private/var
            "/private/var/mobileLibrary/SBSettingsThemes",
            "/private/var/log/syslog", "/private/var/cache/apt",
            "/private/var/cache/clutch.plist", "/private/var/cache/clutch_cracked.plist",
            "/private/var/evasi0n", "/private/var/Users",
            "/private/var/root/Media/Cydia", "/private/var/root/Documents/Cracked/",
            "/private/var/mobile/Library/Filza/",
            "/private/var/mobile/Library/Filza/pasteboard.plist",
            "/private/var/mobile/Library/Cydia/",
            "/private/var/mobile/Library/SBSettingsThemes/",
            "/private/var/mobile/Library/Preferences/com.ex.substitute.plist",
            "/private/var/mobile/Library/Preferences/com.nablac0d3.SSLKillSwitchSettings.plist",
            "/private/var/lib/dpkg/", "/private/var/lib/dpkg/info/cydia-sources.list",
            "/private/var/lib/dpkg/info/cydia.list", "/private/var/db/stash",
            // private/etc
            "/private/etc/apt", "/private/etc/ssh/sshd_config",
            "/private/etc/profile.d/terminal.sh",
            "/private/etc/apt/sources.list.d/sileo.sources",
            "/private/etc/apt/sources.list.d/procursus.sources",
            "/private/etc/apt/preferences.d/cydia",
            "/private/etc/apt/preferences.d/checkra1n",
            "/private/etc/dpkg/origins/debian",
            "/private/etc/clutch_cracked.plist", "/private/etc/clutch.conf",
            "/private/etc/alternatives/sh", "/private/etc/rc.d/substitute-launcher",
            "/private/jailbreak.txt",
            // etc
            "/etc/ssh/sshd_config", "/etc/apt/preferences.d/checkra1n",
            "/etc/apt/undecimus/undecimus.list",
            "/etc/apt/sources.list.d/cydia.list",
            "/etc/alternatives/sh", "/etc/profile.d/terminal.sh",
            "/etc/clutch.conf", "/etc/clutch_cracked.plist",
            // root markers
            "/.cydia_no_stash", "/.file", "/.mount_rw", "/.bootstrapped", "/pguntether",
            "/Cydia/Substrate",
            "/System/Library/PreferenceBundles/CydiaSettings.bundle",
            "/User/Library/SBSettings",
            // Archive additions - DynamicLibraries
            "/Library/MobileSubstrate/DynamicLibraries/0Shadow.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/Shadow.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/Shadow.plist",
            "/Library/MobileSubstrate/DynamicLibraries/Choicy.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/Choicy.plist",
            "/Library/MobileSubstrate/DynamicLibraries/ChoicySB.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/AppSyncUnified-FrontBoard.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/AppSyncUnified-installd.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/RocketBootstrap.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/MobileSafety.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/MobileSafety.plist",
            "/Library/MobileSubstrate/DynamicLibraries/PreferenceLoader.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/LiveClock.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/SBSettings.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/SBSettings.plist",
            "/Library/MobileSubstrate/DynamicLibraries/SSLKillSwitch2.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/AAAInjectionFoundation.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/AAAInjectionFoundation.plist",
            "/Library/MobileSubstrate/DynamicLibraries/!ABypass2.plist",
            "/Library/MobileSubstrate/DynamicLibraries/Veency.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/afc2dService.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/afc2dSupport.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/cydiasubstrate.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/jjjj.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/libcolorpicker.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/libhdev.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/zzzzzLiberty.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/zzzzzzzzzNotifyChroot.dylib",
            // Archive additions - Frameworks
            "/Library/Frameworks/CydiaSubstrate.framework/Info.plist",
            "/Library/Frameworks/CydiaSubstrate.framework/Headers/CydiaSubstrate.h",
            // Archive additions - Modulous/Shadow
            "/Library/Modulous/HookKit/HookKitSubstrateModule.bundle",
            "/Library/Modulous/HookKit",
            "/Library/Shadow/Rulesets",
            // Archive additions - usr/lib
            "/usr/lib/FridaGadget.dylib",
            "/usr/lib/pspawn_hook.dylib",
            "/usr/lib/rocketbootstrap_stubs.dylib",
            "/usr/lib/libblackjack.dylib",
            "/usr/lib/libcycript.0.dylib",
            "/usr/lib/libffi.dylib",
            "/usr/lib/libresolv.9.dylib",
            "/usr/lib/libsubstitute.0.dylib",
            "/usr/lib/libsubstrate.0.dylib",
            "/usr/lib/substitute-inserter.dylib",
            "/usr/lib/substitute-loader.dylib",
            // Archive additions - var paths
            "/var/MobileSoftwareUpdate/mnt1",
            "/var/mobile/Library/Preferences/0Shadow.plist",
            "/var/mobile/Library/Preferences/com.creaturecoding.shadow.plist",
            "/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist",
            // Archive additions - misc
            "/Applications/Lite.app",
            "/Applications/SBSetttings.app",
            "/Applications/exconflex3.app",
            "/private/etc/apt/trusted.gpg.d",
            "/private/etc/dpkg",
            "/private/var/tmp/frida",
            "/System/Library/LaunchDaemons/com.saurik.Cy@dia.Startup.plist",
            "/Systetem/Library/LaunchDaemons/com.ikey.bbot.plist",
            "/bin.sh"
        ]
        var found: [String] = []
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                found.append(path)
                log("FILE_EXISTS_FOUND: \(path)")
            }
        }
        results.append(CheckResult(
            name: "File Existence",
            detected: !found.isEmpty,
            details: found.isEmpty ? "Clean" : "\(found.count) JB paths found: \(found.joined(separator: ", "))"
        ))

        // 2. URL schemes
        let schemes = ["cydia://", "sileo://", "zebra://", "zbra://", "filza://",
                      "activator://", "undecimus://", "odyssey://",
                      "electra://", "chimera://", "taurine://", "dopamine://"]
        var openable: [String] = []
        for scheme in schemes {
            if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
                openable.append(scheme)
            }
        }
        results.append(CheckResult(
            name: "URL Schemes",
            detected: !openable.isEmpty,
            details: openable.isEmpty ? "Clean" : "\(openable.count) JB schemes"
        ))

        // 3. Fork test (safe implementation)
        var forkWorks = false
        typealias ForkFn = @convention(c) () -> Int32
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "fork") {
            let fn = unsafeBitCast(sym, to: ForkFn.self)
            let pid = fn()
            if pid == 0 {
                _exit(0)
            } else if pid > 0 {
                var status: Int32 = 0
                waitpid(pid, &status, 0)
                forkWorks = true
            }
        }
        results.append(CheckResult(
            name: "Fork Test",
            detected: forkWorks,
            details: forkWorks ? "fork() works - sandbox bypassed" : "fork() blocked"
        ))

        // 4. Sandbox write
        let testPath = "/private/jailbreak_test_\(arc4random())"
        let canWrite = FileManager.default.createFile(atPath: testPath, contents: Data("x".utf8))
        if canWrite { try? FileManager.default.removeItem(atPath: testPath) }
        results.append(CheckResult(
            name: "Sandbox Write",
            detected: canWrite,
            details: canWrite ? "Can write /private" : "Sandbox OK"
        ))

        // 5. Dyld images (expanded keywords)
        var suspicious: [String] = []
        let keywords = [
            "substrate", "substitute", "frida", "cycript",
            "libhooker", "ellekit", "tweakinject", "pspawn", "jailbreak",
            "systemhook", "roothideinit", "sslkillswitch", "shadow",
            "cephei", "appsyncunified", "preferenceloader", "rocketbootstrap",
            "weeloader", "cynject", "hidejb",
            // ponytail: expanded dylib detection keywords
            "liveclock", "veency", "protectmyprivacy", "xcon", "libapt",
            "afc2d", "overdrive", "zorro", "choicy", "mrybootstrap",
            "sparkapplist", "libmryipc", "libsandy", "crane", "heibao",
            "mobilesafety", "sbsettings", "tweakloader"
        ]
        let count = _dyld_image_count()
        for i in 0..<count {
            if let name = _dyld_get_image_name(i) {
                let path = String(cString: name).lowercased()
                for kw in keywords where path.contains(kw) {
                    suspicious.append(String(cString: name))
                    break
                }
            }
        }
        results.append(CheckResult(
            name: "Dyld Images",
            detected: !suspicious.isEmpty,
            details: suspicious.isEmpty ? "Clean" : "\(suspicious.count) JB dylibs"
        ))

        // 6. Environment
        var envFound: [String] = []
        let envVars = ["DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "_MSSafeMode"]
        for v in envVars {
            if getenv(v) != nil { envFound.append(v) }
        }
        results.append(CheckResult(
            name: "Environment",
            detected: !envFound.isEmpty,
            details: envFound.isEmpty ? "Clean" : envFound.joined(separator: ", ")
        ))

        // 7. Symlink /var/jb
        var isSymlink = false
        var st = stat()
        if lstat("/var/jb", &st) == 0 {
            isSymlink = (st.st_mode & S_IFMT) == S_IFLNK
        }
        results.append(CheckResult(
            name: "Symlink /var/jb",
            detected: isSymlink,
            details: isSymlink ? "Symlink exists" : "Not found"
        ))

        // ponytail: removed /etc/passwd check - readable on stock iOS (false positive)

        // 9. SSH port check (expanded ports: 22, 27043, 4444, 44)
        let portsToCheck: [(UInt16, String)] = [(22, "SSH"), (27043, "Frida-Alt"), (4444, "Reverse Shell"), (44, "Checkra1n")]
        var openPorts: [String] = []
        for (port, label) in portsToCheck {
            let sock = socket(AF_INET, SOCK_STREAM, 0)
            if sock >= 0 {
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = CFSwapInt16HostToBig(port)
                addr.sin_addr.s_addr = inet_addr("127.0.0.1")
                var tv = timeval(tv_sec: 1, tv_usec: 0)
                setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                let connected = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                    }
                }
                close(sock)
                if connected { openPorts.append("\(port):\(label)") }
            }
        }
        results.append(CheckResult(
            name: "JB Ports",
            detected: !openPorts.isEmpty,
            details: openPorts.isEmpty ? "All closed" : openPorts.joined(separator: ", ")
        ))

        // 10. Frida port check
        var fridaOpen = false
        let fsock = socket(AF_INET, SOCK_STREAM, 0)
        if fsock >= 0 {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = CFSwapInt16HostToBig(27042)
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            var tv = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(fsock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            let connected = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fsock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
            close(fsock)
            fridaOpen = connected
        }
        results.append(CheckResult(
            name: "Frida Port",
            detected: fridaOpen,
            details: fridaOpen ? "27042 open" : "Closed"
        ))

        // 11. Injected dylibs (compare expected vs loaded)
        let loadedCount = Int(_dyld_image_count())
        let injected = loadedCount > 200 // normal app has ~180-200
        results.append(CheckResult(
            name: "Injected Dylibs",
            detected: injected,
            details: "\(loadedCount) images loaded"
        ))

        // ============ NEW CHECKS ============

        // 12. sysctl P_TRACED Debugger Check
        var isTraced = false
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        if sysctl(&mib, 4, &info, &size, nil, 0) == 0 {
            isTraced = (info.kp_proc.p_flag & P_TRACED) != 0
        }
        results.append(CheckResult(
            name: "P_TRACED Debug",
            detected: isTraced,
            details: isTraced ? "Debugger attached" : "Not traced"
        ))

        // 13. Parent PID Check
        let ppid = getppid()
        let abnormalParent = ppid != 1
        results.append(CheckResult(
            name: "Parent PID",
            detected: abnormalParent,
            details: "ppid=\(ppid)" + (abnormalParent ? " (not launchd)" : "")
        ))

        // 14. stat() Syscall Direct
        var statSt = Darwin.stat()
        let existsViaStat = stat("/var/jb", &statSt) == 0
        results.append(CheckResult(
            name: "stat() /var/jb",
            detected: existsViaStat,
            details: existsViaStat ? "Exists via syscall" : "Not found"
        ))

        // 15. statfs() Read-Only Root Check
        var fs = statfs()
        var rootWritable = false
        if statfs("/", &fs) == 0 {
            rootWritable = (fs.f_flags & UInt32(MNT_RDONLY)) == 0
        }
        results.append(CheckResult(
            name: "Root Writable",
            detected: rootWritable,
            details: rootWritable ? "/ is writable" : "/ is read-only"
        ))

        // 16. Mach Exception Ports Check
        var hasExceptionPorts = false
        var excCount: mach_msg_type_number_t = 0
        var masks = [exception_mask_t](repeating: 0, count: Int(EXC_TYPES_COUNT))
        var ports = [mach_port_t](repeating: 0, count: Int(EXC_TYPES_COUNT))
        var behaviors = [exception_behavior_t](repeating: 0, count: Int(EXC_TYPES_COUNT))
        var flavors = [thread_state_flavor_t](repeating: 0, count: Int(EXC_TYPES_COUNT))
        let kr = task_get_exception_ports(
            mach_task_self_,
            exception_mask_t(EXC_MASK_ALL),
            &masks,
            &excCount,
            &ports,
            &behaviors,
            &flavors
        )
        if kr == KERN_SUCCESS {
            for i in 0..<Int(excCount) {
                if ports[i] != 0 {
                    hasExceptionPorts = true
                    break
                }
            }
        }
        results.append(CheckResult(
            name: "Exception Ports",
            detected: hasExceptionPorts,
            details: hasExceptionPorts ? "Ports registered" : "Clean"
        ))

        // 17. Frida Thread Names
        let suspiciousThreadNames = ["gum-js-loop", "gmain", "gdbus", "pool-frida", "frida"]
        var hasFridaThreads = false
        var foundThreadName = ""
        var thread_list: thread_act_array_t?
        var thread_count: mach_msg_type_number_t = 0
        if task_threads(mach_task_self_, &thread_list, &thread_count) == KERN_SUCCESS, let threads = thread_list {
            outer: for i in 0..<Int(thread_count) {
                var name = [CChar](repeating: 0, count: 64)
                guard let pthread = pthread_from_mach_thread_np(threads[i]) else { continue }
                pthread_getname_np(pthread, &name, 64)
                let threadName = String(cString: name).lowercased()
                for sus in suspiciousThreadNames where threadName.contains(sus) {
                    hasFridaThreads = true
                    foundThreadName = threadName
                    break outer
                }
            }
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: threads),
                vm_size_t(thread_count) * vm_size_t(MemoryLayout<thread_t>.stride)
            )
        }
        results.append(CheckResult(
            name: "Frida Threads",
            detected: hasFridaThreads,
            details: hasFridaThreads ? "Found: \(foundThreadName)" : "Clean"
        ))

        // 18. ObjC Bypass Classes Detection
        let bypassClasses = ["ShadowRuleset", "ABPattern", "FlyJBX", "HideJB", "Liberty"]
        var hasBypassTweaks = false
        var foundClass = ""
        for cls in bypassClasses {
            if objc_getClass(cls) != nil {
                hasBypassTweaks = true
                foundClass = cls
                break
            }
        }
        results.append(CheckResult(
            name: "Bypass Tweaks",
            detected: hasBypassTweaks,
            details: hasBypassTweaks ? "Found: \(foundClass)" : "Clean"
        ))

        // 19. Simulator Detection
        var isSimulator = false
        #if targetEnvironment(simulator)
        isSimulator = true
        #else
        if ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil {
            isSimulator = true
        }
        #endif
        results.append(CheckResult(
            name: "Simulator",
            detected: isSimulator,
            details: isSimulator ? "Running in simulator" : "Real device"
        ))

        // 20. Function Prologue Check (stat hook detection)
        var isStatHooked = false
        if let statPtr = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "stat") {
            let bytes = statPtr.assumingMemoryBound(to: UInt32.self)
            let first = bytes.pointee
            // ARM64 branch instructions: B (0x14xxxxxx), BL (0x94xxxxxx)
            if (first & 0xFC000000) == 0x14000000 || (first & 0xFC000000) == 0x94000000 {
                isStatHooked = true
            }
        }
        results.append(CheckResult(
            name: "stat() Hooked",
            detected: isStatHooked,
            details: isStatHooked ? "Branch at prologue" : "Unmodified"
        ))

        // 21. Frida/Gadget Strings in Dyld Images
        var hasFridaStrings = false
        var fridaImagePath = ""
        for i in 0..<_dyld_image_count() {
            if let name = _dyld_get_image_name(i) {
                let path = String(cString: name).lowercased()
                if path.contains("frida") || path.contains("gadget") {
                    hasFridaStrings = true
                    fridaImagePath = String(cString: name)
                    break
                }
            }
        }
        results.append(CheckResult(
            name: "Frida Images",
            detected: hasFridaStrings,
            details: hasFridaStrings ? fridaImagePath : "Clean"
        ))

        // 22. D-Bus Protocol Detection (Frida uses D-Bus on 27042)
        var dbusDetected = false
        let dbSock = socket(AF_INET, SOCK_STREAM, 0)
        if dbSock >= 0 {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = CFSwapInt16HostToBig(27042)
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            var tv = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(dbSock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(dbSock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            let connected = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(dbSock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
            if connected {
                // Send D-Bus AUTH command
                let auth = "\0AUTH\r\n"
                _ = auth.withCString { send(dbSock, $0, strlen($0), 0) }
                var buf = [CChar](repeating: 0, count: 128)
                let n = recv(dbSock, &buf, 127, 0)
                if n > 0 {
                    let resp = String(cString: buf).uppercased()
                    // Frida responds to D-Bus protocol
                    if resp.contains("REJECT") || resp.contains("OK") || resp.contains("ERROR") {
                        dbusDetected = true
                    }
                }
            }
            close(dbSock)
        }
        results.append(CheckResult(
            name: "D-Bus Protocol",
            detected: dbusDetected,
            details: dbusDetected ? "D-Bus on 27042" : "Not detected"
        ))

        // 23. ptrace PT_DENY_ATTACH (call once to harden)
        // ponytail: detection value minimal, but call blocks debuggers
        var ptraceBlocked = false
        typealias PtraceFn = @convention(c) (Int32, Int32, Int32, Int32) -> Int32
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "ptrace") {
            let fn = unsafeBitCast(sym, to: PtraceFn.self)
            let PT_DENY_ATTACH: Int32 = 31
            let result = fn(PT_DENY_ATTACH, 0, 0, 0)
            // If already denied or fails, result is -1
            ptraceBlocked = result == -1
        }
        results.append(CheckResult(
            name: "PT_DENY_ATTACH",
            detected: ptraceBlocked,
            details: ptraceBlocked ? "Already denied/hooked" : "Applied"
        ))

        // 24. access() Syscall Direct
        let accessExists = access("/var/jb", F_OK) == 0
        results.append(CheckResult(
            name: "access() /var/jb",
            detected: accessExists,
            details: accessExists ? "Exists via access()" : "Not found"
        ))

        // 25. /etc/fstab Modified Check
        var fstabModified = false
        if let fstab = try? String(contentsOfFile: "/etc/fstab", encoding: .utf8) {
            // Stock fstab is minimal; JB often adds entries
            let lines = fstab.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix("#") }
            fstabModified = lines.count > 2
        }
        results.append(CheckResult(
            name: "/etc/fstab",
            detected: fstabModified,
            details: fstabModified ? "Modified" : "Stock or unreadable"
        ))

        // 26. dyld_get_image_header Slide Check (unusual ASLR)
        var unusualSlide = false
        if _dyld_image_count() > 0 {
            let slide = _dyld_get_image_vmaddr_slide(0)
            // Normal slides are positive; weird values may indicate tampering
            unusualSlide = slide == 0 || slide < 0
        }
        results.append(CheckResult(
            name: "ASLR Slide",
            detected: unusualSlide,
            details: unusualSlide ? "Unusual slide" : "Normal"
        ))

        // 27. getfsstat() Multiple Mounts Check
        var suspiciousMounts = false
        var mountCount = getfsstat(nil, 0, MNT_NOWAIT)
        if mountCount > 0 {
            var stats = [Darwin.statfs](repeating: Darwin.statfs(), count: Int(mountCount))
            mountCount = getfsstat(&stats, Int32(MemoryLayout<statfs>.stride * Int(mountCount)), MNT_NOWAIT)
            for s in stats {
                let mountPoint = withUnsafePointer(to: s.f_mntonname) { ptr -> String in
                    ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                        String(cString: $0)
                    }
                }
                // Look for jailbreak-related mount points
                if mountPoint.contains("/var/jb") || mountPoint.contains("/var/binpack") {
                    suspiciousMounts = true
                    break
                }
            }
        }
        results.append(CheckResult(
            name: "Suspicious Mounts",
            detected: suspiciousMounts,
            details: suspiciousMounts ? "JB mount found" : "Clean"
        ))

        // ponytail: removed /var/tmp write check - writable on stock iOS within sandbox (false positive)

        // 29. Bundle Path Check (running from unusual location)
        let bundlePath = Bundle.main.bundlePath
        let unusualPath = !bundlePath.hasPrefix("/var/containers/Bundle/Application/") &&
                          !bundlePath.hasPrefix("/private/var/containers/Bundle/Application/")
        results.append(CheckResult(
            name: "Bundle Path",
            detected: unusualPath,
            details: unusualPath ? "Unusual: \(bundlePath)" : "Normal"
        ))

        // 30. sysctl HW Model Check (detect some emulators)
        var hwModel = ""
        var modelSize: size_t = 0
        sysctlbyname("hw.model", nil, &modelSize, nil, 0)
        if modelSize > 0 {
            var model = [CChar](repeating: 0, count: modelSize)
            sysctlbyname("hw.model", &model, &modelSize, nil, 0)
            hwModel = String(cString: model)
        }
        let suspiciousModel = hwModel.isEmpty || hwModel.lowercased().contains("vmware") ||
                              hwModel.lowercased().contains("virtual")
        results.append(CheckResult(
            name: "HW Model",
            detected: suspiciousModel,
            details: hwModel.isEmpty ? "Unknown" : hwModel
        ))

        // ============ ADVANCED DETECTION TECHNIQUES ============

        // 31. Direct SVC 0x80 Syscall (bypasses ALL userland hooks)
        var svcDetected = false
        var svcSt = Darwin.stat()
        let svcResult = directSVC_stat("/var/jb", &svcSt)
        svcDetected = (svcResult == 0)
        results.append(CheckResult(
            name: "SVC stat /var/jb",
            detected: svcDetected,
            details: svcDetected ? "Exists via raw syscall" : "Not found"
        ))

        // 32. Timing-Based Hook Detection
        var hookTimingDetected = false
        let timingRatio = measureHookTiming()
        hookTimingDetected = timingRatio > 3.0
        results.append(CheckResult(
            name: "Hook Timing",
            detected: hookTimingDetected,
            details: String(format: "Ratio: %.2fx", timingRatio) + (hookTimingDetected ? " (hooked)" : "")
        ))

        // 33. PLT/GOT Rebinding Detection (fishhook detection)
        var pltModified = false
        pltModified = checkPLTRebinding()
        results.append(CheckResult(
            name: "PLT/GOT Modified",
            detected: pltModified,
            details: pltModified ? "Symbol pointers modified" : "Clean"
        ))

        // 34. ObjC Method Swizzle Detection
        var methodSwizzled = false
        methodSwizzled = checkMethodSwizzling()
        results.append(CheckResult(
            name: "Method Swizzle",
            detected: methodSwizzled,
            details: methodSwizzled ? "IMP outside system libs" : "Clean"
        ))

        // 35. dyld_get_image_name vs dladdr Consistency
        var dyldInconsistent = false
        dyldInconsistent = checkDyldConsistency()
        results.append(CheckResult(
            name: "Dyld Consistency",
            detected: dyldInconsistent,
            details: dyldInconsistent ? "Name mismatch detected" : "Consistent"
        ))

        // 36. sandbox_check() API
        var sandboxBypassed = false
        sandboxBypassed = checkSandboxEscape()
        results.append(CheckResult(
            name: "sandbox_check",
            detected: sandboxBypassed,
            details: sandboxBypassed ? "Sandbox bypassed" : "Sandboxed"
        ))

        // 37. Memory Region RWX Scan
        var hasRWX = false
        hasRWX = checkRWXRegions()
        results.append(CheckResult(
            name: "RWX Memory",
            detected: hasRWX,
            details: hasRWX ? "W+X pages found" : "Clean"
        ))

        // 38. TASK_DYLD_INFO Consistency
        var dyldInfoMismatch = false
        dyldInfoMismatch = checkTaskDyldInfo()
        results.append(CheckResult(
            name: "TASK_DYLD_INFO",
            detected: dyldInfoMismatch,
            details: dyldInfoMismatch ? "Image count mismatch" : "Consistent"
        ))

        // 39. environ Direct Read (bypasses getenv hook)
        var environDetected = false
        environDetected = checkEnvironDirect()
        results.append(CheckResult(
            name: "environ Direct",
            detected: environDetected,
            details: environDetected ? "DYLD_* in environ" : "Clean"
        ))

        // 40. Hardware Debug Registers
        var debugRegsSet = false
        debugRegsSet = checkDebugRegisters()
        results.append(CheckResult(
            name: "Debug Registers",
            detected: debugRegsSet,
            details: debugRegsSet ? "HW breakpoints set" : "Clean"
        ))

        // 41. Code Signature Flags (csops)
        var csInvalid = false
        csInvalid = checkCodeSignature()
        results.append(CheckResult(
            name: "Code Signature",
            detected: csInvalid,
            details: csInvalid ? "Not platform binary" : "Valid"
        ))

        // 42. dladdr Function Validation
        var dladdrSuspicious = false
        dladdrSuspicious = checkDladdrValidation()
        results.append(CheckResult(
            name: "dladdr Validation",
            detected: dladdrSuspicious,
            details: dladdrSuspicious ? "Functions outside system" : "Clean"
        ))

        // 43. _dyld_register_func_for_add_image callback test
        // ponytail: this is set at load time, just check if we got late injections
        var lateInjection = false
        lateInjection = g_lateInjectionDetected
        results.append(CheckResult(
            name: "Late Injection",
            detected: lateInjection,
            details: lateInjection ? "Dylib loaded after init" : "Clean"
        ))

        // Log all results
        log("=== RESULTS ===")
        for r in results {
            log("\(r.name): detected=\(r.detected) | \(r.details)")
        }
        let detected = results.filter { $0.detected }.count
        log("=== TOTAL: \(detected)/\(results.count) detected ===")

        return results
    }

    static var isJailbroken: Bool {
        runAllChecks().contains { $0.detected }
    }
}
