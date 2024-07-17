#!/bin/sh

set -e

scripts/clean.sh
lune run scripts/dump-services.luau
rojo build -o import-plugin.rbxm default.project.json