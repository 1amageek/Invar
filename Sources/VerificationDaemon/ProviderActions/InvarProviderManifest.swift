import ArchitectureCore
import ArchitectureExtensions

/// Source confirmation describes a sealed operation; host execution grants remain separate.
public enum InvarProviderManifest {
    public static var value: ExtensionManifest {
        let identifier: JSONValue = .object(["type":.string("string"),"minLength":.number(1),"maxLength":.number(128)])
        let verify: JSONValue = .object(["type":.string("object"),"properties":.object(["planID":identifier,"changeRevisionID":identifier]),"required":.array([.string("planID")]),"additionalProperties":.bool(false)])
        let cancel: JSONValue = .object(["type":.string("object"),"properties":.object(["requestID":identifier,"jobID":identifier,"runID":.object(["type":.string("string"),"minLength":.number(1),"maxLength":.number(256)])]),"required":.array([.string("requestID"),.string("jobID"),.string("runID")]),"additionalProperties":.bool(false)])
        let project: JSONValue = .object(["type":.string("object"),"properties":.object(["configuration":.object(["type":.string("string"),"minLength":.number(1),"maxLength":.number(1024)])]),"required":.array([.string("configuration")]),"additionalProperties":.bool(false)])
        return ExtensionManifest(extensionID: "invar",displayName: "Invar",version: "2.0.0",requestedPermissions: [.graphRead,.inputsRead,.eventsSubscribe,.graphsWrite,.viewsWrite,.annotationsWrite,.runsWrite,.actionsReceive],actions: [
            ExtensionActionDefinition(id: "verify-project",title: "Verify project specification and implementation",inputSchemaID: "invar.verify-project.v1",inputSchema: project),
            ExtensionActionDefinition(id: "verify-model",title: "Verify the selected model",inputSchemaID: "invar.verify-model.v2",inputSchema: .object(["type":.string("object"),"properties":.object(["specification":.object(["type":.string("string"),"minLength":.number(1),"maxLength":.number(1024)])]),"required":.array([]),"additionalProperties":.bool(false)])),
            ExtensionActionDefinition(id: "verify",title: "Verify sealed plan with approved configured tools and code",inputSchemaID: "invar.verify.v2",inputSchema: verify),
            ExtensionActionDefinition(id: "cancel",title: "Cancel original Invar verification",operation: "cancel",inputSchemaID: "invar.cancel.v2",inputSchema: cancel)
        ])
    }
}
