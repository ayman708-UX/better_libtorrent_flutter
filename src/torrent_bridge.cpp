#include "torrent_bridge.h"

#include <libtorrent/session.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/bdecode.hpp>
#include <libtorrent/write_resume_data.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/torrent_flags.hpp>

#include <string>
#include <sstream>
#include <vector>
#include <thread>
#include <atomic>
#include <mutex>
#include <memory>
#include <chrono>
#include <cstdlib>
#include <cstring>

#ifdef _WIN32
  #include <windows.h>
#else
  #include <stdlib.h>
#endif

// ---------------------------------------------------------
// Helpers
// ---------------------------------------------------------

static char* alloc_string(const std::string& s) {
#ifdef _WIN32
    return _strdup(s.c_str());
#else
    return strdup(s.c_str());
#endif
}

void te_free_string(char* str) {
    if (str) free(str);
}

static std::string json_escape(const std::string& s) {
    std::ostringstream o;
    for (unsigned char c : s) {
        if (c == '"') o << "\\\"";
        else if (c == '\\') o << "\\\\";
        else if (c == '\b') o << "\\b";
        else if (c == '\f') o << "\\f";
        else if (c == '\n') o << "\\n";
        else if (c == '\r') o << "\\r";
        else if (c == '\t') o << "\\t";
        else if (c >= 32 && c <= 126) {
            o << c; // strictly allow only printable ASCII
        } else {
            o << "?"; // replace invalid/non-ascii with '?'
        }
    }
    return o.str();
}

static std::string to_hex(const libtorrent::sha1_hash& h) {
    std::ostringstream o;
    o << h;
    return o.str();
}

static std::string to_hex(const libtorrent::sha256_hash& h) {
    std::ostringstream o;
    o << h;
    return o.str();
}

// Base64 encoding for resume data and piece data
static const char b64_table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static std::string base64_encode(const char* data, size_t len) {
    std::string result;
    result.reserve(((len + 2) / 3) * 4);
    for (size_t i = 0; i < len; i += 3) {
        unsigned int n = ((unsigned char)data[i]) << 16;
        if (i + 1 < len) n |= ((unsigned char)data[i + 1]) << 8;
        if (i + 2 < len) n |= ((unsigned char)data[i + 2]);
        result += b64_table[(n >> 18) & 0x3F];
        result += b64_table[(n >> 12) & 0x3F];
        result += (i + 1 < len) ? b64_table[(n >> 6) & 0x3F] : '=';
        result += (i + 2 < len) ? b64_table[n & 0x3F] : '=';
    }
    return result;
}

// Global CA bundle path
static std::string g_ca_bundle_path = "";

void te_set_ca_bundle_path(const char* pem_path) {
    if (pem_path) {
        g_ca_bundle_path = pem_path;
#ifdef _WIN32
        _putenv_s("SSL_CERT_FILE", pem_path);
#else
        setenv("SSL_CERT_FILE", pem_path, 1);
#endif
    }
}

// ---------------------------------------------------------
// Session Wrapper
// ---------------------------------------------------------
struct te_session_t {
    std::unique_ptr<libtorrent::session> session;
    
    std::thread alert_thread;
    std::atomic<bool> alert_running{false};
    
    std::mutex cb_mu;
    te_alert_callback dart_callback = nullptr;
    void* dart_user_data = nullptr;

    te_session_t() {}
    ~te_session_t() {
        if (alert_running) {
            alert_running = false;
            if (alert_thread.joinable()) {
                alert_thread.join();
            }
        }
    }
};

struct te_torrent_handle_t {
    libtorrent::torrent_handle handle;
};

