#!/usr/bin/env bash
set -eu
MARKUP_BROWSER_DIR=$(mktemp -d)
export MARKUP_BROWSER_DIR
trap 'rm -rf -- "$MARKUP_BROWSER_DIR"' EXIT
result=0
scripts/run_tests.sh "$@" || result=1
nvim -u NONE -l tests/browser/suite.lua || result=1
exit "$result"
