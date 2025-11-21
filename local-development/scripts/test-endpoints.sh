#!/bin/bash

# エンドポイントテストスクリプト

set -e

echo "🧪 Testing deployed endpoints..."
echo ""

# LocalStack確認
echo "1. LocalStack Health Check"
curl -s http://localhost:4566/_localstack/health | jq -r '.services | to_entries[] | "\(.key): \(.value)"'
echo "✅ LocalStack OK"
echo ""

# S3バケット一覧
echo "2. S3 Buckets"
aws --endpoint-url=http://localhost:4566 s3 ls
echo ""

# DynamoDBテーブル一覧
echo "3. DynamoDB Tables"
aws --endpoint-url=http://localhost:4566 dynamodb list-tables
echo ""

# Lambda関数一覧
echo "4. Lambda Functions"
aws --endpoint-url=http://localhost:4566 lambda list-functions --query 'Functions[].FunctionName' --output table
echo ""

# API Gateway一覧
echo "5. API Gateway APIs"
aws --endpoint-url=http://localhost:4566 apigatewayv2 get-apis --query 'Items[].{Name:Name,ApiId:ApiId,Endpoint:ApiEndpoint}' --output table
echo ""

# Nginx確認
echo "6. Nginx"
if curl -s http://localhost:8080 > /dev/null; then
    echo "✅ Nginx is accessible at http://localhost:8080"
else
    echo "❌ Nginx is not accessible"
fi
echo ""

# PostgreSQL確認
echo "7. PostgreSQL"
if docker-compose exec -T postgres pg_isready -U admin > /dev/null 2>&1; then
    echo "✅ PostgreSQL is ready"
else
    echo "❌ PostgreSQL is not ready"
fi
echo ""

# Redis確認
echo "8. Redis"
if docker-compose exec -T redis redis-cli ping > /dev/null 2>&1; then
    echo "✅ Redis is ready"
else
    echo "❌ Redis is not ready"
fi
echo ""

echo "🎉 All tests complete!"
echo ""
echo "To test the API:"
echo "  # Get API endpoint"
echo "  cd terraform/pattern05-serverless"
echo "  terraform output api_endpoint"
echo ""
echo "  # Create user"
echo "  curl -X POST http://localhost:4566/restapis/.../dev/users \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"name\":\"John\",\"email\":\"john@example.com\"}'"
echo ""
echo "  # List users"
echo "  curl http://localhost:4566/restapis/.../dev/users"
echo ""
