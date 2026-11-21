# CInvarSQLite

## Purpose and Scope
Planned private SwiftPM system-library target exposing the macOS SDK SQLite C interface. Parent: [Invar](../../DESIGN.md). No binding source is implemented in this checkpoint.

## Responsibilities and Boundaries
Expose the system sqlite3 header/library without copied database implementations or callbacks exported from Swift. SQLite connection, statement, borrowed column-buffer and transaction lifetimes belong to VerificationStore. This target owns no mutable Swift state.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Invar](../../DESIGN.md) | parent | Native package composition | Private interop target | Unique module identity |
| [Store](../VerificationStore/DESIGN.md) | used by | SQLite C API | Durable ledger implementation | Pointer/statement/connection ownership must be reviewed there |

## Architecture
```text
VerificationStore actor -> CInvarSQLite module map -> system sqlite3
```

## Contracts and Invariants
Use the fixed macOS SDK's supported C declarations. Never reuse/import Explorer's private CSQLite target. Store validates lengths, status codes, transactions and exactly-once statement/connection release; borrowed column bytes cannot outlive their statement/step. The future module map links sqlite3 only and introduces no runtime installation.

## Verification and Change Impact
[Store/native linkage tests](../../Documentation/VERIFICATION-PLAN.md) must compile/link and execute actual SQLite commit/rollback and failure paths on the selected host; manifest structure alone does not verify C ownership or durability. SDK/interface changes recheck Store's unsafe boundary and transaction tests.
