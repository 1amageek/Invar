import ArchitectureCore
import VerificationCore

struct DaemonHostDispatcher: DaemonRequestHandling, DaemonResponseObserving {
    let record: DaemonHostRecord
    let host: any DaemonHostControlling
    let application: any DaemonRequestHandling
    func handle(_ request: JSONValue,channel: DaemonRPCChannel) async throws -> JSONValue? {
        guard request["method"].string?.hasPrefix("host.") == true else { return try await application.handle(request,channel: channel) }
        guard channel == .control, case .object(let fields) = request, Set(fields.keys) == Set(["id","protocolVersion","workspaceID","epoch","method","body"]),
            request["protocolVersion"].int == 3, request["workspaceID"].string == record.endpoint.workspaceID,
            request["epoch"].string == record.epoch else { throw InvarError("AUTHENTICATION_REQUIRED","Host control workspace or epoch differs",exitCode: 8) }
        let result: DaemonStatus
        switch request["method"].string {
        case "host.status":
            guard request["body"] == .object([:]) else { throw InvarError("INVALID_REQUEST","Host status has no parameters") }
            result = try await host.administrativeStatus()
        case "host.stop":
            guard case .object(let fields) = request["body"], Set(fields.keys) == Set(["mode","deadlineSeconds"]), let text = request["body"]["mode"].string, let mode = DaemonStopMode(rawValue: text), case .number(let seconds) = request["body"]["deadlineSeconds"] else { throw InvarError("INVALID_REQUEST","Stop needs a typed mode/deadline") }
            result = try await host.requestStop(mode: mode,deadlineSeconds: seconds,requestID: request["id"].string ?? "")
        default: throw InvarError("METHOD_NOT_FOUND","Unknown host-control operation")
        }
        return try JSONValue.encode(result)
    }
    func responseFinished(_ request: JSONValue) async {
        guard request["method"].string == "host.stop", request["workspaceID"].string == record.endpoint.workspaceID,
            request["epoch"].string == record.epoch,
            let id = request["id"].string else { return }
        await host.stopResponseFinished(requestID: id)
    }

}
