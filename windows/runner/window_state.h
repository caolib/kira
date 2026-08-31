#ifndef RUNNER_WINDOW_STATE_H_
#define RUNNER_WINDOW_STATE_H_

#include <windows.h>

namespace window_state {

// Loads the window bounds persisted by the previous session into |out_rect|
// (physical pixels, screen coordinates). Returns false when no usable state
// exists, in which case the caller should fall back to its own defaults.
bool Load(RECT& out_rect);

// Persists the bounds of |hwnd| for the next session. No-op when the window
// is minimized or maximized, so those sessions keep the last normal-state
// bounds instead of persisting workspace-coordinate placement data.
void Save(HWND hwnd);

}  // namespace window_state

#endif  // RUNNER_WINDOW_STATE_H_
