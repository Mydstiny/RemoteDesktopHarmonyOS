#pragma once
#include <atomic>
#include <cstdint>
#include <string>

struct SessionTrafficSnapshot {
    bool available = false;
    uint64_t generation = 0;
    uint64_t received = 0;
    uint64_t sent = 0;
    std::string scope;
};

struct SessionTrafficCounters {
    std::atomic<uint64_t> received {0};
    std::atomic<uint64_t> sent {0};
    std::atomic<bool> available {false};
    uint64_t generation = 0;
    SessionTrafficSnapshot snapshot() const {
        return {available.load(std::memory_order_acquire), generation,
            received.load(std::memory_order_relaxed), sent.load(std::memory_order_relaxed),
            "rdp-tcp-payload"};
    }
};