// ---------------------------------------------------------
// Alert Serialization
// ---------------------------------------------------------
static std::string serialize_alert(libtorrent::alert* a) {
    try {
        std::ostringstream json;
        json << "{";
        json << "\"type\":" << a->type() << ",";
        json << "\"what\":\"" << json_escape(a->what()) << "\",";
        json << "\"message\":\"" << json_escape(a->message()) << "\"";
        
        // Torrent alert base → extract torrent_id
        if (auto* ta = libtorrent::alert_cast<libtorrent::torrent_alert>(a)) {
            json << ",\"torrent_id\":" << ta->handle.id();
        }

        // state_update_alert → bulk status updates
        if (auto* su = libtorrent::alert_cast<libtorrent::state_update_alert>(a)) {
            json << ",\"status\":[";
            bool first = true;
            for (auto& st : su->status) {
                if (!first) json << ",";
                json << "{";
                json << "\"id\":" << st.handle.id() << ",";
                json << "\"state\":" << static_cast<int>(st.state) << ",";
                json << "\"progress\":" << st.progress << ",";
                json << "\"download_rate\":" << st.download_rate << ",";
                json << "\"upload_rate\":" << st.upload_rate << ",";
                json << "\"download_payload_rate\":" << st.download_payload_rate << ",";
                json << "\"upload_payload_rate\":" << st.upload_payload_rate << ",";
                json << "\"total_done\":" << st.total_done << ",";
                json << "\"total_wanted\":" << st.total_wanted << ",";
                json << "\"total_wanted_done\":" << st.total_wanted_done << ",";
                json << "\"total\":" << st.total << ",";
                json << "\"num_peers\":" << st.num_peers << ",";
                json << "\"num_seeds\":" << st.num_seeds << ",";
                json << "\"num_pieces\":" << st.num_pieces << ",";
                json << "\"num_connections\":" << st.num_connections << ",";
                json << "\"list_seeds\":" << st.list_seeds << ",";
                json << "\"list_peers\":" << st.list_peers << ",";
                json << "\"has_metadata\":" << (st.has_metadata ? "true" : "false") << ",";
                json << "\"is_seeding\":" << (st.is_seeding ? "true" : "false") << ",";
                json << "\"is_finished\":" << (st.is_finished ? "true" : "false") << ",";
                json << "\"name\":\"" << json_escape(st.name) << "\",";
                json << "\"save_path\":\"" << json_escape(st.save_path) << "\",";
                json << "\"current_tracker\":\"" << json_escape(st.current_tracker) << "\",";
                json << "\"all_time_download\":" << st.all_time_download << ",";
                json << "\"all_time_upload\":" << st.all_time_upload << ",";
                json << "\"added_time\":" << st.added_time << ",";
                json << "\"completed_time\":" << st.completed_time;
                json << "}";
                first = false;
            }
            json << "]";
        }

        // save_resume_data_alert → serialize resume data as base64
        if (auto* rd = libtorrent::alert_cast<libtorrent::save_resume_data_alert>(a)) {
            std::vector<char> buf = libtorrent::write_resume_data_buf(rd->params);
            json << ",\"resume_data\":\"" << base64_encode(buf.data(), buf.size()) << "\"";
        }

        // save_resume_data_failed_alert
        if (auto* rf = libtorrent::alert_cast<libtorrent::save_resume_data_failed_alert>(a)) {
            json << ",\"error\":\"" << json_escape(rf->error.message()) << "\"";
        }

        // read_piece_alert → piece data as base64
        if (auto* rp = libtorrent::alert_cast<libtorrent::read_piece_alert>(a)) {
            json << ",\"piece\":" << static_cast<int>(rp->piece);
            json << ",\"size\":" << rp->size;
            if (rp->buffer && rp->size > 0) {
                json << ",\"data\":\"" << base64_encode(rp->buffer.get(), rp->size) << "\"";
            }
            if (rp->error) {
                json << ",\"error\":\"" << json_escape(rp->error.message()) << "\"";
            }
        }

        // metadata_received_alert
        if (libtorrent::alert_cast<libtorrent::metadata_received_alert>(a)) {
            json << ",\"metadata_received\":true";
        }

        // torrent_finished_alert
        if (libtorrent::alert_cast<libtorrent::torrent_finished_alert>(a)) {
            json << ",\"finished\":true";
        }

        // file_completed_alert
        if (auto* fc = libtorrent::alert_cast<libtorrent::file_completed_alert>(a)) {
            json << ",\"file_index\":" << static_cast<int>(fc->index);
        }

        // piece_finished_alert
        if (auto* pf = libtorrent::alert_cast<libtorrent::piece_finished_alert>(a)) {
            json << ",\"piece\":" << static_cast<int>(pf->piece_index);
        }

        // torrent_error_alert
        if (auto* te = libtorrent::alert_cast<libtorrent::torrent_error_alert>(a)) {
            json << ",\"error\":\"" << json_escape(te->error.message()) << "\"";
        }

        // add_torrent_alert
        if (auto* at = libtorrent::alert_cast<libtorrent::add_torrent_alert>(a)) {
            if (at->error) {
                json << ",\"error\":\"" << json_escape(at->error.message()) << "\"";
            }
        }

        // tracker_reply_alert
        if (auto* tr = libtorrent::alert_cast<libtorrent::tracker_reply_alert>(a)) {
            json << ",\"num_peers\":" << tr->num_peers;
        }

        // tracker_error_alert
        if (auto* ter = libtorrent::alert_cast<libtorrent::tracker_error_alert>(a)) {
            json << ",\"error\":\"" << json_escape(ter->error.message()) << "\"";
            json << ",\"status_code\":" << ter->status_code;
        }

        json << "}";
        return json.str();
    } catch (...) {
        return "{}";
    }
}

