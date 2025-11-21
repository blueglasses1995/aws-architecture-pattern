# AWS アーキテクチャーパターン - ローカル開発環境

このディレクトリには、AWSアーキテクチャーパターンをローカル環境で実行・テストするための設定が含まれています。

## 📋 前提条件

- Docker Desktop (または Docker + Docker Compose)
- Terraform CLI (オプション: Dockerコンテナでも実行可能)
- AWS CLI (オプション: Dockerコンテナでも実行可能)
- 8GB以上のメモリ推奨

## 🚀 クイックスタート

### 1. 環境起動

```bash
# ディレクトリ移動
cd local-development

# 全サービス起動
docker-compose up -d

# ログ確認
docker-compose logs -f localstack
```

### 2. LocalStackの動作確認

```bash
# AWS CLIでLocalStackに接続
docker-compose exec awscli sh

# S3バケット一覧（初期は空）
aws --endpoint-url=http://localstack:4566 s3 ls

# テストバケット作成
aws --endpoint-url=http://localstack:4566 s3 mb s3://test-bucket

# 確認
aws --endpoint-url=http://localstack:4566 s3 ls
```

### 3. Terraformでインフラ構築

```bash
# Terraformコンテナに入る
docker-compose exec terraform sh

# パターン5（サーバーレス）を構築
cd pattern05-serverless
terraform init
terraform plan
terraform apply -auto-approve

# リソース確認
terraform show
```

## 📁 ディレクトリ構造

```
local-development/
├── docker-compose.yml          # Docker Compose設定
├── README.md                   # このファイル
├── init-scripts/               # LocalStack初期化スクリプト
│   └── setup.sh
├── nginx/                      # Nginx設定（オンプレミス環境シミュレート）
│   ├── nginx.conf
│   └── html/
├── postgres/                   # PostgreSQL初期化
│   └── init.sql
├── terraform/                  # Terraformコード
│   ├── pattern01-three-tier/   # パターン1: 3層Webアプリ
│   ├── pattern04-cdn/          # パターン4: CDN
│   ├── pattern05-serverless/   # パターン5: サーバーレス
│   └── pattern31-lambda-edge/  # パターン31: Lambda@Edge
├── lambda-functions/           # Lambda関数コード
│   ├── api-handler/
│   ├── image-resize/
│   └── edge-function/
└── scripts/                    # ユーティリティスクリプト
    ├── deploy-all.sh
    ├── cleanup.sh
    └── test-endpoints.sh
```

## 🔧 利用可能なサービス

### LocalStack (ポート: 4566)
- S3
- Lambda
- DynamoDB
- API Gateway
- CloudFront
- SQS
- SNS
- IAM
- CloudWatch Logs
- EventBridge
- Secrets Manager

### 補助サービス
- **Nginx** (ポート: 8080/8443) - オンプレミス環境シミュレート
- **PostgreSQL** (ポート: 5432) - RDS代替
- **Redis** (ポート: 6379) - ElastiCache代替

## 📝 パターン別セットアップ

### パターン1: 3層Webアプリケーション

```bash
cd terraform/pattern01-three-tier
terraform init
terraform apply -auto-approve

# 動作確認
curl http://localhost:8080
```

**含まれるリソース:**
- Nginx (Webサーバー)
- PostgreSQL (データベース)
- ロードバランサー設定

### パターン4: 静的コンテンツ配信（CDN）

```bash
cd terraform/pattern04-cdn
terraform init
terraform apply -auto-approve

# S3にファイルアップロード
aws --endpoint-url=http://localhost:4566 s3 cp ./sample.html s3://cdn-bucket/

# CloudFront経由でアクセス（LocalStackのURL）
curl http://localhost:4566/cloudfront/...
```

**含まれるリソース:**
- S3バケット
- CloudFront Distribution
- Lambda@Edge関数

### パターン5: サーバーレスWebアプリケーション

