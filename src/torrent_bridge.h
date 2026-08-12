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
 */
typedef void (*te_alert_callback)(int32_t alert_type, const char* json_payload, void* user_data);

/* 
 * Certificate configuration
 * Must be called before te_session_create on iOS/Android to set the CA bundle path
 */
TORRENT_API void te_set_ca_bundle_path(const char* pem_path);

/* Session Management */
TORRENT_API te_session_t* te_session_create(const char* config_json);
TORRENT_API void te_session_destroy(te_session_t* s);
TORRENT_API void te_session_set_alert_callback(te_session_t* s, te_alert_callback cb, void* user_data);
TORRENT_API void te_session_pause(te_session_t* s);
TORRENT_API void te_session_resume(te_session_t* s);

/* Torrent Management */
TORRENT_API te_torrent_handle_t* te_add_magnet(te_session_t* s, const char* magnet_uri, const char* save_path);
TORRENT_API te_torrent_handle_t* te_add_torrent_file(te_session_t* s, const uint8_t* data, size_t len, const char* save_path);
TORRENT_API void te_torrent_pause(te_torrent_handle_t* h);
TORRENT_API void te_torrent_resume(te_torrent_handle_t* h);
TORRENT_API void te_torrent_remove(te_session_t* s, te_torrent_handle_t* h, bool delete_files);

/* Streaming and Prioritization Support */
TORRENT_API void te_torrent_set_sequential_download(te_torrent_handle_t* h, bool enabled);
TORRENT_API void te_torrent_set_file_priority(te_torrent_handle_t* h, int file_index, int priority);
TORRENT_API void te_torrent_set_piece_deadline(te_torrent_handle_t* h, int piece_index, int deadline, int flags);

// Helper
TORRENT_API void te_free_string(char* str);

#ifdef __cplusplus
}
#endif