// ---------------------------------------------------------
// Alert Pump Thread
// ---------------------------------------------------------
static void alert_pump_loop(te_session_t* s) {
    auto last_status_request = std::chrono::steady_clock::now();

    while (s->alert_running.load()) {
        // Request status updates at a sane interval (every 500ms)
        auto now = std::chrono::steady_clock::now();
        if (now - last_status_request >= std::chrono::milliseconds(500)) {
            try {
                s->session->post_torrent_updates(libtorrent::status_flags_t::all());
            } catch (...) {}
            last_status_request = now;
        }

        try {
            if (!s->session->wait_for_alert(libtorrent::milliseconds(100))) {
                continue;
            }
        } catch (...) {
            continue;
        }

        std::vector<libtorrent::alert*> alerts;
        s->session->pop_alerts(&alerts);

        for (auto* a : alerts) {
            if (!a) continue;
            
            std::string payload = serialize_alert(a);
            char* payload_ptr = alloc_string(payload);

            std::lock_guard<std::mutex> lk(s->cb_mu);
            if (s->dart_callback) {
                s->dart_callback(a->type(), payload_ptr, s->dart_user_data);
            } else {
                free(payload_ptr);
            }
        }
    }
}

// ---------------------------------------------------------
// Session API
// ---------------------------------------------------------
te_session_t* te_session_create(const char* config_json) {
    libtorrent::settings_pack sp;
    sp.set_int(libtorrent::settings_pack::alert_mask, 
        libtorrent::alert_category::status | 
        libtorrent::alert_category::error |
        libtorrent::alert_category::storage |
        libtorrent::alert_category::performance_warning |
        libtorrent::alert_category::piece_progress |
        libtorrent::alert_category::file_progress |
        libtorrent::alert_category::tracker);
    
    sp.set_str(libtorrent::settings_pack::listen_interfaces, "0.0.0.0:6881,[::]:6881");
    
    // Parse config_json if provided
    if (config_json) {
        std::string conf(config_json);
        // listen_interfaces
        auto pos = conf.find("\"listen_interfaces\"");
        if (pos != std::string::npos) {
            auto colon = conf.find(":", pos);
            auto quote1 = conf.find("\"", colon);
            auto quote2 = conf.find("\"", quote1 + 1);
            if (quote1 != std::string::npos && quote2 != std::string::npos) {
                sp.set_str(libtorrent::settings_pack::listen_interfaces, conf.substr(quote1 + 1, quote2 - quote1 - 1));
            }
        }
    }

    auto* s = new te_session_t();
    try {
        s->session = std::make_unique<libtorrent::session>(std::move(sp));
        s->alert_running = true;
        s->alert_thread = std::thread(alert_pump_loop, s);
    } catch (std::exception& e) {
        delete s;
        return nullptr;
    }
    return s;
}

void te_session_destroy(te_session_t* s) {
    if (s) {
        delete s;
    }
}

void te_session_set_alert_callback(te_session_t* s, te_alert_callback cb, void* user_data) {
    if (s) {
        std::lock_guard<std::mutex> lk(s->cb_mu);
        s->dart_callback = cb;
        s->dart_user_data = user_data;
    }
}

void te_session_pause(te_session_t* s) {
    if (s && s->session) s->session->pause();
}

