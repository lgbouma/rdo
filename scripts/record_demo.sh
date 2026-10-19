#!/bin/sh
# Records frames for docs/demo.gif in the iOS simulator, then composes the gif.
# Usage: scripts/record_demo.sh [simulator name]   (default: iPhone 17)
set -e
cd "$(dirname "$0")/.."
SIM="${1:-iPhone 17}"
FRAMES="$(mktemp -d)"
TEST_RUNNER_PHONELIST_DEMO_DIR="$FRAMES" xcodebuild test \
  -project PhoneList.xcodeproj -scheme PhoneList \
  -destination "platform=iOS Simulator,name=$SIM" CODE_SIGNING_ALLOWED=NO \
  -only-testing:PhoneListUITests/DemoRecording 2>&1 | grep -E "Test Case|error:|\*\* "
python3 scripts/make_demo_gif.py "$FRAMES" docs/demo.gif
