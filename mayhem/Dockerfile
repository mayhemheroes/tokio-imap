# Build Stage
FROM ghcr.io/evanrichter/cargo-fuzz:latest as builder

## Add source code to the build stage.
ADD . /src
WORKDIR /src

RUN echo building instrumented harnesses && \
    bash -c "pushd imap-proto/fuzz && cargo +nightly -Z sparse-registry fuzz build && popd" && \
    mv imap-proto/fuzz/target/x86_64-unknown-linux-gnu/release/utf8_parse_response /utf8_parse_response && \
    echo done

RUN echo building non-instrumented harnesses && \
    export RUSTFLAGS="--cfg fuzzing -Clink-dead-code -Cdebug-assertions -C codegen-units=1" && \
    bash -c "pushd imap-proto/fuzz && cargo +nightly -Z sparse-registry build --release && popd" && \
    mv imap-proto/fuzz/target/release/utf8_parse_response /utf8_parse_response_no_inst && \
    echo done

# Package Stage
FROM rustlang/rust:nightly

COPY --from=builder /utf8_parse_response /utf8_parse_response_no_inst /
