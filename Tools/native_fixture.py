"""Captured real native harnesses used by the owned daemon integration test."""
import hashlib
import json

def create_native_fixture(w, root, listener, compiler, sdk, tools_directory):
    def profile(harness):
        return {"compiler": str(compiler.absolute()), "sdk": str(sdk.resolve()), "toolsDirectory": str(tools_directory.resolve()),
                "modules": [{"name": "A", "sources": ["A.swift"]}, {"name": "B", "sources": ["B.swift"], "dependencies": ["A"]}], "harness": [harness]}
    secret = root / "outside-secret"
    secret.write_text("must not be readable")
    (w / 'A.swift').write_text('public func increment(_ value: Int64) -> Int64 { return value >= 7 ? value + 2 : value + 1 }\n')
    (w / 'B.swift').write_text('import A\npublic func evaluate(_ value: Int64) -> Int64 { return increment(value) * 2 }\n')
    (w / 'Harness.swift').write_text(r'''import B
@main struct Check { static func main() { let holds = evaluate(4) == 10; print("{\"schemaVersion\":1,\"testsRun\":1,\"holds\":\(holds)}") } }
''')
    (w / 'FuzzHarness.swift').write_text(r'''import B
@main struct Check { static func main() { guard CommandLine.arguments.count == 2, let value = Int64(CommandLine.arguments[1]) else { return }; let holds = evaluate(value) == value * 2 + 2; print("{\"schemaVersion\":1,\"testsRun\":1,\"holds\":\(holds)}") } }
''')
    (w / 'Trap.swift').write_text('@main struct Check { static func main() { fatalError("Expected hardware trap") } }\n')
    (w / 'Empty.swift').write_text(r'''@main struct Check { static func main() { print("{\"schemaVersion\":1,\"testsRun\":0,\"holds\":true}") } }
''')
    sandbox = r'''import Darwin
@main struct Check { static func main() {
 let file = open(SECRET, O_RDONLY); let fileDenied = file == -1; if file >= 0 { close(file) }
 let descriptor = socket(AF_INET, SOCK_STREAM, 0)
 var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET); address.sin_port = UInt16(PORT).bigEndian; address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
 let status = withUnsafePointer(to: &address) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }; if descriptor >= 0 { close(descriptor) }
 let networkDenied = status == -1
 // Swift marks fork unavailable; resolve the C symbol only to test the sandbox syscall denial.
 let handle = dlopen(nil, RTLD_NOW)
 guard let pointer = dlsym(handle, "fork") else { return }
 let nativeFork = unsafeBitCast(pointer, to: (@convention(c) () -> pid_t).self)
 let child = nativeFork(); if child == 0 { _exit(0) }; let forkDenied = child == -1
 let groupDenied = setpgid(0, getpgid(getppid())) == -1
 let sessionDenied = setsid() == -1
 let holds = fileDenied && networkDenied && forkDenied && groupDenied && sessionDenied
 print("{\"schemaVersion\":1,\"testsRun\":5,\"holds\":\(holds)}")
} }
'''
    (w / 'Sandbox.swift').write_text(sandbox.replace('SECRET', json.dumps(str(secret))).replace('PORT', str(listener.getsockname()[1])))
    (w / 'corpus.json').write_text('["100"]')
    checks = [{'id': 'native', 'profile': profile('Harness.swift'), 'approved': True},
              {'id': 'isolation', 'profile': profile('Sandbox.swift'), 'approved': True, 'expectedTestCount': 5},
              {'id': 'expected_trap', 'profile': profile('Trap.swift'), 'approved': True, 'expectedSignal': 5},
              {'id': 'unexpected_crash', 'profile': profile('Trap.swift'), 'approved': True},
              {'id': 'empty_oracle', 'profile': profile('Empty.swift'), 'approved': True}]
    config = {'schemaVersion': 1, 'native': checks, 'fuzz': [{'id': 'fuzz', 'profile': profile('FuzzHarness.swift'), 'corpus': 'corpus.json', 'seed': '7', 'minimum': '0', 'maximum': '100', 'iterations': 5, 'approved': True}]}
    paths = ["Harness.swift", "Sandbox.swift", "Trap.swift", "Empty.swift", "FuzzHarness.swift", "corpus.json"]
    entries = []
    for path in sorted(paths):
        data = (w / path).read_bytes()
        entries.append({"path": path, "digest": hashlib.sha256(data).hexdigest(), "byteCount": len(data)})
    return config, entries
