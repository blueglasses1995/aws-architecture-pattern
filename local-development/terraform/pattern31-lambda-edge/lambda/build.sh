#!/bin/bash

# Lambda@Edge関数のビルドスクリプト

set -e

echo "Building Lambda@Edge functions..."

cd "$(dirname "$0")"

# viewer_request
echo "Building viewer_request..."
zip viewer_request.zip viewer_request.js
echo "✅ viewer_request.zip created"

# viewer_response
echo "Building viewer_response..."
zip viewer_response.zip viewer_response.js
echo "✅ viewer_response.zip created"

echo ""
echo "✅ Build complete!"
echo "Created:"
echo "  - viewer_request.zip"
echo "  - viewer_response.zip"
