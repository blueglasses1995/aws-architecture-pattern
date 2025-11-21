# パターン5: サーバーレスWebアプリケーション

## 問題

スタートアップ企業が、予算を抑えつつスケーラブルなWebアプリケーションを構築したいと考えています。
以下の要件を満たすアーキテクチャーを設計してください。

**要件:**
- サーバー管理を最小限にしたい
- トラフィックは不定期（月間0-100万リクエスト）
- 開発リソースが限られている
- コストを使った分だけに抑えたい
- REST APIとフロントエンドを提供

## 推奨アーキテクチャー

```
[ユーザー]
    ↓
[CloudFront]
    ↓
[S3] (静的サイトホスティング)
    ↓ API呼び出し
[API Gateway]
    ↓
[Lambda関数群]
    ↓
[DynamoDB]
```

### 使用するAWSサービス:
- **S3**: 静的ウェブホスティング
- **CloudFront**: CDN
- **API Gateway**: REST/WebSocket API
- **Lambda**: サーバーレスコンピューティング
- **DynamoDB**: NoSQLデータベース
- **Cognito**: 認証・認可
- **CloudWatch**: ログ・監視

## 解説

### なぜこのアーキテクチャーなのか

#### 1. サーバーレスの利点

**従来のサーバーベース vs サーバーレス:**

```
従来型:
- EC2 t3.small × 2台: 24時間365日稼働
- 月額: 約10,000円（トラフィックゼロでも課金）
- 運用: OS更新、セキュリティパッチ、監視

サーバーレス:
- Lambda: リクエスト毎に課金
- 月額: 0リクエスト = 0円、100万リクエスト = 約200円
- 運用: ほぼゼロ（AWSが管理）
```

#### 2. Lambda関数の設計

**関数の粒度:**

**マイクロ関数（推奨）:**
```javascript
// getUserById.js
exports.handler = async (event) => {
    const userId = event.pathParameters.id;
    const dynamodb = new AWS.DynamoDB.DocumentClient();

    const result = await dynamodb.get({
        TableName: 'Users',
        Key: { userId }
    }).promise();

    return {
        statusCode: 200,
        body: JSON.stringify(result.Item)
    };
};

// createUser.js
exports.handler = async (event) => {
    const user = JSON.parse(event.body);
    const dynamodb = new AWS.DynamoDB.DocumentClient();

    await dynamodb.put({
        TableName: 'Users',
        Item: {
            userId: uuidv4(),
            ...user,
            createdAt: new Date().toISOString()
        }
    }).promise();

    return {
        statusCode: 201,
        body: JSON.stringify({ message: 'User created' })
    };
};
```

**コールドスタート対策:**
```javascript
// 初期化は関数外で（再利用される）
const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

// 接続プールの設定
const https = require('https');
const agent = new https.Agent({
    keepAlive: true,
    maxSockets: 50
});

AWS.config.update({
    httpOptions: { agent }
});

// ハンドラー
exports.handler = async (event) => {
    // 処理
};
```

**Provisioned Concurrency（重要な関数用）:**
```yaml
# SAM template
Functions:
  CriticalFunction:
    Type: AWS::Serverless::Function
    Properties:
      Handler: index.handler
      Runtime: nodejs18.x
      ProvisionedConcurrencyConfig:
        ProvisionedConcurrentExecutions: 5  # 常に5インスタンス待機
```

#### 3. API Gatewayの設計

**REST API vs HTTP API:**

| 機能 | REST API | HTTP API |
|------|---------|----------|
| コスト | 高 | 低（約30%削減） |
| レイテンシー | 標準 | 低（約40%削減） |
| 認証 | Cognito, Lambda, IAM | Cognito, JWT, IAM |
| WAF統合 | ○ | × |
| 使用推奨 | 複雑な要件 | シンプルなAPI |

**API Gateway設定例:**
```yaml
# OpenAPI仕様
openapi: 3.0.1
info:
  title: User API
  version: 1.0.0
paths:
  /users:
    get:
      x-amazon-apigateway-integration:
        type: aws_proxy
        httpMethod: POST
        uri: arn:aws:apigateway:ap-northeast-1:lambda:path/2015-03-31/functions/arn:aws:lambda:ap-northeast-1:123456789012:function:listUsers/invocations
        responses:
          default:
            statusCode: 200
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/User'
    post:
      x-amazon-apigateway-integration:
        type: aws_proxy
        httpMethod: POST
        uri: arn:aws:apigateway:ap-northeast-1:lambda:path/2015-03-31/functions/arn:aws:lambda:ap-northeast-1:123456789012:function:createUser/invocations
```

