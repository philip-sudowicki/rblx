#!/usr/bin/env bash
# DEEP HAUL verification pipeline.
#
#   tools/check.sh          run everything
#   tools/check.sh types    only the luau-lsp type check
#
# Requires rojo, luau-lsp, selene and luau (the Luau CLI) on PATH. `rokit install` provides the
# first three; the Luau CLI comes from https://github.com/luau-lang/luau/releases.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CACHE="$ROOT/tools/.cache"
mkdir -p "$CACHE" build
DEFS="$CACHE/globalTypes.d.luau"
if [ ! -f "$DEFS" ]; then
	echo "==> downloading Roblox type definitions for luau-lsp"
	curl -sSL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi

step() { printf '\n==> %s\n' "$1"; }

run_types() {
	step "rojo sourcemap"
	rojo sourcemap default.project.json --output sourcemap.json
	step "luau-lsp analyze (strict, Roblox definitions)"
	luau-lsp analyze \
		--sourcemap=sourcemap.json \
		--definitions="$DEFS" \
		--base-luaurc=.luaurc \
		--ignore="src/server/Vendor/**" \
		--ignore="**/Vendor/**" \
		src
}

run_lint() {
	step "selene"
	selene src/shared src/client src/first src/server/Services src/server/Config src/server/Main.server.luau
}

run_tests() {
	step "unit tests (luau CLI)"
	python3 tools/bundle_tests.py
	luau build/test_bundle.luau
}

run_build() {
	step "rojo build"
	rojo build default.project.json --output build/DeepHaul.rbxl
}

case "${1:-all}" in
	types) run_types ;;
	lint) run_lint ;;
	tests) run_tests ;;
	build) run_build ;;
	all)
		run_types
		run_lint
		run_tests
		run_build
		step "all checks passed"
		;;
	*) echo "unknown step: $1" >&2; exit 2 ;;
esac
