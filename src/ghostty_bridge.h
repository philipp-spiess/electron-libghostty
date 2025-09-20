#ifndef ELECTRON_LIBGHOSTTY_GHOSTTY_BRIDGE_H_
#define ELECTRON_LIBGHOSTTY_GHOSTTY_BRIDGE_H_

#include <stdint.h>

#include "ghostty.h"
#ifdef __cplusplus
extern "C" {
#endif

void GhosttyNativeEmitSetTitle(int32_t surface_id, const char* title);
void GhosttyNativeEmitBell(int32_t surface_id);
void GhosttyNativeEmitSurfaceExit(int32_t surface_id, bool process_alive, uint32_t exit_code);
void GhosttyNativeEmitClipboardReadRequest(int32_t surface_id,
                                           uint64_t request_id,
                                           ghostty_clipboard_e clipboard);
void GhosttyNativeEmitClipboardWrite(int32_t surface_id,
                                     const char* text,
                                     ghostty_clipboard_e clipboard,
                                     bool confirm);

#ifdef __cplusplus
}
#endif

#endif  // ELECTRON_LIBGHOSTTY_GHOSTTY_BRIDGE_H_