void te_session_resume(te_session_t* s) {
    if (s && s->session) s->session->resume();
}

// ---------------------------------------------------------
// Session Settings
// ---------------------------------------------------------

// A simple JSON value extractor (no dependency on a JSON library)
static bool json_find_int(const std::string& json, const std::string& key, int& out) {
    std::string needle = "\"" + key + "\"";
    auto pos = json.find(needle);
    if (pos == std::string::npos) return false;
    auto colon = json.find(":", pos + needle.size());
    if (colon == std::string::npos) return false;
    // skip whitespace
    auto start = json.find_first_of("-0123456789", colon + 1);
    if (start == std::string::npos) return false;
    out = std::atoi(json.c_str() + start);
    return true;
}

static bool json_find_bool(const std::string& json, const std::string& key, bool& out) {
    std::string needle = "\"" + key + "\"";
    auto pos = json.find(needle);
    if (pos == std::string::npos) return false;
    auto colon = json.find(":", pos + needle.size());
    if (colon == std::string::npos) return false;
    auto val_start = json.find_first_not_of(" \t\n\r", colon + 1);
    if (val_start == std::string::npos) return false;
    out = (json.compare(val_start, 4, "true") == 0);
    return true;
}

static bool json_find_string(const std::string& json, const std::string& key, std::string& out) {
    std::string needle = "\"" + key + "\"";
    auto pos = json.find(needle);
    if (pos == std::string::npos) return false;
    auto colon = json.find(":", pos + needle.size());
    if (colon == std::string::npos) return false;
    auto quote1 = json.find("\"", colon + 1);
    if (quote1 == std::string::npos) return false;
    auto quote2 = json.find("\"", quote1 + 1);
    if (quote2 == std::string::npos) return false;
    out = json.substr(quote1 + 1, quote2 - quote1 - 1);
    return true;
}

void te_session_apply_settings(te_session_t* s, const char* settings_json) {
    if (!s || !s->session || !settings_json) return;
    
    std::string json(settings_json);
    libtorrent::settings_pack sp;
    
    int ival;
    bool bval;
    std::string sval;
    
    if (json_find_int(json, "download_rate_limit", ival))
        sp.set_int(libtorrent::settings_pack::download_rate_limit, ival);
    if (json_find_int(json, "upload_rate_limit", ival))
        sp.set_int(libtorrent::settings_pack::upload_rate_limit, ival);
    if (json_find_int(json, "connections_limit", ival))
        sp.set_int(libtorrent::settings_pack::connections_limit, ival);
    if (json_find_int(json, "active_downloads", ival))
        sp.set_int(libtorrent::settings_pack::active_downloads, ival);
    if (json_find_int(json, "active_seeds", ival))
        sp.set_int(libtorrent::settings_pack::active_seeds, ival);
    if (json_find_int(json, "active_limit", ival))
        sp.set_int(libtorrent::settings_pack::active_limit, ival);
    
    if (json_find_bool(json, "enable_dht", bval))
        sp.set_bool(libtorrent::settings_pack::enable_dht, bval);
    if (json_find_bool(json, "anonymous_mode", bval))
        sp.set_bool(libtorrent::settings_pack::anonymous_mode, bval);
    
    if (json_find_string(json, "listen_interfaces", sval))
        sp.set_str(libtorrent::settings_pack::listen_interfaces, sval);
    if (json_find_string(json, "user_agent", sval))
        sp.set_str(libtorrent::settings_pack::user_agent, sval);
    if (json_find_string(json, "proxy_hostname", sval))
        sp.set_str(libtorrent::settings_pack::proxy_hostname, sval);
    if (json_find_string(json, "proxy_username", sval))
        sp.set_str(libtorrent::settings_pack::proxy_username, sval);
    if (json_find_string(json, "proxy_password", sval))
        sp.set_str(libtorrent::settings_pack::proxy_password, sval);
    
    if (json_find_int(json, "proxy_port", ival))
        sp.set_int(libtorrent::settings_pack::proxy_port, ival);
    if (json_find_int(json, "proxy_type", ival))
        sp.set_int(libtorrent::settings_pack::proxy_type, ival);
    
    if (json_find_int(json, "in_enc_policy", ival))
        sp.set_int(libtorrent::settings_pack::in_enc_policy, ival);
    if (json_find_int(json, "out_enc_policy", ival))
        sp.set_int(libtorrent::settings_pack::out_enc_policy, ival);
    if (json_find_int(json, "allowed_enc_level", ival))
        sp.set_int(libtorrent::settings_pack::allowed_enc_level, ival);

    s->session->apply_settings(std::move(sp));
}

