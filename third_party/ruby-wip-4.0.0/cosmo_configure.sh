#!/usr/bin/env bash
# CosmoRuby configuration shim: toggles static vs plugin (.a) extensions.
# Usage: cosmo_configure.sh [--with-static-linked-ext] [--with-plugin-ext] [--with-slim-static]
# Defaults to plugin mode (dynamic load via cosmo_plugin).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RBCONFIG="$ROOT/third_party/ruby/lib/rbconfig.rb"
CONFIG_H="$ROOT/third_party/ruby/include/ruby/config.h"
MODE_CONFIG_H="$ROOT/third_party/ruby/include/ruby/config.mode.h"
MODE_RBCONFIG="$ROOT/third_party/ruby/lib/rbconfig.mode.rb"
SENTINEL="$ROOT/third_party/ruby/.cosmo_configured"
MODE="plugin" # default
BOOTSTRAP=false
SLIM_STATIC=false

for arg in "$@"; do
  case "$arg" in
    --with-static-linked-ext) MODE="static" ;;
    --with-plugin-ext) MODE="plugin" ;;
    --with-slim-static) SLIM_STATIC=true ;;
    --without-slim-static) SLIM_STATIC=false ;;
    --bootstrap) BOOTSTRAP=true ;;
    -h|--help)
      cat <<EOF
CosmoRuby configure shim
  --with-static-linked-ext   keep extensions linked into ruby.a (EXTSTATIC=1, DLEXT=.so)
  --with-plugin-ext          use cosmo_plugin-loaded .a extensions (EXTSTATIC=0, DLEXT=.a) [default]
  --with-slim-static         create zero-byte extension markers in static mode (SLIM_STATIC=1)
  --without-slim-static      disable zero-byte extension markers (SLIM_STATIC=0) [default]
  --bootstrap                build/copy automate_mkdeps + mtdeps into build/bootstrap
EOF
      exit 0
      ;;
    *)
      echo "warning: ignoring unsupported option '$arg'" >&2
      ;;
  esac
done

if [[ ! -f "$RBCONFIG" || ! -f "$CONFIG_H" ]]; then
  echo "cosmo_configure: missing rbconfig.rb or config.h" >&2
  exit 1
fi

RUBY_BIN="${HOST_RUBY:-ruby}"
export RUBYOPT=--disable-gems

MODE_UPPER=$(printf '%s' "$MODE" | tr a-z A-Z)
echo "cosmo_configure: MODE=${MODE} (using $RUBY_BIN)"

"$BOOTSTRAP" && {
  STUB="$ROOT/build/bootstrap/mkdeps_stub.sh"
  if [[ ! -x "$STUB" ]]; then
    echo "cosmo_configure: missing mkdeps stub at $STUB" >&2
    exit 1
  fi
  echo "cosmo_configure: building automate_mkdeps + mtdeps with stub mkdeps"
  make -C "$ROOT" MKDEPS="$STUB" -j"${BOOTSTRAP_JOBS:-$(nproc)}" o//third_party/build/mtdeps/automate_mkdeps
  make -C "$ROOT" MKDEPS="$STUB" -j"${BOOTSTRAP_JOBS:-$(nproc)}" o//third_party/build/mtdeps/mtdeps
  mkdir -p "$ROOT/build/bootstrap"
  cp "$ROOT/o//third_party/build/mtdeps/automate_mkdeps" "$ROOT/build/bootstrap/automate_mkdeps"
  cp "$ROOT/o//third_party/build/mtdeps/mtdeps" "$ROOT/build/bootstrap/mtdeps"
  echo "cosmo_configure: bootstrap copies placed in build/bootstrap/"
}

# Initialise static configs on first run (add includes/requires)
if [[ ! -f "$SENTINEL" ]]; then
  echo "cosmo_configure: first run - initialising static configs"

  "$RUBY_BIN" - "$CONFIG_H" "$MODE_CONFIG_H" <<'RUBY_INIT_CONFIG_H'
