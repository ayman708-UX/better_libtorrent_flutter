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

#include <string>
#include <sstream>
#include <vector>
#include <thread>
#include <atomic>
#include <mutex>
#include <memory>
#include <iostream>

#ifdef _WIN32
  #include <windows.h>
#else
  #include <stdlib.h>
#endif

// ---------------------------------------------------------
// Global CA bundle path (for iOS/Android)
// ---------------------------------------------------------
static std::string g_ca_bundle_path = "";

void te_set_ca_bundle_path(const char* pem_path) {
    if (pem_path) {
        g_ca_bundle_path = pem_path;
        // OpenSSL reads SSL_CERT_FILE if set.
#ifdef _WIN32
        _putenv_s("SSL_CERT_FILE", pem_path);
#else
        setenv("SSL_CERT_FILE", pem_path, 1);
#endif
    }
}

// ---------------------------------------------------------
// Helper to escape JSON strings manually
// ---------------------------------------------------------
static std::string json_escape(const std::string& s) {
    std::ostringstream o;
    for (char c : s) {
        if (c == '"') o << "\\\"";
        else if (c == '\\') o << "\\\\";
        else if (c == '\b') o << "\\b";
        else if (c == '\f') o << "\\f";
        else if (c == '\n') o << "\\n";
        else if (c == '\r') o << "\\r";
        else if (c == '\t') o << "\\t";
        else if (c >= 0 && c <= 0x1f) {
            // ignore control chars for simplicity in this minimal bridge
        } else {
            o << c;
        }
    }
    return o.str();
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
// Alert Pump Thread
// ---------------------------------------------------------
static void alert_pump_loop(te_session_t* s) {
    while (s->alert_running.load()) {
        // Request a state_update_alert to be posted
        s->session->post_torrent_updates();

        if (!s->session->wait_for_alert(libtorrent::milliseconds(200))) {
            continue;
        }

        std::vector<libtorrent::alert*> alerts;
        s->session->pop_alerts(&alerts);

        for (auto* a : alerts) {
            if (!a) continue;
            
            // Serialize basic info to JSON
            std::ostringstream json;
            json << "{";
            json << "\"type\":" << a->type() << ",";
            json << "\"what\":\"" << json_escape(a->what()) << "\",";
            json << "\"message\":\"" << json_escape(a->message()) << "\"";
            
            // If it's a torrent alert, extract the torrent ID
            if (auto* ta = libtorrent::alert_cast<libtorrent::torrent_alert>(a)) {
                json << ",\"torrent_id\":" << ta->handle.id();
            }

            // If it's a state update alert, serialize status
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
                    json << "\"total_done\":" << st.total_done << ",";
                    json << "\"total_wanted\":" << st.total_wanted << ",";
                    json << "\"num_peers\":" << st.num_peers << ",";
                    json << "\"num_seeds\":" << st.num_seeds;
                    json << "}";
                    first = false;
                }
                json << "]";
            }
            
            json << "}";
            std::string payload = json.str();

#ifdef _WIN32
            char* payload_ptr = _strdup(payload.c_str());
#else
            char* payload_ptr = strdup(payload.c_str());
#endif

            // Invoke Dart callback
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
        libtorrent::alert_category::performance_warning);
    
    // Default ports
    sp.set_str(libtorrent::settings_pack::listen_interfaces, "0.0.0.0:6881");
    
    // VERY simple config parsing for string-based listen_interfaces
    if (config_json) {
        std::string conf(config_json);
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
// Torrent API
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
// Streaming and Prioritization
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

void te_torrent_set_file_priority(te_torrent_handle_t* h, int file_index, int priority) {
    if (h && h->handle.is_valid()) {
        h->handle.file_priority(libtorrent::file_index_t(file_index), 
                                libtorrent::download_priority_t(static_cast<uint8_t>(priority)));
    }
}

void te_torrent_set_piece_deadline(te_torrent_handle_t* h, int piece_index, int deadline, int flags) {
    if (h && h->handle.is_valid()) {
        h->handle.set_piece_deadline(libtorrent::piece_index_t(piece_index), deadline, 
                                     static_cast<libtorrent::deadline_flags_t>(flags));
    }
}

void te_free_string(char* str) {
    if (str) free(str);
}
