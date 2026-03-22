#include "secure_buffer.h"

// Ensure libsodium is initialized exactly once.
// Safe to call multiple times — subsequent calls are no-ops.
namespace {
    [[maybe_unused]] static int sodium_initialized = []() {
        if (sodium_init() < 0) {
            // Fatal — can't use libsodium primitives.
            std::abort();
        }
        return 1;
    }();
}
