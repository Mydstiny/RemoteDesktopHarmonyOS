#pragma once

/**
 * Forward the process stderr (Rust `eprintln!` from rustdesk_ffi, library console
 * output) to hilog so device log exports contain it. Idempotent; installed once at
 * module load. The pipe stays blocking: Rust panics when a stderr write fails, so a
 * dedicated reader keeps it drained and only rate-limits what reaches hilog.
 */
namespace StderrHilogBridge {
void Install();
}
