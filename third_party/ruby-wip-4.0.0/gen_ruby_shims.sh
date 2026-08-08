#!/usr/bin/env bash
# Regenerate the ruby_shims/ directory required by mkdeps dependency scanning.
#
# ruby.deps.mk lists entries like ruby_shims/internal+array.h in
# THIRD_PARTY_RUBY_A_INCS.  mkdeps (build/bootstrap/mtdeps -P ruby_shims/)
# needs those files to exist so it can read them during Stage 2 resolution
# (see docs/ai/cosmo_ruby/MKDEPS_AUTOMATION_SYSTEM.md).  Historically they
# were produced by bin/create_shims.sh, which was never committed; this
# script rebuilds them deterministically from ruby.deps.mk instead.
#
# Mapping: strip "ruby_shims/", replace '+' with '/', then resolve against
#   1. repo root            (entries like third_party+ruby+include+ruby.h)
#   2. third_party/ruby/    (entries like internal+array.h)
# Each shim is a one-line include of the resolved file so mkdeps picks up
# the real header's transitive dependencies.  Unresolvable entries (e.g.
# generated files that don't exist yet) become empty shims, which merely
# weakens dependency tracking for those files.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEPS_MK="$ROOT/third_party/ruby/ruby.deps.mk"
OUT="$ROOT/ruby_shims"

mkdir -p "$OUT"

missing=0
total=0
while IFS= read -r entry; do
  total=$((total + 1))
  name="${entry#ruby_shims/}"
  real="${name//+//}"
  shim="$OUT/$name"
  resolved=""
  for base in "" "third_party/ruby/" "third_party/ruby/include/"; do
    if [ -f "$ROOT/$base$real" ]; then
      resolved="$base$real"
      break
    fi
  done
  if [ -z "$resolved" ]; then
    # Fall back to locating the header anywhere in the ruby tree
    # (covers -I'd subdirs like enc/, enc/trans/, prism/, .ext includes).
    resolved="$(cd "$ROOT" && find third_party/ruby/ -type f -path "*/$real" 2>/dev/null | sort | head -n1 || true)"
  fi
  if [ -n "$resolved" ]; then
    printf '#include "%s"\n' "$resolved" > "$shim"
  else
    : > "$shim"
    missing=$((missing + 1))
    echo "gen_ruby_shims: no source found for $entry (created empty shim)" >&2
  fi
done < <(grep -o 'ruby_shims/[^ \\]*' "$DEPS_MK" | sort -u)

echo "gen_ruby_shims: wrote $total shims to $OUT ($missing empty)"
