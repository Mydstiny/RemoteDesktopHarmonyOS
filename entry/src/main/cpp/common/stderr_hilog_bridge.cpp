#include "stderr_hilog_bridge.h"

#include <hilog/log.h>
#include <unistd.h>
#include <cerrno>
#include <fcntl.h>
#include <atomic>
#include <chrono>
#include <string>
#include <thread>

namespace StderrHilogBridge {
namespace {
constexpr unsigned int kDomain = 0x0026;
constexpr const char* kTag = "NativeStderr";
// At most this many lines per window reach hilog; the rest are counted and reported.
constexpr int kLinesPerWindow = 300;
constexpr auto kWindow = std::chrono::seconds(10);
constexpr size_t kMaxLine = 1024;
std::atomic<bool> g_installed {false};

void Emit(const std::string& line) {
    OH_LOG_Print(LOG_APP, LOG_INFO, kDomain, kTag, "%{public}s", line.c_str());
}

void Pump(int readFd) {
    char buffer[2048];
    std::string line;
    auto windowStart = std::chrono::steady_clock::now();
    int linesInWindow = 0;
    long suppressed = 0;
    auto flushLine = [&]() {
        if (line.empty()) { return; }
        const auto now = std::chrono::steady_clock::now();
        if (now - windowStart >= kWindow) {
            if (suppressed > 0) {
                Emit("[stderr] " + std::to_string(suppressed) + " lines suppressed (rate limit)");
            }
            windowStart = now;
            linesInWindow = 0;
            suppressed = 0;
        }
        if (linesInWindow < kLinesPerWindow) {
            ++linesInWindow;
            Emit(line);
        } else {
            ++suppressed;
        }
        line.clear();
    };
    // The read end is never closed: writers would then get EPIPE/SIGPIPE, and Rust's
    // eprintln! panics when stderr fails.
    for (;;) {
        const ssize_t count = read(readFd, buffer, sizeof(buffer));
        if (count < 0 && errno == EINTR) { continue; }
        if (count <= 0) {
            flushLine();
            if (count == 0) { return; }  // Every writer is gone; nothing more can arrive.
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            continue;
        }
        for (ssize_t i = 0; i < count; ++i) {
            const char c = buffer[i];
            if (c == '\n') { flushLine(); continue; }
            if (line.size() < kMaxLine) { line.push_back(c); }
        }
    }
}
} // namespace

void Install() {
    bool expected = false;
    if (!g_installed.compare_exchange_strong(expected, true)) { return; }
    int fds[2] = {-1, -1};
    if (pipe(fds) != 0) { g_installed.store(false); return; }
    fcntl(fds[0], F_SETFD, FD_CLOEXEC);
    if (dup2(fds[1], STDERR_FILENO) < 0) {
        close(fds[0]);
        close(fds[1]);
        g_installed.store(false);
        return;
    }
    close(fds[1]);
    std::thread(Pump, fds[0]).detach();
    OH_LOG_Print(LOG_APP, LOG_INFO, kDomain, kTag, "%{public}s", "stderr forwarded to hilog");
}
} // namespace StderrHilogBridge
