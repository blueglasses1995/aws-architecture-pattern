#!/bin/bash

# LocalStack初期化スクリプト
# このスクリプトはLocalStack起動後に自動実行されます

set -e

echo "🚀 Initializing LocalStack..."

# AWS CLI設定
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=ap-northeast-1

# S3バケット作成（サンプル）
echo "Creating S3 buckets..."
awslocal s3 mb s3://sample-bucket || true
awslocal s3 mb s3://logs-bucket || true

# DynamoDBテーブル作成（サンプル）
echo "Creating DynamoDB tables..."
awslocal dynamodb create-table \
    --table-name SampleTable \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    || true

# SQSキュー作成（サンプル）
echo "Creating SQS queues..."
awslocal sqs create-queue --queue-name sample-queue || true

# SNSトピック作成（サンプル）
echo "Creating SNS topics..."
awslocal sns create-topic --name sample-topic || true

echo "✅ LocalStack initialization complete!"