configh, mode_configh = ARGV
configh = File.realpath(configh)

# Check if config.h already includes config.mode.h
text = File.read(configh)
unless text.include?('#include "config.mode.h"')
  # Find the line with SLIM_STATIC and remove it (will be in config.mode.h)
  text = text.sub(/#define\s+SLIM_STATIC\s+\d+\n/, "")
  # Find the line with EXTSTATIC and remove it
  text = text.sub(/#define\s+EXTSTATIC\s+\d+\n/, "")
  # Find the line with DLEXT and remove it
  text = text.sub(/#define\s+DLEXT\s+".*?"\n/, "")
  # Find the line with SOEXT and remove it
  text = text.sub(/#define\s+SOEXT\s+".*?"\n/, "")

  # Cosmopolitan-specific fixes:
  # Add HAVE_UNAME and HAVE_SYS_UTSNAME_H after HAVE_WORKING_FORK
  text = text.sub(/(#define HAVE_WORKING_FORK 1\n)/, "\\1#define HAVE_UNAME 1\n#define HAVE_SYS_UTSNAME_H 1\n")

  # Comment out HAVE_MKNOD (Cosmopolitan doesn't support mknod for FIFOs)
  text = text.sub(/#define HAVE_MKNOD 1\n/, "/* #undef HAVE_MKNOD -- Cosmopolitan doesn't support mknod for FIFOs (returns ENOSYS) */\n")

  # Comment out CANNOT_FORK_WITH_PTHREAD (Cosmopolitan supports fork with pthreads)
  text = text.sub(/#define CANNOT_FORK_WITH_PTHREAD 1\n/, "/* Cosmopolitan supports fork() with pthreads */\n/* #define CANNOT_FORK_WITH_PTHREAD 1 */\n")

  # Add the include before the final #endif
  text = text.sub(/(#endif\s*\/\*\s*INCLUDE_RUBY_CONFIG_H\s*\*\/\s*)$/, "#include \"config.mode.h\"\n\\1")
  File.write(configh, text)
  puts "cosmo_configure: added #include \"config.mode.h\" to config.h"
else
  puts "cosmo_configure: config.h already includes config.mode.h"
end
RUBY_INIT_CONFIG_H

  "$RUBY_BIN" - "$RBCONFIG" "$MODE_RBCONFIG" <<'RUBY_INIT_RBCONFIG'
rbconfig, mode_rbconfig = ARGV
rbconfig = File.realpath(rbconfig)

# Check if rbconfig.rb already requires rbconfig.mode
text = File.read(rbconfig)
unless text.include?("require_relative 'rbconfig.mode'")
  # Remove the dynamic config lines (they'll be in rbconfig.mode.rb)
  text = text.sub(/^\s*CONFIG\["SOEXT"\]\s*=.*\n/, "")
  text = text.sub(/^\s*CONFIG\["EXTSTATIC"\]\s*=.*\n/, "")
  text = text.sub(/^\s*CONFIG\["SLIM_STATIC"\]\s*=.*\n/, "")
  text = text.sub(/^\s*CONFIG\["DLEXT"\]\s*=.*\n/, "")

  # Add require before the CONFIG.each_value expansion (before line ~329)
  # Find the "CONFIG.each_value do |val|" line and add require before it
  text = text.sub(/(^\s*CONFIG\.each_value do \|val\|)/m, "require_relative 'rbconfig.mode'\n\\1")
  File.write(rbconfig, text)
  puts "cosmo_configure: added require_relative 'rbconfig.mode' to rbconfig.rb"
else
  puts "cosmo_configure: rbconfig.rb already requires rbconfig.mode"
end
RUBY_INIT_RBCONFIG

  echo "cosmo_configure: static initialisation complete"
fi

# Generate mode-specific files (always regenerated on each run)
"$RUBY_BIN" - "$MODE_CONFIG_H" "$MODE_RBCONFIG" "$RBCONFIG" "$MODE" "$SLIM_STATIC" <<'RUBY_GEN_MODE'
mode_configh, mode_rbconfig, rbconfig_main, mode, slim_static = ARGV
# Use expand_path instead of realpath since mode files may not exist yet
mode_configh = File.expand_path(mode_configh)
mode_rbconfig = File.expand_path(mode_rbconfig)
rbconfig_main = File.expand_path(rbconfig_main)
slim_static = slim_static == "true"

plugin_mode = mode == "plugin"
slim_value = slim_static ? "yes" : "no"
slim_define = slim_static ? 1 : 0

# Generate config.mode.h
dlext = plugin_mode ? ".a" : ".so"
soext = plugin_mode ? ".a" : ".so"
extstatic = plugin_mode ? 0 : 1

config_mode_h = <<~C_HEADER
/* config.mode.h - Mode-specific configuration (generated by cosmo_configure.sh) */
/* MODE: #{mode}, SLIM_STATIC: #{slim_static} */
#ifndef RUBY_CONFIG_MODE_H
#define RUBY_CONFIG_MODE_H

#ifndef EXTSTATIC
#define EXTSTATIC #{extstatic}
#endif
#define DLEXT "#{dlext}"
#define SOEXT "#{soext}"
#ifndef SLIM_STATIC
#define SLIM_STATIC #{slim_define}
#endif

#endif /* RUBY_CONFIG_MODE_H */
C_HEADER

File.write(mode_configh, config_mode_h)
puts "cosmo_configure: generated config.mode.h (EXTSTATIC=#{extstatic}, DLEXT=#{dlext})"

# Generate rbconfig.mode.rb - includes configure_args manipulation
rbconfig_dlext = plugin_mode ? "a" : "so"
rbconfig_soext = plugin_mode ? "so" : "so"  # SOEXT is always "so" in rbconfig
rbconfig_extstatic = plugin_mode ? "no" : "yes"

# Read the main rbconfig.rb to get current configure_args
main_text = File.read(rbconfig_main)
if main_text =~ /CONFIG\["configure_args"\]\s*=\s*"([^"]*)"/
  configure_args = $1

  # Fix the --with-static-linked-ext flag based on mode
  if plugin_mode
    # Remove --with-static-linked-ext if present
    configure_args = configure_args.gsub(/'--with-static-linked-ext'\s*/, "").strip
  else
    # Add --with-static-linked-ext if not present
    unless configure_args.include?("'--with-static-linked-ext'")
      # Insert after the first configure flag
      configure_args = configure_args.sub(/^(\s*)/, "\\1'--with-static-linked-ext' ")
    end
  end
else
  # Fallback if we can't parse configure_args
  configure_args = plugin_mode ? "" : " '--with-static-linked-ext'"
end

rbconfig_mode = <<~RUBY_CONFIG
# rbconfig.mode.rb - Mode-specific configuration (generated by cosmo_configure.sh)
# MODE: #{mode}, SLIM_STATIC: #{slim_static}

RbConfig::CONFIG["DLEXT"] = "#{rbconfig_dlext}"
RbConfig::CONFIG["SOEXT"] = "#{rbconfig_soext}"
RbConfig::CONFIG["EXTSTATIC"] = "#{rbconfig_extstatic}"
RbConfig::CONFIG["SLIM_STATIC"] = "#{slim_value}"
RbConfig::CONFIG["configure_args"] = "#{configure_args}"
RUBY_CONFIG

File.write(mode_rbconfig, rbconfig_mode)
puts "cosmo_configure: generated rbconfig.mode.rb (DLEXT=#{rbconfig_dlext}, EXTSTATIC=#{rbconfig_extstatic})"
RUBY_GEN_MODE

# Touch sentinel file to indicate successful configuration
touch "$SENTINEL"
echo "cosmo_configure: mode configuration complete (mode=${MODE})"
