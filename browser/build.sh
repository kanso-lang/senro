#!/bin/sh
# Build what an app's page loads to run its components:
#
#   KANSO=/path/to/kanso sh browser/build.sh <app> <runtime.wasm>
#
# The app's browser.kso is built for the browser (`kanso build --wasm`) and
# lands at public/senro/app.wasm, beside the kanso runtime built for wasm32,
# which kanso's scripts/build_runtime_wasm.sh writes. The page script fetches
# both from /senro/.
set -e
app=$1
runtime=$2
KANSO=${KANSO:-kanso}
mkdir -p "$app/public/senro"
(cd "$app" && "$KANSO" build browser.kso --wasm > /dev/null)
mv "$app/browser.wasm" "$app/public/senro/app.wasm"
rm -f "$app/browser.ll"
cp "$runtime" "$app/public/senro/runtime.wasm"
