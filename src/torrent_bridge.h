#pragma once

#ifdef _WIN32
  #ifdef TORRENT_BRIDGE_EXPORTS
    #define TORRENT_API __declspec(dllexport)
  #else
    #define TORRENT_API __declspec(dllimport)
  #endif
#else
  #define TORRENT_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

typedef struct te_session_t te_session_t;
typedef struct te_torrent_handle_t te_torrent_handle_t;

/* Torrent states aligned with libtorrent */
#define TE_STATE_CHECKING_FILES 1
#define TE_STATE_DOWNLOADING_META 2
#define TE_STATE_DOWNLOADING 3
#define TE_STATE_FINISHED 4
#define TE_STATE_SEEDING 5
#define TE_STATE_ALLOCATING 6
#define TE_STATE_CHECKING_RESUME_DATA 7

/* 
 * Alert Callback Type
 * Alert payload is serialized as JSON for easy Dart parsing.
 * The char* payload is heap-allocated; caller must free via te_free_string().
 */
typedef void (*te_alert_callback)(int32_t alert_type, const char* json_payload, void* user_data);

/* =========================================================
 * Utility
 * ========================================================= */
TORRENT_API void te_free_string(char* str);

/* =========================================================
 * Certificate configuration
 * Must be called before te_session_create on iOS/Android
 * ========================================================= */
TORRENT_API void te_set_ca_bundle_path(const char* pem_path);

/* =========================================================
 * Session Management
 * ========================================================= */
TORRENT_API te_session_t* te_session_create(const char* config_json);
TORRENT_API void te_session_destroy(te_session_t* s);
TORRENT_API void te_session_set_alert_callback(te_session_t* s, te_alert_callback cb, void* user_data);
TORRENT_API void te_session_pause(te_session_t* s);
TORRENT_API void te_session_resume(te_session_t* s);

/* Session Settings */
TORRENT_API void te_session_apply_settings(te_session_t* s, const char* settings_json);
TORRENT_API char* te_session_get_settings(te_session_t* s);
TORRENT_API bool te_session_is_dht_running(te_session_t* s);
TORRENT_API void te_session_post_torrent_updates(te_session_t* s);
TORRENT_API void te_session_post_session_stats(te_session_t* s);

/* =========================================================
 * Torrent Management
 * ========================================================= */
TORRENT_API te_torrent_handle_t* te_add_magnet(te_session_t* s, const char* magnet_uri, const char* save_path);
TORRENT_API te_torrent_handle_t* te_add_torrent_file(te_session_t* s, const uint8_t* data, size_t len, const char* save_path);
TORRENT_API te_torrent_handle_t* te_add_torrent_with_resume(te_session_t* s, const uint8_t* resume_data, size_t len, const char* save_path);
TORRENT_API void te_torrent_pause(te_torrent_handle_t* h);
TORRENT_API void te_torrent_resume(te_torrent_handle_t* h);
TORRENT_API void te_torrent_remove(te_session_t* s, te_torrent_handle_t* h, bool delete_files);

/* =========================================================
 * Torrent Info & Status
 * ========================================================= */
TORRENT_API char* te_torrent_get_status(te_torrent_handle_t* h);
TORRENT_API char* te_torrent_get_name(te_torrent_handle_t* h);
TORRENT_API char* te_torrent_get_info_hash(te_torrent_handle_t* h);
TORRENT_API int   te_torrent_get_file_count(te_torrent_handle_t* h);
TORRENT_API char* te_torrent_get_files(te_torrent_handle_t* h);
TORRENT_API char* te_torrent_get_piece_info(te_torrent_handle_t* h);

/* =========================================================
 * Streaming & Piece Control
 * ========================================================= */
TORRENT_API void te_torrent_set_sequential_download(te_torrent_handle_t* h, bool enabled);
TORRENT_API bool te_torrent_have_piece(te_torrent_handle_t* h, int piece_index);
TORRENT_API void te_torrent_read_piece(te_torrent_handle_t* h, int piece_index);
TORRENT_API void te_torrent_set_piece_deadline(te_torrent_handle_t* h, int piece_index, int deadline, int flags);
TORRENT_API void te_torrent_reset_piece_deadline(te_torrent_handle_t* h, int piece_index);
TORRENT_API void te_torrent_clear_piece_deadlines(te_torrent_handle_t* h);

/* =========================================================
 * File Prioritization
 * ========================================================= */
TORRENT_API void te_torrent_set_file_priority(te_torrent_handle_t* h, int file_index, int priority);
TORRENT_API char* te_torrent_get_file_priorities(te_torrent_handle_t* h);
TORRENT_API void te_torrent_set_all_file_priorities(te_torrent_handle_t* h, const int* priorities, int count);

/* =========================================================
 * Per-Torrent Limits
 * ========================================================= */
TORRENT_API void te_torrent_set_upload_limit(te_torrent_handle_t* h, int limit);
TORRENT_API void te_torrent_set_download_limit(te_torrent_handle_t* h, int limit);
TORRENT_API int  te_torrent_get_upload_limit(te_torrent_handle_t* h);
TORRENT_API int  te_torrent_get_download_limit(te_torrent_handle_t* h);
TORRENT_API void te_torrent_set_max_connections(te_torrent_handle_t* h, int max_connections);
TORRENT_API void te_torrent_set_max_uploads(te_torrent_handle_t* h, int max_uploads);

/* =========================================================
 * Torrent Control
 * ========================================================= */
TORRENT_API void te_torrent_force_reannounce(te_torrent_handle_t* h);
TORRENT_API void te_torrent_force_recheck(te_torrent_handle_t* h);
TORRENT_API void te_torrent_save_resume_data(te_torrent_handle_t* h);
TORRENT_API void te_torrent_move_storage(te_torrent_handle_t* h, const char* new_path);
TORRENT_API void te_torrent_set_flags(te_torrent_handle_t* h, uint64_t flags, uint64_t mask);
TORRENT_API uint64_t te_torrent_get_flags(te_torrent_handle_t* h);
TORRENT_API void te_torrent_flush_cache(te_torrent_handle_t* h);

/* =========================================================
 * Torrent Flags (matches libtorrent::torrent_flags)
 * ========================================================= */
#define TE_FLAG_SEED_MODE           0x001
#define TE_FLAG_UPLOAD_MODE         0x002
#define TE_FLAG_SHARE_MODE          0x004
#define TE_FLAG_APPLY_IP_FILTER     0x008
#define TE_FLAG_PAUSED              0x010
#define TE_FLAG_AUTO_MANAGED        0x020
#define TE_FLAG_SEQUENTIAL_DOWNLOAD 0x200
#define TE_FLAG_STOP_WHEN_READY     0x2000

#ifdef __cplusplus
}
#endif
