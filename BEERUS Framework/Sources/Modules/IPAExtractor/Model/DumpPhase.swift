import Foundation

enum DumpPhase: Equatable {
    case checking, attaching, loading, dumping, building, complete

    var title: String {
        switch self {
        case .checking: "CHECKING"
        case .attaching: "ATTACHING"
        case .loading: "LOADING"
        case .dumping: "DUMPING"
        case .building: "BUILDING"
        case .complete: "COMPLETE"
        }
    }

    var subtitle: String {
        switch self {
        case .checking: "verify frida connection"
        case .attaching: "attach to target process"
        case .loading: "inject dump script"
        case .dumping: "extract decrypted binary"
        case .building: "package ipa archive"
        case .complete: "done"
        }
    }

    var icon: String {
        switch self {
        case .checking: "magnifyingglass"
        case .attaching: "link"
        case .loading: "doc.text"
        case .dumping: "arrow.down.doc"
        case .building: "archivebox"
        case .complete: "checkmark.seal"
        }
    }
}
