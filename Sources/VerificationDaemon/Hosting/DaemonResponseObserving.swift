import ArchitectureCore

protocol DaemonResponseObserving: Sendable {
    func responseFinished(_ request: JSONValue) async
}
