#include "server_internal.h"
#include "logger.h"

#include <sqlite3.h>
#include <string.h>

int init_db(const char *db_path) {
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(db_path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
        log_error("failed to open db: %s", sqlite3_errmsg(db));
        if (db) sqlite3_close(db);
        return -1;
    }

    const char *schema_sql =
        "PRAGMA journal_mode=WAL;"
        "PRAGMA synchronous=NORMAL;"
        "PRAGMA temp_store=MEMORY;"
        "PRAGMA mmap_size=268435456;"
        "CREATE TABLE IF NOT EXISTS kv_store ("
        "data_key TEXT PRIMARY KEY,"
        "data_value TEXT NOT NULL,"
        "updated_at INTEGER NOT NULL"
        ");";

    char *err = NULL;
    if (sqlite3_exec(db, schema_sql, NULL, NULL, &err) != SQLITE_OK) {
        log_error("failed to init schema: %s", err ? err : "unknown");
        sqlite3_free(err);
        sqlite3_close(db);
        return -1;
    }

    sqlite3_stmt *stmt = NULL;
    const char *upsert = "INSERT OR IGNORE INTO kv_store (data_key, data_value, updated_at) VALUES (?1, ?2, strftime('%s', 'now'));";
    if (sqlite3_prepare_v2(db, upsert, -1, &stmt, NULL) != SQLITE_OK) {
        log_error("failed to prepare init insert: %s", sqlite3_errmsg(db));
        sqlite3_close(db);
        return -1;
    }

    for (size_t i = 0; i < DATA_KEYS_COUNT; i++) {
        const char *default_json = strcmp(DATA_KEYS[i], "profile") == 0 ? "{}" : "[]";
        sqlite3_bind_text(stmt, 1, DATA_KEYS[i], -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 2, default_json, -1, SQLITE_STATIC);
        if (sqlite3_step(stmt) != SQLITE_DONE) {
            log_error("failed to seed key %s: %s", DATA_KEYS[i], sqlite3_errmsg(db));
            sqlite3_finalize(stmt);
            sqlite3_close(db);
            return -1;
        }
        sqlite3_reset(stmt);
        sqlite3_clear_bindings(stmt);
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return 0;
}

int worker_db_open(worker_db_t *db, const char *db_path) {
    memset(db, 0, sizeof(*db));
    if (sqlite3_open_v2(db_path, &db->db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
        log_error("worker failed to open db: %s", sqlite3_errmsg(db->db));
        if (db->db) sqlite3_close(db->db);
        return -1;
    }

    sqlite3_exec(db->db, "PRAGMA busy_timeout=5000;", NULL, NULL, NULL);
    sqlite3_exec(db->db, "PRAGMA synchronous=NORMAL;", NULL, NULL, NULL);
    sqlite3_exec(db->db, "PRAGMA temp_store=MEMORY;", NULL, NULL, NULL);
    sqlite3_exec(db->db, "PRAGMA mmap_size=268435456;", NULL, NULL, NULL);
    sqlite3_exec(db->db, "PRAGMA cache_size=-32768;", NULL, NULL, NULL);

    if (sqlite3_prepare_v2(db->db, "SELECT data_value FROM kv_store WHERE data_key=?1", -1, &db->get_stmt, NULL) != SQLITE_OK ||
        sqlite3_prepare_v2(db->db,
                           "INSERT INTO kv_store (data_key, data_value, updated_at) VALUES (?1, ?2, strftime('%s', 'now'))"
                           " ON CONFLICT(data_key) DO UPDATE SET data_value=excluded.data_value, updated_at=excluded.updated_at",
                           -1,
                           &db->upsert_stmt,
                           NULL) != SQLITE_OK ||
        sqlite3_prepare_v2(db->db, "SELECT json_valid(?1)", -1, &db->json_valid_stmt, NULL) != SQLITE_OK) {
        log_error("worker failed to prepare statements: %s", sqlite3_errmsg(db->db));
        worker_db_close(db);
        return -1;
    }

    return 0;
}

void worker_db_close(worker_db_t *db) {
    sqlite3_finalize(db->get_stmt);
    sqlite3_finalize(db->upsert_stmt);
    sqlite3_finalize(db->json_valid_stmt);
    if (db->db) sqlite3_close(db->db);
    memset(db, 0, sizeof(*db));
}
