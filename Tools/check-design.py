#!/usr/bin/env python3
"""Check public package dependency declarations and design links."""
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
 expected={'architectureexplorer':('ArchitectureExplorer','0.1.4'),'swift-formal':('swift-formal','0.1.1'),'swift-sdk':('swift-sdk','0.15.0')}
 dependencies={}
 pins={pin['identity']:pin for pin in json.loads((ROOT/'Package.resolved').read_text())['pins']}
 for entry in current['dependencies']:
  assert 'sourceControl' in entry
  dependency=entry['sourceControl'][0]
  identity=dependency['identity']
  location=dependency['location']['remote'][0]['urlString']
  repository,expected_version=expected[identity]
  assert location==f'https://github.com/1amageek/{repository}.git'
  version,=dependency['requirement']['exact']
  assert pins[identity]['location']==location and pins[identity]['state']['version']==version==expected_version
  dependencies[identity]=version
 assert dependencies.keys()==expected.keys()
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
 print(json.dumps({'scope':'Manifest and document structure only; not behavioral acceptance','designFiles':len(designs),'acceptanceIDsMapped':len(identifiers),'pinnedDependencies':dependencies},indent=2))
except (AssertionError,KeyError,OSError,ValueError,subprocess.SubprocessError) as error:
 print(str(error),file=sys.stderr); sys.exit(1)
