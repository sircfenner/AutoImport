#!/bin/sh

set -e

scripts/clean.sh
lune run scripts/dump-services.luau
rojo build --plugin import-plugin-dev.rbxm --watch default.project.json