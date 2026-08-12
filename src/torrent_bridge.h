#ifdef __cplusplus
extern "C" {
#endif
#include <stdint.h>

#if defined(_WIN32)
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

FFI_PLUGIN_EXPORT int32_t te_ping(void);

#ifdef __cplusplus
}
#endif