**スロットリング設定:**
```yaml
# 全体の制限
AccountSettings:
  ThrottleBurstLimit: 5000
  ThrottleRateLimit: 10000

# ステージ毎の制限
Stage:
  ThrottleBurstLimit: 500
  ThrottleRateLimit: 1000

# メソッド毎の制限
MethodSettings:
  /users/GET:
    ThrottleBurstLimit: 100
    ThrottleRateLimit: 200
```

#### 4. DynamoDBの設計

**シングルテーブル設計:**
```javascript
// PK（Partition Key）とSK（Sort Key）の設計
Table: AppData

// ユーザー
PK: USER#123
SK: PROFILE
Attributes: { name, email, ... }

// ユーザーの投稿
PK: USER#123
SK: POST#2024-01-01#001
Attributes: { title, content, ... }

// 投稿へのコメント
PK: POST#001
SK: COMMENT#2024-01-01#001
Attributes: { userId, comment, ... }
```

**GSI（Global Secondary Index）:**
```javascript
// メールアドレスで検索
GSI: EmailIndex
  PK: email
  SK: (なし)

// 投稿日時で検索
GSI: PostDateIndex
  PK: POST
  SK: createdAt
```

**オンデマンドモード vs プロビジョニングモード:**
```
オンデマンド（推奨）:
- 使った分だけ課金
- 自動スケーリング
- 予測困難なトラフィックに最適

プロビジョニング:
- RCU/WCUを事前設定
- 予測可能なトラフィックでコスト最適
- Auto Scaling設定が必要
```

### オンプレミスでの同等構成

#### 1. Function as a Service (FaaS)のオンプレミス実装

**OpenFaaS:**
```yaml
# docker-compose.yml
version: "3.3"
services:
  gateway:
    image: openfaas/gateway:latest
    ports:
      - 8080:8080
    environment:
      functions_provider_url: "http://faas-swarm:8080/"
    deploy:
      placement:
        constraints: [node.role == manager]

  faas-swarm:
    image: openfaas/faas-swarm:latest
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
    deploy:
      placement:
        constraints: [node.role == manager]
```

**関数デプロイ:**
```yaml
# stack.yml
provider:
  name: openfaas
  gateway: http://127.0.0.1:8080

functions:
  get-user:
    lang: node18
    handler: ./get-user
    image: myregistry/get-user:latest
    environment:
      DB_HOST: mongodb://mongo:27017
    limits:
      memory: 128Mi
    requests:
      memory: 64Mi
```

**課題:**
- 物理リソースの制約（スケーリング限界）
- コールドスタート対策が必要
- 運用負荷が高い

**Knative (Kubernetes上):**
```yaml
# service.yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: user-service
spec:
  template:
    spec:
      containers:
      - image: gcr.io/myproject/user-service
        ports:
        - containerPort: 8080
        env:
        - name: DB_CONNECTION
          value: "mongodb://mongo:27017"
        resources:
          limits:
            memory: "256Mi"
            cpu: "200m"
      containerConcurrency: 100
      timeoutSeconds: 300
```

**オートスケーリング:**
```yaml
apiVersion: autoscaling.knative.dev/v1alpha1
kind: PodAutoscaler
metadata:
  name: user-service-autoscaler
spec:
  scaleTargetRef:
    apiVersion: serving.knative.dev/v1
    kind: Service
    name: user-service
  minScale: 0           # ゼロスケール可能
  maxScale: 100
  targetUtilizationPercentage: 70
```

#### 2. APIゲートウェイのオンプレミス実装

**Kong Gateway:**
```yaml
# kong.yml
_format_version: "3.0"

services:
- name: user-service
  url: http://user-function:8080
  routes:
  - name: user-route
    paths:
    - /users
    methods:
    - GET
    - POST
  plugins:
  - name: rate-limiting
    config:
      minute: 1000
      hour: 10000
  - name: jwt
    config:
      key_claim_name: iss
  - name: cors
    config:
      origins:
      - '*'
```

