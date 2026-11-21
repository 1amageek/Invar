#!/usr/bin/env python3
"""Check local dependency declarations and design links; not behavioral acceptance."""
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
ROOT=Path(__file__).resolve().parents[1]
MANDATORY=['Purpose and Scope','Responsibilities and Boundaries','Related Designs','Architecture','Contracts and Invariants','Verification and Change Impact']
def manifest(path):
 with tempfile.TemporaryDirectory(prefix='invar-manifest-check-') as scratch:
  r=subprocess.run(['swift','package','--package-path',str(path),'--scratch-path',scratch,'dump-package'],capture_output=True,text=True,timeout=60,check=True)
  return json.loads(r.stdout)
try:
 current=manifest(ROOT); assert current['name']=='Invar'
 assert {p['name'] for p in current['products']}=={'VerificationCore','VerificationDiscovery','VerificationPlanner','VerificationStore','VerificationExplorer','VerificationBackends','VerificationRuntime','VerificationClient','VerificationDaemon','VerificationFormal','invar'}
 paths={e['fileSystem'][0]['identity']:Path(e['fileSystem'][0]['path']).resolve() for e in current['dependencies']}
 expected={identity:(ROOT/'..'/folder).resolve() for identity,folder in [('architectureexplorer','ArchitectureExplorer'),('formal','Formal'),('swift-sdk','swift-sdk')]}
 assert paths==expected,(paths,expected)
 dependencies={}
 required={'architectureexplorer':{'ArchitectureCore','ArchitectureIR','ArchitectureClient'},'formal':{'FormalCore','FormalIR','FormalCompiler','FormalValidation','FormalEvidence'},'swift-sdk':{'MCP'}}
 for identity,path in paths.items():
  products={p['name'] for p in manifest(path)['products']}; assert required[identity]<=products
  dependencies[identity]={'localPath':'../'+path.name,'requiredProducts':sorted(required[identity])}
 designs=[p for p in ROOT.rglob('DESIGN.md') if not any(part == '.git' or part.startswith('.build') for part in p.parts)]
 for path in designs:
  source=path.read_text()
  for heading in MANDATORY: assert '## '+heading in source,(str(path),heading)
 for path in ROOT.rglob('*.md'):
  if any(part in {'.git','Requirements'} or part.startswith('.build') for part in path.parts): continue
  for target in re.findall(r'\]\(([^)]+)\)',path.read_text()):
   if '://' in target or target.startswith('#'): continue
   assert (path.parent/target.split('#',1)[0]).resolve().is_file(),(str(path),target)
 plan=(ROOT/'Documentation/VERIFICATION-PLAN.md').read_text(); identifiers=[]
 for first,last in re.findall(r'\| INV-(\d{3})(?:\.\.(\d{3}))? \|',plan): identifiers.extend(range(int(first),int(last or first)+1))
 assert sorted(identifiers)==list(range(1,49))
 root_design=ROOT/'DESIGN.md'; reached=set(); pending=[root_design]
 while pending:
  path=pending.pop().resolve()
  if path in reached: continue
  reached.add(path)
  for target in re.findall(r'\]\(([^)]+)\)',path.read_text()):
   if '://' in target: continue
   linked=(path.parent/target.split('#',1)[0]).resolve()
   if linked.name=='DESIGN.md' and linked.is_relative_to(ROOT): pending.append(linked)
 assert {p.resolve() for p in designs}<=reached, sorted(str(p) for p in designs if p.resolve() not in reached)
 assert not list((ROOT/'Documentation/Requirements').glob('ArchitectureExplorer-EXTENSIONS*'))
 for filename in ['EXTENSIONS-SPEC.md','EXTENSIONS-API.md']:
  assert (ROOT/'../ArchitectureExplorer/Documentation'/filename).is_file()
 print(json.dumps({'scope':'Manifest and document structure only; not behavioral acceptance','designFiles':len(designs),'acceptanceIDsMapped':len(identifiers),'localDependencies':dependencies},indent=2))
except (AssertionError,OSError,ValueError,subprocess.SubprocessError) as error:
 print(str(error),file=sys.stderr); sys.exit(1)
