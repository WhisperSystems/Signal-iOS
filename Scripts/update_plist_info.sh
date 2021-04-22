#!/usr/bin/env sh

set -e

# PROJECT_DIR will be set when run from xcode, else we infer it
if [ -z "${PROJECT_DIR}" ]; then
    PROJECT_DIR=$(git rev-parse --show-toplevel)
    echo "inferred ${PROJECT_DIR}"
fi

# Capture hash & comment from last WebRTC git commit.
cd "$PROJECT_DIR"/ThirdParty/WebRTC/
_git_commit=$(git log --pretty=oneline | head -1)
cd "$PROJECT_DIR"

# Remove existing .plist entry, if any.
/usr/libexec/PlistBuddy -c 'Delete BuildDetails' Signal/Signal-Info.plist || true
# Add new .plist entry.
/usr/libexec/PlistBuddy -c 'add BuildDetails dict' Signal/Signal-Info.plist

/usr/libexec/PlistBuddy -c "add :BuildDetails:WebRTCCommit string '$_git_commit'" Signal/Signal-Info.plist

_osx_version=$(defaults read loginwindow SystemVersionStampAsString)
/usr/libexec/PlistBuddy -c "add :BuildDetails:OSXVersion string '$_osx_version'" Signal/Signal-Info.plist

echo "CONFIGURATION: ${CONFIGURATION}"
if [ "${CONFIGURATION}" = "App Store Release" ] || [ "${CONFIGURATION}" = "Profiling" ]; then
    /usr/libexec/PlistBuddy -c "add :BuildDetails:XCodeVersion string '${XCODE_VERSION_MAJOR}.${XCODE_VERSION_MINOR}'" Signal/Signal-Info.plist

    # Use UTC
    _build_datetime=$(date -u)
    /usr/libexec/PlistBuddy -c "add :BuildDetails:DateTime string '$_build_datetime'" Signal/Signal-Info.plist

    _build_timestamp=$(date +%s)
    /usr/libexec/PlistBuddy -c "add :BuildDetails:Timestamp string '$_build_timestamp'" Signal/Signal-Info.plist
fi