```bash
cd terraform/pattern05-serverless
terraform init
terraform apply -auto-approve

# API Gateway エンドポイント取得
terraform output api_endpoint

# APIテスト
curl -X POST http://localhost:4566/restapis/.../dev/users \
  -H "Content-Type: application/json" \
  -d '{"name": "John Doe", "email": "john@example.com"}'
```

**含まれるリソース:**
- API Gateway
- Lambda関数（複数）
- DynamoDB テーブル
- S3バケット（静的ホスティング）

### パターン31: Lambda@Edge

```bash
cd terraform/pattern31-lambda-edge
terraform init
terraform apply -auto-approve

# Lambda@Edge関数デプロイ
cd ../../lambda-functions/edge-function
zip function.zip index.js
aws --endpoint-url=http://localhost:4566 lambda create-function \
  --function-name edge-viewer-request \
  --runtime nodejs18.x \
  --zip-file fileb://function.zip \
  --handler index.handler \
  --role arn:aws:iam::000000000000:role/lambda-role
```

**含まれるリソース:**
- CloudFront Distribution
- Lambda@Edge関数
- S3 Origin
- セキュリティヘッダー追加
- A/Bテスト機能

## 🧪 テストとデバッグ

### LocalStack Health Check

```bash
curl http://localhost:4566/_localstack/health | jq
```

### Lambda関数ログ確認

```bash
# CloudWatch Logsからログ取得
aws --endpoint-url=http://localhost:4566 logs tail /aws/lambda/my-function --follow
```

### DynamoDB データ確認

```bash
# テーブル一覧
aws --endpoint-url=http://localhost:4566 dynamodb list-tables

# テーブルスキャン
aws --endpoint-url=http://localhost:4566 dynamodb scan --table-name Users
```

### S3バケット内容確認

```bash
aws --endpoint-url=http://localhost:4566 s3 ls s3://my-bucket --recursive
```

## 🛠️ ユーティリティスクリプト

### 全パターンをデプロイ

```bash
./scripts/deploy-all.sh
```

### 全リソースをクリーンアップ

```bash
./scripts/cleanup.sh
```

### エンドポイントテスト

```bash
./scripts/test-endpoints.sh
```

## 🔍 トラブルシューティング

### LocalStackが起動しない

```bash
# コンテナログ確認
docker-compose logs localstack

# コンテナ再起動
docker-compose restart localstack
```

### Terraform実行エラー

```bash
# Terraform状態リセット
rm -rf .terraform .terraform.lock.hcl terraform.tfstate*
terraform init

# LocalStack接続確認
curl http://localhost:4566/_localstack/health
```

### Lambda関数がデプロイできない

```bash
# Lambda Executorの確認
docker-compose exec localstack bash
ls /tmp/localstack/lambda

# Docker-in-Dockerの確認
docker ps
```

## 📊 パフォーマンス比較

LocalStackは開発・テスト用途であり、本番AWSとは以下の違いがあります：

| 項目 | LocalStack | AWS |
|------|-----------|-----|
| レイテンシ | <10ms | 地域により異なる |
| スループット | マシンスペック依存 | ほぼ無制限 |
| 耐久性 | なし（揮発性） | 11 9's |
| 可用性 | シングルポイント | Multi-AZ |
| コスト | 無料（Pro版は有料） | 従量課金 |

## 🔐 セキュリティ注意事項

- このローカル環境は開発・学習用です
- 本番データは使用しないでください
- AWS認証情報（本物）は使用しないでください
- ポート4566は外部公開しないでください

## 📚 参考リンク

- [LocalStack Documentation](https://docs.localstack.cloud/)
- [Terraform LocalStack Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS CLI with LocalStack](https://docs.localstack.cloud/user-guide/integrations/aws-cli/)

## 🤝 コントリビューション

改善提案やバグ報告は、GitHubのIssueまでお願いします。

## 📄 ライセンス

MIT License
