#!/bin/bash

# 全パターンのデプロイスクリプト

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🚀 Deploying all AWS architecture patterns..."
echo ""

# LocalStack起動確認
echo "Checking LocalStack..."
if ! curl -s http://localhost:4566/_localstack/health > /dev/null; then
    echo "❌ LocalStack is not running. Please start it first:"
    echo "   docker-compose up -d localstack"
    exit 1
fi
echo "✅ LocalStack is running"
echo ""

# パターン5: サーバーレス
echo "📦 Pattern 5: Serverless Web Application"
cd "$PROJECT_ROOT/terraform/pattern05-serverless"

# Lambda関数ビルド
if [ -d "lambda" ]; then
    echo "Building Lambda functions..."
    cd lambda
    chmod +x build.sh
    ./build.sh
    cd ..
fi

# Terraform実行
terraform init -upgrade
terraform apply -auto-approve

echo "✅ Pattern 5 deployed"
echo ""

# パターン31: Lambda@Edge
echo "🌐 Pattern 31: Lambda@Edge"
cd "$PROJECT_ROOT/terraform/pattern31-lambda-edge"

# Lambda@Edge関数ビルド
if [ -d "lambda" ]; then
    echo "Building Lambda@Edge functions..."
    cd lambda
    chmod +x build.sh
    ./build.sh
    cd ..
fi

# Terraform実行
terraform init -upgrade
terraform apply -auto-approve

echo "✅ Pattern 31 deployed"
echo ""

# デプロイ完了
echo "🎉 All patterns deployed successfully!"
echo ""
echo "📝 Next steps:"
echo "  1. Run './scripts/test-endpoints.sh' to test the deployments"
echo "  2. Check http://localhost:8080 for Nginx"
echo "  3. Access S3 website and API Gateway endpoints (see outputs above)"
echo ""
