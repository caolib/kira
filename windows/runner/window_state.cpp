#include "window_state.h"

#include <shlobj.h>

#include <fstream>

namespace {

// %APPDATA%\kira\window_state.txt, created on demand. Returns an empty path
// when the AppData location is unavailable; callers then skip persistence.
std::wstring StateFilePath() {
  PWSTR appdata_raw = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr,
                                  &appdata_raw))) {
    return std::wstring();
  }
  std::wstring dir(appdata_raw);
  CoTaskMemFree(appdata_raw);
  dir += L"\\kira";
  CreateDirectoryW(dir.c_str(), nullptr);
  return dir + L"\\window_state.txt";
}

}  // namespace

namespace window_state {

bool Load(RECT& out_rect) {
  const std::wstring path = StateFilePath();
  if (path.empty()) {
    return false;
  }

  std::ifstream file(path);
  if (!file.is_open()) {
    return false;
  }

  long left, top, right, bottom;
  char comma;
  if (!(file >> left >> comma >> top >> comma >> right >> comma >> bottom) ||
      right <= left || bottom <= top) {
    return false;
  }

  // Reject placement whose center lies on no monitor (e.g. the display was
  // disconnected between sessions); fall back to defaults instead.
  const POINT center = {left + (right - left) / 2, top + (bottom - top) / 2};
  if (MonitorFromPoint(center, MONITOR_DEFAULTTONULL) == nullptr) {
    return false;
  }

  out_rect = {left, top, right, bottom};
  return true;
}

void Save(HWND hwnd) {
  const std::wstring path = StateFilePath();
  if (path.empty() || hwnd == nullptr || IsIconic(hwnd) || IsZoomed(hwnd)) {
    return;
  }

  RECT rect;
  if (!GetWindowRect(hwnd, &rect)) {
    return;
  }

  std::ofstream file(path, std::ios::trunc);
  if (!file.is_open()) {
    return;
  }
  file << rect.left << ',' << rect.top << ',' << rect.right << ',' << rect.bottom;
}

}  // namespace window_state
