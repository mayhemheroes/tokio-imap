#![no_main]

//! Ported from upstream's imap-proto/fuzz/fuzz_targets/utf8_parse_response.rs (and the
//! fork's old `utf8-parse-response` Mayhem target): drives the full IMAP server-response
//! parser — imap_proto::Response::from_bytes — over arbitrary bytes. This is imap-proto's
//! primary parsing surface (RFC 3501 + the 2087/2971/4314/4315/4551/5161/5256/5464/7162
//! extension parsers all hang off it).

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let _ = imap_proto::Response::from_bytes(data);
});
