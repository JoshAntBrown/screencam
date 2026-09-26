#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=ScreenCam.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp Info.plist $APP/Contents/
cp icon/AppIcon.icns $APP/Contents/Resources/
xcrun swiftc -O -swift-version 5 main.swift -o $APP/Contents/MacOS/ScreenCam
# Sign with a stable identity if available so macOS permissions survive rebuilds.
if security find-identity -v -p codesigning | grep -q "Apple Development"; then
  codesign --force --sign "Apple Development" $APP
else
  codesign --force --sign - $APP
fi
echo "Built $PWD/$APP"
