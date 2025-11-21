#!/bin/bash

# Lambda関数のビルドスクリプト

set -e

echo "Building Lambda functions..."

# create_user
echo "Building create_user..."
cd "$(dirname "$0")"
mkdir -p build/create_user
cp create_user.js build/create_user/index.js
cd build/create_user
npm init -y
npm install @aws-sdk/client-dynamodb @aws-sdk/lib-dynamodb
zip -r ../create_user.zip .
cd ../..
mv build/create_user.zip create_user.zip

# list_users
echo "Building list_users..."
mkdir -p build/list_users
cp list_users.js build/list_users/index.js
cd build/list_users
npm init -y
npm install @aws-sdk/client-dynamodb @aws-sdk/lib-dynamodb
zip -r ../list_users.zip .
cd ../..
mv build/list_users.zip list_users.zip

# クリーンアップ
rm -rf build

echo "✅ Build complete!"
echo "Created:"
echo "  - create_user.zip"
echo "  - list_users.zip"
