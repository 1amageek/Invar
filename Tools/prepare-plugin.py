#!/usr/bin/env python3
"""Prepare a local agent marketplace pinned to a development binary and workspace."""
import argparse
import json
from pathlib import Path
import shutil
import os
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--workspace", type=Path, required=True)
parser.add_argument("--binary", type=Path, default=root / ".build/debug/invar")
parser.add_argument("--state", type=Path, help="Existing private daemon store when using a non-default location")
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
binary = args.binary.resolve(strict=True)
workspace = args.workspace.resolve(strict=True)
output = args.output.absolute()
if not binary.is_file() or not os.access(binary, os.X_OK) or not workspace.is_dir():
    parser.error("Expected an executable Invar binary and an existing workspace directory.")
if output.exists():
    parser.error("Select a new marketplace directory.")
output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(dir=output.parent) as temp:
    stage = Path(temp) / "marketplace"
    for relative in [".agents/plugins", ".claude-plugin", "plugins/invar"]:
        shutil.copytree(root / relative, stage / relative)
    config = stage / "plugins/invar/.mcp.json"
    manifest = json.loads(config.read_text())
    server = manifest["mcpServers"]["invar"]
    server["command"] = str(binary)
    server["args"].extend(["--workspace", str(workspace)])
    if args.state is not None:
        state = args.state.resolve(strict=True)
        if not state.is_dir():
            parser.error("Expected an existing daemon store directory.")
        server["args"].extend(["--state", str(state)])
    config.write_text(json.dumps(manifest, indent=2) + "\n")
    stage.rename(output)
print(output)