char* te_session_get_settings(te_session_t* s) {
    if (!s || !s->session) return alloc_string("{}");
    
    libtorrent::settings_pack sp = s->session->get_settings();
    
    std::ostringstream json;
    json << "{";
    json << "\"download_rate_limit\":" << sp.get_int(libtorrent::settings_pack::download_rate_limit) << ",";
    json << "\"upload_rate_limit\":" << sp.get_int(libtorrent::settings_pack::upload_rate_limit) << ",";
    json << "\"connections_limit\":" << sp.get_int(libtorrent::settings_pack::connections_limit) << ",";
    json << "\"active_downloads\":" << sp.get_int(libtorrent::settings_pack::active_downloads) << ",";
    json << "\"active_seeds\":" << sp.get_int(libtorrent::settings_pack::active_seeds) << ",";
    json << "\"active_limit\":" << sp.get_int(libtorrent::settings_pack::active_limit) << ",";
    json << "\"enable_dht\":" << (sp.get_bool(libtorrent::settings_pack::enable_dht) ? "true" : "false") << ",";
    json << "\"anonymous_mode\":" << (sp.get_bool(libtorrent::settings_pack::anonymous_mode) ? "true" : "false") << ",";
    json << "\"listen_interfaces\":\"" << json_escape(sp.get_str(libtorrent::settings_pack::listen_interfaces)) << "\",";
    json << "\"user_agent\":\"" << json_escape(sp.get_str(libtorrent::settings_pack::user_agent)) << "\",";
    json << "\"proxy_hostname\":\"" << json_escape(sp.get_str(libtorrent::settings_pack::proxy_hostname)) << "\",";
    json << "\"proxy_port\":" << sp.get_int(libtorrent::settings_pack::proxy_port) << ",";
    json << "\"proxy_type\":" << sp.get_int(libtorrent::settings_pack::proxy_type) << ",";
    json << "\"in_enc_policy\":" << sp.get_int(libtorrent::settings_pack::in_enc_policy) << ",";
    json << "\"out_enc_policy\":" << sp.get_int(libtorrent::settings_pack::out_enc_policy) << ",";
    json << "\"allowed_enc_level\":" << sp.get_int(libtorrent::settings_pack::allowed_enc_level);
    json << "}";
    
    return alloc_string(json.str());
}

bool te_session_is_dht_running(te_session_t* s) {
    if (!s || !s->session) return false;
    return s->session->is_dht_running();
}

void te_session_post_torrent_updates(te_session_t* s) {
    if (s && s->session) {
        try {
            s->session->post_torrent_updates(libtorrent::status_flags_t::all());
        } catch (...) {}
    }
}

void te_session_post_session_stats(te_session_t* s) {
    if (s && s->session) {
        try {
            s->session->post_session_stats();
        } catch (...) {}
    }
}

// ---------------------------------------------------------
// Torrent Management
// ---------------------------------------------------------
te_torrent_handle_t* te_add_magnet(te_session_t* s, const char* magnet_uri, const char* save_path) {
    if (!s || !s->session || !magnet_uri || !save_path) return nullptr;

    libtorrent::error_code ec;
    libtorrent::add_torrent_params p = libtorrent::parse_magnet_uri(magnet_uri, ec);
    if (ec) return nullptr;

    p.save_path = save_path;

    try {
        libtorrent::torrent_handle h = s->session->add_torrent(std::move(p), ec);
        if (ec) return nullptr;
        
        auto* handle = new te_torrent_handle_t();
        handle->handle = std::move(h);
        return handle;
    } catch (...) {
        return nullptr;
    }
}

