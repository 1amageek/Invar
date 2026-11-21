#!/usr/bin/env python3
"""Validate versioned schemas and actual private ledger records, without exporting bytes."""
import argparse
import json
from pathlib import Path
import sqlite3
from jsonschema import Draft202012Validator, ValidationError
from referencing import Registry, Resource

p = argparse.ArgumentParser(); p.add_argument('--store', type=Path); a = p.parse_args()
root = Path(__file__).resolve().parents[1]
schemas = [json.loads(p.read_text()) for p in sorted((root / 'Schemas').glob('*.json'))]
registry = Registry().with_resources((s['$id'], Resource.from_contents(s)) for s in schemas)
validators = {}
for schema in schemas:
    Draft202012Validator.check_schema(schema)
    validators[schema['$id'].split(':')[-1]] = Draft202012Validator(schema, registry=registry)
count = 0
checked = {}
skipped = {}
if a.store:
    database = sqlite3.connect('file:' + str(a.store.resolve()) + '?mode=ro', uri=True)
    for namespace, payload in database.execute("SELECT namespace,payload FROM records"):
        kind = {'input':'input-reference','schedulingPlan':'scheduling-plan'}.get(namespace, namespace)
        if kind in validators:
            try:
                validators[kind].validate(json.loads(payload))
            except ValidationError as error:
                raise SystemExit(json.dumps({'namespace': namespace, 'fieldPath': list(error.absolute_path), 'validator': error.validator, 'reason': 'Retained record violates the current shape contract; private payload omitted'}))
            count += 1
            checked[namespace] = checked.get(namespace, 0) + 1
        else:
            skipped[namespace] = skipped.get(namespace, 0) + 1
    database.close()
print(json.dumps({'schemaVersion': 2, 'schemaCount': len(schemas), 'validatedRecords': count, 'checkedNamespaces': checked, 'unclaimedNamespaces': skipped, 'scope': 'Shape validation only; behavioral invariants are owned by Swift validation and execution tests'}))
