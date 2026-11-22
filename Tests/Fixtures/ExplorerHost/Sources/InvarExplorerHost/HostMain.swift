import ArchitectureClient
import ArchitectureCore
import ArchitectureService
import ArchitectureStore
import Darwin
import Foundation
import VerificationClient
import VerificationCore
import VerificationFormal
import FormalEvidence

@main struct HostMain {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.count >= 2 else { throw InvarError("INVALID_ARGUMENT","Expected fixture command/workspace") }
            let command = arguments[0], paths = try WorkspacePaths(arguments[1])
            if command == "serve" {
                try paths.prepareState()
                let store = try SQLiteGraphStore(path: paths.state.appendingPathComponent("graph.sqlite").path,workspaceID: paths.workspaceID)
                let daemon = try ArchitectureDaemon(paths: paths,store: store)
                try await daemon.run()
                return
            }
            if command == "identity" {
                let peer = try ConnectionPeer.current()
                try output(.object(["workspaceID":.string(paths.workspaceID),"binaryDigest":.string(peer.binaryDigest),"codeIdentity":.string(peer.codeIdentity),"state":.string(paths.state.path)])); return
            }
            if command == "configuration" {
                guard arguments.count == 3 else { throw InvarError("INVALID_ARGUMENT","Expected captured configuration path") }
                let path = try paths.resolve(arguments[2])
                let bytes = try Data(contentsOf: path)
                guard bytes.count <= 262144 else { throw InvarError("RESOURCE_LIMIT","Configuration fixture is too large") }
                let configuration = try ConfigurationReader.decode(bytes)
                let digest = try configuration.identity()
                try output(.object(["digest":.string(digest)])); return
            }
            if command == "rpc" {
                guard arguments.count == 4, arguments[3].utf8.count <= 65536 else { throw InvarError("INVALID_ARGUMENT","Expected method and bounded JSON") }
                let bytes = Data(arguments[3].utf8), parameters = try JSONDecoder().decode(JSONValue.self,from: bytes)
                let value = try await ArchitectureClient(workspace: paths.root.path).call(arguments[2],parameters: parameters)
                try output(value); return
            }
            guard ["request","query","formal"].contains(command), arguments.count == 5 else { throw InvarError("INVALID_ARGUMENT","Expected client state/key/payload") }
            let state = URL(fileURLWithPath: arguments[2])
            let endpointPaths = DaemonEndpointPaths(workspaceID: paths.workspaceID,userID: getuid(),homeDirectory: FileManager.default.homeDirectoryForCurrentUser,stateDirectory: state)
            let admin = LocalDaemonAdministration(paths: endpointPaths)
            let endpoint = try await admin.endpoint(); await admin.shutdown()
            let client = try await LocalVerificationClient.connect(endpoint: endpoint)
            defer { await client.shutdown() }
            guard arguments[4].utf8.count <= 65536 else { throw InvarError("RESOURCE_LIMIT","Fixture payload exceeds typed limit") }
            let bytes = Data(arguments[4].utf8)
            if command == "formal" {
                let request = try JSONDecoder().decode(JSONValue.self,from: bytes)
                guard let evidenceID = request["evidenceID"].string else { throw InvarError("INVALID_ARGUMENT","Expected evidence ID") }
                let reference = try request["bundle"].decode(EvidenceBundleReference.self)
                let reader = try await RemoteFormalEvidenceStore(client: client,evidenceID: evidenceID).open(reference,budget: FormalReadPolicy.development.maximumBudget)
                let result: JSONValue
                do { result = try await inspect(reader) }
                catch {
                    let original = error
                    do { try await reader.shutdown() } catch { throw InvarError("CLEANUP_FAILED","Formal query failed (\(original)); shutdown failed (\(error))") }
                    throw original
                }
                try await reader.shutdown(); try output(result)
            } else if command == "request" {
                let operation = try JSONDecoder().decode(WorkspaceOperation.self,from: bytes)
                let timeout: Double
                switch operation {
                case .preparePlan(_,_,let budget): timeout = budget.runTimeoutSeconds
                case .verify(let id,_,_,_): timeout = try await client.plan(id).budget.runTimeoutSeconds
                default: timeout = 60
                }
                let fixed = try await client.prepare(operation,key: arguments[3],timeout: timeout)
                let receipt = try await client.accept(fixed)
                try output(JSONValue.encode(receipt))
            } else {
                let query = try JSONDecoder().decode(WorkspaceQuery.self,from: bytes)
                let value: JSONValue
                switch query {
                case .status: value = try await JSONValue.encode(client.status())
                case .demand(let id): value = try await JSONValue.encode(client.operation(id))
                case .plan(let id): value = try await JSONValue.encode(client.plan(id))
                case .run(let id): value = try await JSONValue.encode(client.run(id))
                case .runRecord(let id): value = try await JSONValue.encode(client.runRecord(id))
                case .providerAction(let id): value = try await JSONValue.encode(client.providerAction(id))
                case .publication(let id): value = try await JSONValue.encode(client.publication(id))
                case .watch(let id): value = try await JSONValue.encode(client.watch(id))
                case .watches: value = try await JSONValue.encode(client.watches())
                case .sourceHead: value = try await JSONValue.encode(client.sourceHead())
                case .currentView: value = try await JSONValue.encode(client.currentView())
                case .view(let id): value = try await JSONValue.encode(client.view(id))
                case .change(let id): value = try await JSONValue.encode(client.change(id))
                case .changeRevision(let id): value = try await JSONValue.encode(client.changeRevision(id))
                default: throw InvarError("INVALID_ARGUMENT","Query not used by this fixture")
                }
                try output(value)
            }
        } catch {
            let failure: InvarError
            if let typed = error as? InvarError { failure = typed }
            else if let typed = error as? ArchitectureError { failure = InvarError(typed.code,typed.message,exitCode: typed.exitCode) }
            else { failure = InvarError("FIXTURE_FAILED",String(describing: error)) }
            do { try output(JSONValue.encode(failure)) } catch { FileHandle.standardError.write(Data("Cannot encode fixture failure\n".utf8)) }
            exit(failure.exitCode)
        }
    }
    static func inspect(_ reader: any FormalEvidenceReading) async throws -> JSONValue {
        let catalog = try await reader.catalog()
        var graphs: [JSONValue] = []
        for graph in catalog.graphs where graph.extraction == "available" {
            let query = FormalGraphQuery(graphID: graph.id,roots: Array(graph.roots.prefix(8)),relations: [],direction: "outgoing",depth: 0)
            let page = try await reader.graph(query)
            graphs.append(.object(["kind":.string(graph.kind.rawValue),"roots":.number(Double(graph.roots.count)),"nodes":.number(Double(page.nodes.count)),"edges":.number(Double(page.edges.count)),"nodeKinds":.array(Set(page.nodes.map(\.kind)).sorted().map(JSONValue.string)),"edgeKinds":.array(Set(page.edges.map(\.kind)).sorted().map(JSONValue.string)),"producerScopeComplete":.bool(graph.complete),"pageHasMore":.bool(page.nextCursor != nil)]))
        }
        var documents: [JSONValue] = []
        if let document = catalog.documents.first {
            let count = min(document.byteCount,4096)
            let chunk = try await reader.document(DocumentRangeQuery(documentID: document.id,start: 0,count: count))
            documents.append(.object(["documentID":.string(document.id),"count":.number(Double(chunk.bytes.count)),"sha256":.string(Canonical.digest(chunk.bytes))]))
        }
        return .object(["graphs":.array(graphs),"documents":.array(documents)])
    }
    static func output(_ value: JSONValue) throws { var bytes = try CanonicalJSON.encode(value); bytes.append(10); FileHandle.standardOutput.write(bytes) }
}