te_torrent_handle_t* te_add_torrent_file(te_session_t* s, const uint8_t* data, size_t len, const char* save_path) {
    if (!s || !s->session || !data || len == 0 || !save_path) return nullptr;
    
    try {
        libtorrent::error_code ec;
        libtorrent::bdecode_node node;
        libtorrent::bdecode(reinterpret_cast<const char*>(data), 
                            reinterpret_cast<const char*>(data) + len, node, ec);
        if (ec) return nullptr;

        auto ti = std::make_shared<libtorrent::torrent_info>(node, ec);
        if (ec) return nullptr;

        libtorrent::add_torrent_params p;
        p.ti = ti;
        p.save_path = save_path;

        libtorrent::torrent_handle h = s->session->add_torrent(std::move(p), ec);
        if (ec) return nullptr;
        
        auto* handle = new te_torrent_handle_t();
        handle->handle = std::move(h);
        return handle;
    } catch (...) {
        return nullptr;
    }
}

te_torrent_handle_t* te_add_torrent_with_resume(te_session_t* s, const uint8_t* resume_data, size_t len, const char* save_path) {
    if (!s || !s->session || !resume_data || len == 0) return nullptr;
    
    try {
        libtorrent::error_code ec;
        libtorrent::add_torrent_params p = libtorrent::read_resume_data(
            libtorrent::span<const char>(reinterpret_cast<const char*>(resume_data), len), ec);
        if (ec) return nullptr;

        if (save_path) p.save_path = save_path;

        libtorrent::torrent_handle h = s->session->add_torrent(std::move(p), ec);
        if (ec) return nullptr;
        
        auto* handle = new te_torrent_handle_t();
        handle->handle = std::move(h);
        return handle;
    } catch (...) {
        return nullptr;
    }
}

void te_torrent_pause(te_torrent_handle_t* h) {
    if (h && h->handle.is_valid()) h->handle.pause();
}

void te_torrent_resume(te_torrent_handle_t* h) {
    if (h && h->handle.is_valid()) h->handle.resume();
}

void te_torrent_remove(te_session_t* s, te_torrent_handle_t* h, bool delete_files) {
    if (s && s->session && h && h->handle.is_valid()) {
        auto flags = delete_files ? libtorrent::session::delete_files : libtorrent::remove_flags_t{};
        s->session->remove_torrent(h->handle, flags);
        delete h;
    }
}

// ---------------------------------------------------------
// Torrent Info & Status
// ---------------------------------------------------------
char* te_torrent_get_status(te_torrent_handle_t* h) {
    if (!h || !h->handle.is_valid()) return alloc_string("{}");
    
    try {
        auto st = h->handle.status(
            libtorrent::torrent_handle::query_name |
            libtorrent::torrent_handle::query_save_path);
        
        std::ostringstream json;
        json << "{";
        json << "\"id\":" << h->handle.id() << ",";
        json << "\"state\":" << static_cast<int>(st.state) << ",";
        json << "\"progress\":" << st.progress << ",";
        json << "\"download_rate\":" << st.download_rate << ",";
        json << "\"upload_rate\":" << st.upload_rate << ",";
        json << "\"download_payload_rate\":" << st.download_payload_rate << ",";
        json << "\"upload_payload_rate\":" << st.upload_payload_rate << ",";
        json << "\"total_done\":" << st.total_done << ",";
        json << "\"total_wanted\":" << st.total_wanted << ",";
        json << "\"total_wanted_done\":" << st.total_wanted_done << ",";
        json << "\"total\":" << st.total << ",";
        json << "\"num_peers\":" << st.num_peers << ",";
        json << "\"num_seeds\":" << st.num_seeds << ",";
        json << "\"num_pieces\":" << st.num_pieces << ",";
        json << "\"num_connections\":" << st.num_connections << ",";
        json << "\"list_seeds\":" << st.list_seeds << ",";
        json << "\"list_peers\":" << st.list_peers << ",";
        json << "\"has_metadata\":" << (st.has_metadata ? "true" : "false") << ",";
        json << "\"is_seeding\":" << (st.is_seeding ? "true" : "false") << ",";
        json << "\"is_finished\":" << (st.is_finished ? "true" : "false") << ",";
        json << "\"name\":\"" << json_escape(st.name) << "\",";
        json << "\"save_path\":\"" << json_escape(st.save_path) << "\",";
        json << "\"current_tracker\":\"" << json_escape(st.current_tracker) << "\",";
        json << "\"all_time_download\":" << st.all_time_download << ",";
        json << "\"all_time_upload\":" << st.all_time_upload << ",";
        json << "\"added_time\":" << st.added_time << ",";
        json << "\"completed_time\":" << st.completed_time;
        json << "}";
        return alloc_string(json.str());
    } catch (...) {
        return alloc_string("{}");
    }
}

