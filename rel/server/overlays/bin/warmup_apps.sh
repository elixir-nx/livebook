#!/bin/sh

echo "Using warmup_apps.sh is deprecated. Please use warmup_apps instead."

cd -P -- "$(dirname -- "$0")"
exec ./livebook eval Livebook.Release.warmup_apps
