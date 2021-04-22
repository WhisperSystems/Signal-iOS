#!/usr/bin/env sh

set -e

# Remove existing .plist entry, if any.
/usr/libexec/PlistBuddy -c "Delete BuildTimestamp" SignalShareExtension/Info.plist || true

if [ "${CONFIGURATION}" = "App Store Release" ]; then
    _build_timestamp=$(date +%s)
    /usr/libexec/PlistBuddy -c "add :BuildTimestamp string '$_build_timestamp'" SignalShareExtension/Info.plist
fi