char* te_torrent_get_name(te_torrent_handle_t* h) {
    if (!h || !h->handle.is_valid()) return alloc_string("");
    auto st = h->handle.status(libtorrent::torrent_handle::query_name);
    return alloc_string(st.name);
}

char* te_torrent_get_info_hash(te_torrent_handle_t* h) {
    if (!h || !h->handle.is_valid()) return alloc_string("{}");
    
    auto ih = h->handle.info_hashes();
    std::ostringstream json;
    json << "{";
    if (ih.has_v1()) {
        json << "\"v1\":\"" << to_hex(ih.v1) << "\"";
    }
    if (ih.has_v1() && ih.has_v2()) json << ",";
    if (ih.has_v2()) {
        json << "\"v2\":\"" << to_hex(ih.v2) << "\"";
    }
    json << "}";
    
    return alloc_string(json.str());
}

int te_torrent_get_file_count(te_torrent_handle_t* h) {
    if (!h || !h->handle.is_valid()) return 0;
    auto ti = h->handle.torrent_file();
    if (!ti) return 0;
    return ti->files().num_files();
}

char* te_torrent_get_files(te_torrent_handle_t* h) {
    if (!h || !h->handle.is_valid()) return alloc_string("[]");
    auto ti = h->handle.torrent_file();
    if (!ti) return alloc_string("[]");
    
    const auto& fs = ti->files();
    std::ostringstream json;
    json << "[";
    for (int i = 0; i < fs.num_files(); ++i) {
        auto idx = libtorrent::file_index_t(i);
        if (i > 0) json << ",";
        json << "{";
        json << "\"index\":" << i << ",";
        json << "\"name\":\"" << json_escape(std::string(fs.file_name(idx))) << "\",";
        json << "\"path\":\"" << json_escape(fs.file_path(idx)) << "\",";
        json << "\"size\":" << fs.file_size(idx);
        json << "}";
    }
    json << "]";
    
    return alloc_string(json.str());
}

char* te_torrent_get_piece_info(te_torrent_handle_t* h) {
    if (!h || !h->handle.is_valid()) return alloc_string("{}");
    auto ti = h->handle.torrent_file();
    if (!ti) return alloc_string("{}");
    
    std::ostringstream json;
    json << "{";
    json << "\"num_pieces\":" << ti->num_pieces() << ",";
    json << "\"piece_length\":" << ti->piece_length() << ",";
    json << "\"total_size\":" << ti->total_size();
    json << "}";
    
    return alloc_string(json.str());
}

// ---------------------------------------------------------
// Streaming & Piece Control
// ---------------------------------------------------------
void te_torrent_set_sequential_download(te_torrent_handle_t* h, bool enabled) {
    if (h && h->handle.is_valid()) {
        if (enabled) {
            h->handle.set_flags(libtorrent::torrent_flags::sequential_download);
        } else {
            h->handle.unset_flags(libtorrent::torrent_flags::sequential_download);
        }
    }
}

bool te_torrent_have_piece(te_torrent_handle_t* h, int piece_index) {
    if (!h || !h->handle.is_valid()) return false;
    return h->handle.have_piece(libtorrent::piece_index_t(piece_index));
}

void te_torrent_read_piece(te_torrent_handle_t* h, int piece_index) {
    if (h && h->handle.is_valid()) {
        h->handle.read_piece(libtorrent::piece_index_t(piece_index));
    }
}

void te_torrent_set_piece_deadline(te_torrent_handle_t* h, int piece_index, int deadline, int flags) {
    if (h && h->handle.is_valid()) {
        h->handle.set_piece_deadline(libtorrent::piece_index_t(piece_index), deadline, 
                                     static_cast<libtorrent::deadline_flags_t>(flags));
    }
}