**Nginx API Gateway:**
```nginx
# /etc/nginx/nginx.conf
http {
    # Rate Limiting
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=100r/s;

    # バックエンド定義
    upstream user_service {
        server user-function:8080;
    }

    server {
        listen 443 ssl;
        server_name api.example.com;

        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;

        location /users {
            limit_req zone=api_limit burst=20 nodelay;

            # JWT検証（lua-resty-jwt使用）
            access_by_lua_block {
                local jwt = require "resty.jwt"
                local validators = require "resty.jwt-validators"

                local token = ngx.var.http_authorization
                local jwt_obj = jwt:verify(secret, token)

                if not jwt_obj["verified"] then
                    ngx.status = 401
                    ngx.say("Unauthorized")
                    ngx.exit(ngx.HTTP_UNAUTHORIZED)
                end
            }

            proxy_pass http://user_service;
            proxy_set_header Host $host;
        }
    }
}
```

#### 3. NoSQLデータベース

**MongoDB:**
```javascript
// シャーディング設定
sh.enableSharding("myapp")

sh.shardCollection(
    "myapp.users",
    { userId: "hashed" }
)

// レプリカセット
rs.initiate({
    _id: "myReplSet",
    members: [
        { _id: 0, host: "mongo1:27017" },
        { _id: 1, host: "mongo2:27017" },
        { _id: 2, host: "mongo3:27017" }
    ]
})
```

**Cassandra:**
```cql
-- キースペース作成
CREATE KEYSPACE myapp
WITH replication = {
    'class': 'NetworkTopologyStrategy',
    'datacenter1': 3
};

-- テーブル作成
CREATE TABLE myapp.users (
    user_id UUID PRIMARY KEY,
    name TEXT,
    email TEXT,
    created_at TIMESTAMP
);

-- セカンダリインデックス
CREATE INDEX ON myapp.users (email);
```

### オンプレミスとAWSの比較

| 項目 | オンプレミス（OpenFaaS/K8s） | AWS Serverless |
|------|---------------------------|----------------|
| **初期コスト** | 高額<br>Kubernetes クラスタ構築<br>数百万円 | ゼロ<br>従量課金のみ |
| **スケーリング** | 物理リソースに制約<br>ノード追加に時間 | ほぼ無制限<br>自動スケール |
| **運用負荷** | 高い<br>K8s管理、関数デプロイ、監視 | 低い<br>マネージドサービス |
| **コールドスタート** | 対策必要<br>最小レプリカ数を維持 | 対策必要<br>Provisioned Concurrency |
| **コスト（低トラフィック）** | 高い<br>常にクラスタ稼働 | 低い<br>使用時のみ課金 |

### コスト比較（月間100万リクエスト）

**オンプレミス（Kubernetes + OpenFaaS）:**
- Kubernetes クラスタ（3ノード）: 約15万円/月
- ロードバランサー: 約3万円/月
- MongoDB（レプリカセット）: 約10万円/月
- 運用コスト: 約20万円/月
- **合計: 約48万円/月**

**AWS Serverless:**
- Lambda（100万リクエスト、平均200ms、512MB）: 約350円/月
- API Gateway: 約3,500円/月
- DynamoDB（オンデマンド）: 約1,250円/月
- S3 + CloudFront: 約1,000円/月
- **合計: 約6,100円/月**

**コスト削減率: 約98%**

## まとめ

サーバーレスアーキテクチャーは、スタートアップや不定期トラフィックのアプリケーションに最適です。

**メリット:**
- **初期投資ゼロ**
- **完全な従量課金**（使わなければコストゼロ）
- **自動スケーリング**
- **運用負荷最小**

**ベストプラクティス:**
1. Lambda関数は単一責任（1関数1機能）
2. DynamoDBはシングルテーブル設計
3. CloudFrontでキャッシュ活用
4. X-Rayでトレーシング
5. CloudWatch Logsで集中ログ管理

**注意点:**
- コールドスタート（重要な関数はProvisioned Concurrency）
- ベンダーロックイン（AWS依存）
- デバッグの難しさ（ローカル実行環境を整備）
