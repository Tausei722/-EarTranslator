#!/bin/sh
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

echo "Installing CocoaPods dependencies..."
sudo gem install cocoapods --no-document 2>/dev/null || true
pod install --repo-update

echo "Pod install completed."
