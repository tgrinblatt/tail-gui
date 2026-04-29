import Foundation

struct TailProcess: Identifiable, Hashable {
    let pid: Int32
    let filePath: String
    let discoveredAt: Date

    var id: Int32 { pid }
}
