#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘
# YJIT Rust Library Build
#
# YJIT is Ruby's Rust-based JIT compiler. The Rust code does NOT make
# direct syscalls - it calls C functions in jit.c that use mprotect/madvise.
# Cosmopolitan provides these POSIX functions, so Rust targets standard
# x86_64-unknown-linux-gnu.

RUBY_YJIT_ENABLED ?= 1

# YJIT's Rust code targets x86_64-unknown-linux-gnu. Cross-compiling
# Rust to aarch64 with Cosmopolitan's libc is not supported, so
# disable YJIT on aarch64 builds (the x86_64 half of a fat binary
# still gets YJIT).
ifeq ($(ARCH),aarch64)
RUBY_YJIT_ENABLED := 0
endif

ifeq ($(RUBY_YJIT_ENABLED),1)

CARGO ?= $(shell command -v cargo 2>/dev/null)

# Track Rust source files for dependency detection
YJIT_RUST_SRCS := $(wildcard \
    third_party/ruby/yjit/Cargo.toml \
    third_party/ruby/yjit/src/*.rs \
    third_party/ruby/yjit/src/*/*.rs \
    third_party/ruby/yjit/src/*/*/*.rs \
    third_party/ruby/jit/Cargo.toml \
    third_party/ruby/jit/src/*.rs)

YJIT_TARGET_DIR := o/$(MODE)/third_party/ruby/yjit/target
YJIT_LIB := $(YJIT_TARGET_DIR)/release/libyjit.a

# Build YJIT Rust library
$(YJIT_LIB): $(YJIT_RUST_SRCS)
ifneq ($(CARGO),)
	@echo "Building YJIT (Rust release mode)"
	@mkdir -p $(YJIT_TARGET_DIR)
	TMPDIR=/tmp $(CARGO) build \
	    --manifest-path third_party/ruby/yjit/Cargo.toml \
	    --target-dir $(YJIT_TARGET_DIR) \
	    --release -q
else
	$(error YJIT enabled but cargo not found. Install Rust or set RUBY_YJIT_ENABLED=0)
endif

# Create relocatable object from static library
# This allows --whole-archive linkage to work properly
YJIT_LIBOBJ := o/$(MODE)/third_party/ruby/yjit/libyjit.o

$(YJIT_LIBOBJ): $(YJIT_LIB)
	@echo "Creating relocatable YJIT object"
	@mkdir -p $(dir $@)
	$(LD) -r -o $@ --whole-archive $(YJIT_LIB) --no-whole-archive

.PHONY: yjit-lib yjit-clean
yjit-lib: $(YJIT_LIB)
yjit-clean:
	rm -rf $(YJIT_TARGET_DIR)

else
# YJIT disabled - empty variables
YJIT_LIB :=
YJIT_LIBOBJ :=
endif
