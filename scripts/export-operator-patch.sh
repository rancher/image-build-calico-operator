#!/bin/sh
set -eu

cd "$(git rev-parse --show-toplevel)"
git add --intent-to-add --all
git diff --check refs/patch-base -- >&2
git diff --binary refs/patch-base --
