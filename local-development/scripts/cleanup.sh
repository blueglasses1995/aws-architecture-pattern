#!/bin/bash

# 全リソースのクリーンアップスクリプト

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🧹 Cleaning up all AWS resources..."
echo ""

# 確認
read -p "This will destroy all Terraform resources. Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# パターン31: Lambda@Edge
echo "🌐 Cleaning Pattern 31: Lambda@Edge"
cd "$PROJECT_ROOT/terraform/pattern31-lambda-edge"
if [ -f "terraform.tfstate" ]; then
    terraform destroy -auto-approve
fi
echo "✅ Pattern 31 cleaned"
echo ""

# パターン5: サーバーレス
echo "📦 Cleaning Pattern 5: Serverless"
cd "$PROJECT_ROOT/terraform/pattern05-serverless"
if [ -f "terraform.tfstate" ]; then
    terraform destroy -auto-approve
fi
echo "✅ Pattern 5 cleaned"
echo ""

# LocalStackデータクリア（オプション）
read -p "Clear LocalStack data? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Clearing LocalStack data..."
    rm -rf /tmp/localstack/*
    echo "✅ LocalStack data cleared"
fi

echo ""
echo "🎉 Cleanup complete!"
echo ""
echo "To restart fresh:"
echo "  1. docker-compose down"
echo "  2. docker-compose up -d"
echo "  3. ./scripts/deploy-all.sh"
echo ""
