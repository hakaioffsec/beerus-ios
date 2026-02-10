import Foundation
import MachO

enum DeviceInfo {

    /// Returns the CPU architecture of the current device (e.g. "arm64", "arm64e").
    static var architecture: String {
        var sysinfo = utsname()
        uname(&sysinfo)

        // Machine hardware name (e.g. "iPhone10,4")
        // But for actual CPU subtype we use sysctl
        var type: cpu_type_t = 0
        var subtype: cpu_subtype_t = 0
        var size = MemoryLayout<cpu_type_t>.size

        sysctlbyname("hw.cputype", &type, &size, nil, 0)
        size = MemoryLayout<cpu_subtype_t>.size
        sysctlbyname("hw.cpusubtype", &subtype, &size, nil, 0)

        switch type {
        case CPU_TYPE_ARM64:
            switch subtype {
            case CPU_SUBTYPE_ARM64E:
                return "arm64e"
            case CPU_SUBTYPE_ARM64_ALL, CPU_SUBTYPE_ARM64_V8:
                return "arm64"
            default:
                return "arm64"
            }
        case CPU_TYPE_ARM:
            switch subtype {
            case CPU_SUBTYPE_ARM_V7S:
                return "armv7s"
            case CPU_SUBTYPE_ARM_V7:
                return "armv7"
            case CPU_SUBTYPE_ARM_V6:
                return "armv6"
            default:
                return "arm"
            }
        case CPU_TYPE_X86_64:
            return "x86_64"
        case CPU_TYPE_X86:
            return "i386"
        default:
            return "unknown"
        }
    }

    /// Returns the device model identifier (e.g. "iPhone10,4", "iPad13,1").
    static var modelIdentifier: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
