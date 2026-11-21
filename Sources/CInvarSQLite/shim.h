#include <sqlite3.h>
#include <stddef.h>

/* SQLite copies borrowed argument bytes before this call returns. */
static inline int invar_bind_bytes(sqlite3_stmt *statement, int index, const void *bytes, size_t count) {
  return sqlite3_bind_blob64(statement, index, bytes, (sqlite3_uint64)count, SQLITE_TRANSIENT);
}
static inline int invar_bind_string(sqlite3_stmt *statement, int index, const char *text) {
  return sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT);
}
