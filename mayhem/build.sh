#!/usr/bin/env bash
#
# mayhem/build.sh — build tokio-imap's cargo-fuzz target as a sanitized libFuzzer
# binary (OSS-Fuzz Rust path: cargo-fuzz + ASan via RUSTFLAGS) and pre-build the
# workspace test suite that mayhem/test.sh runs. The harness is ported from
# upstream's imap-proto/fuzz/fuzz_targets/utf8_parse_response.rs into the ADDITIVE
# mayhem/fuzz/ crate (upstream's fuzz crate pins libfuzzer-sys to an unpinned git
# ref; the additive crate uses crates.io libfuzzer-sys 0.4 so the build is
# cacheable/air-gapped — same code path: imap_proto::Response::from_bytes).
#
# Runs inside the commit image (RUST mayhem/Dockerfile) as `mayhem` in /mayhem ($SRC).
# Toolchain + cargo registry live at $CARGO_HOME=/opt/toolchains/rust/cargo (pinned absolute).
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
#   - This FIRST build (CI, online) populates the cargo registry under $CARGO_HOME.
#   - The re-run resolves crates from that cache; the rlenv runtime exports
#     CARGO_NET_OFFLINE=true, so do NOT hard-code `--offline` here.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

# §6.2 item 10 — DWARF < 4 so Mayhem's triage can read symbols. rustc's plain debuginfo can
# emit DWARF-5, and the prebuilt asan runtime archive (DWARF5) links FIRST regardless. The
# cc-wrapper (baked by the Dockerfile) prepends a DWARF3 anchor.o on the final link so a DWARF3
# CU is at .debug_info offset 0 (what verify-repo's readelf -m1 check reads). Overridable.
RUST_DEBUG_FLAGS="${RUST_DEBUG_FLAGS:- -Cdebuginfo=2 -Zdwarf-version=3 -Clinker=/opt/mayhem-dwarf3-anchor/cc-wrapper.sh}"

# OSS-Fuzz Rust libFuzzer+ASan flags. cargo-fuzz sets the ASan flag itself; we pin it
# explicitly. --cfg fuzzing matches libfuzzer-sys; force-frame-pointers aids ASan backtraces.
# NOTE: the base image's $SANITIZER_FLAGS is a clang flag set that rustc ignores — for Rust
# the sanitizer is threaded via RUSTFLAGS (-Zsanitizer=address, the OSS-Fuzz Rust path), which
# instruments ALL crates cargo-fuzz builds (imap-proto included), not just the harness.
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing -Zsanitizer=address -Cforce-frame-pointers ${RUST_DEBUG_FLAGS}"

# ADDITIVE cargo-fuzz crate: mayhem/fuzz/ depends on imap-proto by path.
FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

echo "=== cargo fuzz build (image nightly, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# Pre-build the workspace's own test suite (imap-proto + tokio-imap, project NORMAL flags,
# a clean non-sanitized build) so mayhem/test.sh only RUNS it. RUSTFLAGS above is fuzz-only —
# keep it out of the test build.
echo "=== cargo test --no-run --workspace (tokio-imap suite, clean flags) ==="
env -u RUSTFLAGS cargo test --no-run --workspace

echo "build.sh complete"