void te_torrent_reset_piece_deadline(te_torrent_handle_t* h, int piece_index) {
    if (h && h->handle.is_valid()) {
        h->handle.reset_piece_deadline(libtorrent::piece_index_t(piece_index));
    }
}

void te_torrent_clear_piece_deadlines(te_torrent_handle_t* h) {
    if (h && h->handle.is_valid()) {
        h->handle.clear_piece_deadlines();
    }
}

// ---------------------------------------------------------
// File Prioritization
// ---------------------------------------------------------
void te_torrent_set_file_priority(te_torrent_handle_t* h, int file_index, int priority) {
    if (h && h->handle.is_valid()) {
        h->handle.file_priority(libtorrent::file_index_t(file_index), 
                                libtorrent::download_priority_t(static_cast<uint8_t>(priority)));
    }
}

char* te_torrent_get_file_priorities(te_torrent_handle_t* h) {
    if (!h || !h->handle.is_valid()) return alloc_string("[]");
    
    auto prios = h->handle.get_file_priorities();
    std::ostringstream json;
    json << "[";
    for (size_t i = 0; i < prios.size(); ++i) {
        if (i > 0) json << ",";
        json << static_cast<int>(prios[i]);
    }
    json << "]";
    
    return alloc_string(json.str());
}

void te_torrent_set_all_file_priorities(te_torrent_handle_t* h, const int* priorities, int count) {
    if (!h || !h->handle.is_valid() || !priorities || count <= 0) return;
    
    std::vector<libtorrent::download_priority_t> prios;
    prios.reserve(count);
    for (int i = 0; i < count; ++i) {
        prios.push_back(libtorrent::download_priority_t(static_cast<uint8_t>(priorities[i])));
    }
    h->handle.prioritize_files(prios);
}

// ---------------------------------------------------------
// Per-Torrent Limits
// ---------------------------------------------------------
void te_torrent_set_upload_limit(te_torrent_handle_t* h, int limit) {
    if (h && h->handle.is_valid()) h->handle.set_upload_limit(limit);
}

void te_torrent_set_download_limit(te_torrent_handle_t* h, int limit) {
    if (h && h->handle.is_valid()) h->handle.set_download_limit(limit);
}

int te_torrent_get_upload_limit(te_torrent_handle_t* h) {
    if (!h || !h->handle.is_valid()) return 0;
    return h->handle.upload_limit();
}

int te_torrent_get_download_limit(te_torrent_handle_t* h) {
    if (!h || !h->handle.is_valid()) return 0;
    return h->handle.download_limit();
}

void te_torrent_set_max_connections(te_torrent_handle_t* h, int max_connections) {
    if (h && h->handle.is_valid()) h->handle.set_max_connections(max_connections);
}

void te_torrent_set_max_uploads(te_torrent_handle_t* h, int max_uploads) {
    if (h && h->handle.is_valid()) h->handle.set_max_uploads(max_uploads);
}

// ---------------------------------------------------------
// Torrent Control
// ---------------------------------------------------------
void te_torrent_force_reannounce(te_torrent_handle_t* h) {
    if (h && h->handle.is_valid()) h->handle.force_reannounce();
}

void te_torrent_force_recheck(te_torrent_handle_t* h) {
    if (h && h->handle.is_valid()) h->handle.force_recheck();
}

void te_torrent_save_resume_data(te_torrent_handle_t* h) {
    if (h && h->handle.is_valid()) h->handle.save_resume_data();
}

void te_torrent_move_storage(te_torrent_handle_t* h, const char* new_path) {
    if (h && h->handle.is_valid() && new_path) {
        h->handle.move_storage(new_path);
    }
}

void te_torrent_set_flags(te_torrent_handle_t* h, uint64_t flags, uint64_t mask) {
    if (h && h->handle.is_valid()) {
        h->handle.set_flags(
            libtorrent::torrent_flags_t(flags),
            libtorrent::torrent_flags_t(mask));
    }
}

uint64_t te_torrent_get_flags(te_torrent_handle_t* h) {
    if (!h || !h->handle.is_valid()) return 0;
    return static_cast<uint64_t>(h->handle.flags());
}

void te_torrent_flush_cache(te_torrent_handle_t* h) {
    if (h && h->handle.is_valid()) h->handle.flush_cache();
}
