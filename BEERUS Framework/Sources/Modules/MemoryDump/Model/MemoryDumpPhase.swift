import Foundation

enum MemoryDumpPhase: Equatable {
    case connecting, attaching, dumping, packaging, complete

    var title: String {
        switch self {
        case .connecting: "CONNECTING"
        case .attaching: "ATTACHING"
        case .dumping: "DUMPING"
        case .packaging: "PACKAGING"
        case .complete: "COMPLETE"
        }
    }

    var subtitle: String {
        switch self {
        case .connecting: "checking frida server"
        case .attaching: "attach to target process"
        case .dumping: "reading memory regions"
        case .packaging: "creating zip archive"
        case .complete: "done"
        }
    }

    var icon: String {
        switch self {
        case .connecting: "magnifyingglass"
        case .attaching: "link"
        case .dumping: "memorychip"
        case .packaging: "archivebox"
        case .complete: "checkmark.seal"
        }
    }
}
