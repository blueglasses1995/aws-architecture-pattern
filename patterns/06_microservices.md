# パターン6: マイクロサービスアーキテクチャ

## 問題

大規模ECサイトを、複数チームで独立して開発・デプロイできるアーキテクチャーにリファクタリングします。
以下の要件を満たすマイクロサービスアーキテクチャーを設計してください。

**要件:**
- ユーザー管理、商品カタログ、注文処理、決済など複数のサービス
- 各サービスを独立してデプロイ可能
- サービス間の疎結合
- コンテナベースの運用
- 自動スケーリングと高可用性

## 推奨アーキテクチャー

```
[ユーザー]
    ↓
[ALB / API Gateway]
    ↓
[Amazon ECS / EKS]
├─ ユーザーサービス (Container)
├─ 商品サービス (Container)
├─ 注文サービス (Container)
└─ 決済サービス (Container)
    ↓
[各サービス専用DB]
├─ RDS (PostgreSQL)
├─ DynamoDB
└─ ElastiCache
    ↓
[SQS / SNS / EventBridge]
（サービス間非同期通信）
```

### 使用するAWSサービス:
- **ECS Fargate / EKS**: コンテナオーケストレーション
- **ECR**: Dockerイメージレジストリ
- **ALB**: サービスメッシュ用LB
- **RDS / DynamoDB**: サービス毎のDB
- **SQS / SNS / EventBridge**: 非同期メッセージング
- **App Mesh**: サービスメッシュ
- **X-Ray**: 分散トレーシング

## 解説

### なぜこのアーキテクチャーなのか

#### 1. モノリスからマイクロサービスへ

**モノリシックアーキテクチャーの課題:**
```
単一の巨大アプリケーション
├─ デプロイが困難（全体を停止）
├─ スケーリングが非効率（全体をスケール）
├─ 技術スタックが固定される
├─ チーム間の依存が高い
└─ 障害の影響範囲が大きい
```

**マイクロサービスの利点:**
```
小さな独立したサービス群
├─ 独立したデプロイ（他サービスに影響なし）
├─ 必要なサービスだけスケール
├─ サービス毎に最適な技術選択
├─ チームの自律性向上
└─ 障害の局所化
```

#### 2. ECS vs EKS の選択

**Amazon ECS (Elastic Container Service):**

**利点:**
- AWSネイティブ、シンプル
- Fargateで完全マネージド
- AWS統合が容易（IAM、CloudWatch等）

**設定例:**
```json
{
  "family": "user-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [
    {
      "name": "user-service",
      "image": "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/user-service:latest",
      "portMappings": [
        {
          "containerPort": 8080,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {"name": "DB_HOST", "value": "user-db.example.com"},
        {"name": "CACHE_HOST", "value": "redis.example.com"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/user-service",
          "awslogs-region": "ap-northeast-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

**Amazon EKS (Elastic Kubernetes Service):**

**利点:**
- Kubernetes標準、ポータビリティ
- 豊富なエコシステム
- マルチクラウド対応

**Deployment例:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: user-service
  template:
    metadata:
      labels:
        app: user-service
        version: v1
    spec:
      containers:
      - name: user-service
        image: 123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/user-service:v1.2.3
        ports:
        - containerPort: 8080
        env:
        - name: DB_HOST
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: host
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: user-service
spec:
  selector:
    app: user-service
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
```

#### 3. サービス間通信パターン

**A. 同期通信（REST API）:**
```
商品サービス → (HTTP) → 在庫サービス
```

**課題:**
- カスケード障害（在庫サービスが落ちると商品サービスも影響）
- レスポンスタイムの積み重ね

**対策:**
```javascript
// Circuit Breaker パターン（Node.js例）
const CircuitBreaker = require('opossum');

const options = {
  timeout: 3000,        // 3秒でタイムアウト
  errorThresholdPercentage: 50,  // エラー率50%で開く
  resetTimeout: 30000   // 30秒後に再試行
};

async function callInventoryService(productId) {
  const response = await fetch(`http://inventory-service/api/stock/${productId}`);
  return response.json();
}

const breaker = new CircuitBreaker(callInventoryService, options);

// 使用
try {
  const stock = await breaker.fire('product-123');
} catch (err) {
  // フォールバック処理
  return { available: false, message: 'Inventory service unavailable' };
}
```

**B. 非同期通信（メッセージキュー）:**
```
注文サービス → (SQS) → 決済サービス
                 ↓
              在庫サービス
```

**SQS使用例:**
```javascript
// 注文サービス: メッセージ送信
const AWS = require('aws-sdk');
const sqs = new AWS.SQS();

async function publishOrderCreated(order) {
  const params = {
    QueueUrl: 'https://sqs.ap-northeast-1.amazonaws.com/123456789012/orders',
    MessageBody: JSON.stringify({
      orderId: order.id,
      userId: order.userId,
      items: order.items,
      totalAmount: order.totalAmount
    }),
    MessageAttributes: {
      eventType: {
        DataType: 'String',
        StringValue: 'OrderCreated'
      }
    }
  };

  await sqs.sendMessage(params).promise();
}

// 決済サービス: メッセージ受信
async function processOrders() {
  const params = {
    QueueUrl: 'https://sqs.ap-northeast-1.amazonaws.com/123456789012/orders',
    MaxNumberOfMessages: 10,
    WaitTimeSeconds: 20  // Long Polling
  };

  const result = await sqs.receiveMessage(params).promise();

  for (const message of result.Messages || []) {
    const order = JSON.parse(message.Body);

    try {
      // 決済処理
      await processPayment(order);

      // 成功したらメッセージ削除
      await sqs.deleteMessage({
        QueueUrl: params.QueueUrl,
        ReceiptHandle: message.ReceiptHandle
      }).promise();
    } catch (err) {
      // エラー時はメッセージを再処理（自動的にキューに戻る）
      console.error('Payment failed:', err);
    }
  }
}
```

**C. イベント駆動（EventBridge）:**
```yaml
# EventBridgeルール
Rules:
  OrderCreatedRule:
    EventPattern:
      source:
        - order.service
      detail-type:
        - OrderCreated
    Targets:
      - Arn: arn:aws:lambda:ap-northeast-1:123456789012:function:SendEmail
      - Arn: arn:aws:sqs:ap-northeast-1:123456789012:inventory-queue
      - Arn: arn:aws:lambda:ap-northeast-1:123456789012:function:UpdateAnalytics
```

#### 4. サービスメッシュ（AWS App Mesh）

**App Meshの利点:**
- サービス間通信の可視化
- トラフィック管理（カナリアデプロイ、A/Bテスト）
- リトライ、タイムアウトの統一管理

**Virtual Node定義:**
```json
{
  "meshName": "ecommerce-mesh",
  "spec": {
    "listeners": [
      {
        "portMapping": {
          "port": 8080,
          "protocol": "http"
        },
        "healthCheck": {
          "protocol": "http",
          "path": "/health",
          "intervalMillis": 5000,
          "timeoutMillis": 2000,
          "unhealthyThreshold": 3,
          "healthyThreshold": 2
        }
      }
    ],
    "serviceDiscovery": {
      "awsCloudMap": {
        "namespaceName": "ecommerce.local",
        "serviceName": "user-service"
      }
    },
    "backends": [
      {
        "virtualService": {
          "virtualServiceName": "order-service.ecommerce.local"
        }
      }
    ]
  },
  "virtualNodeName": "user-service-vn"
}
```

### オンプレミスでの同等構成

#### 1. Kubernetes クラスタ

**マルチマスター構成:**
```
[Control Plane]
├─ kube-apiserver × 3
├─ kube-scheduler × 3
├─ kube-controller-manager × 3
└─ etcd × 3 (クラスタ構成)

[Worker Nodes]
├─ Node 1-10 (コンテナ実行)
└─ kubelet, kube-proxy
```

**必要なハードウェア:**
- マスターノード: 3台（vCPU 4, RAM 16GB）
- ワーカーノード: 10台以上（vCPU 8, RAM 32GB）
- ストレージ: Ceph / GlusterFS（分散ストレージ）

**Kubeadm初期化:**
```bash
# マスターノード初期化
kubeadm init --control-plane-endpoint="lb.k8s.local:6443" \
  --upload-certs \
  --pod-network-cidr=10.244.0.0/16

# CNI (Calico) インストール
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# ワーカーノード参加
kubeadm join lb.k8s.local:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

#### 2. サービスメッシュ（Istio）

**Istio インストール:**
```bash
# Istioctl インストール
curl -L https://istio.io/downloadIstio | sh -
cd istio-1.20.0
export PATH=$PWD/bin:$PATH

# Istio デプロイ
istioctl install --set profile=production

# サイドカー自動注入
kubectl label namespace production istio-injection=enabled
```

**Virtual Service（トラフィック管理）:**
```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: user-service
spec:
  hosts:
  - user-service
  http:
  - match:
    - headers:
        x-canary:
          exact: "true"
    route:
    - destination:
        host: user-service
        subset: v2
      weight: 100
  - route:
    - destination:
        host: user-service
        subset: v1
      weight: 90
    - destination:
        host: user-service
        subset: v2
      weight: 10  # 10%をv2に
```

**Destination Rule:**
```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: user-service
spec:
  host: user-service
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 50
        http2MaxRequests: 100
    loadBalancer:
      simple: LEAST_REQUEST
    outlierDetection:
      consecutiveErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
```

#### 3. メッセージキュー（RabbitMQ / Kafka）

**RabbitMQ クラスタ:**
```bash
# docker-compose.yml
version: '3.8'
services:
  rabbitmq1:
    image: rabbitmq:3-management
    hostname: rabbit1
    environment:
      RABBITMQ_ERLANG_COOKIE: 'secret_cookie'
      RABBITMQ_DEFAULT_USER: admin
      RABBITMQ_DEFAULT_PASS: password
    volumes:
      - rabbitmq1_data:/var/lib/rabbitmq

  rabbitmq2:
    image: rabbitmq:3-management
    hostname: rabbit2
    environment:
      RABBITMQ_ERLANG_COOKIE: 'secret_cookie'
    depends_on:
      - rabbitmq1
    volumes:
      - rabbitmq2_data:/var/lib/rabbitmq

volumes:
  rabbitmq1_data:
  rabbitmq2_data:
```

**Kafka クラスタ:**
```yaml
# docker-compose.yml
version: '3'
services:
  zookeeper:
    image: confluentinc/cp-zookeeper:latest
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181

  kafka1:
    image: confluentinc/cp-kafka:latest
    depends_on:
      - zookeeper
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka1:9092

  kafka2:
    image: confluentinc/cp-kafka:latest
    depends_on:
      - zookeeper
    environment:
      KAFKA_BROKER_ID: 2
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka2:9092
```

### オンプレミスとAWSの比較

| 項目 | オンプレミス（Kubernetes） | AWS ECS/EKS |
|------|-------------------------|-------------|
| **初期構築** | 非常に複雑<br>クラスタ構築、ネットワーク設定 | 簡単<br>数クリックで起動 |
| **運用負荷** | 高い<br>マスター管理、etcd管理、アップグレード | 低い<br>マネージドコントロールプレーン |
| **コスト（小規模）** | 高い<br>最小構成でも数百万円 | 低い<br>使った分だけ |
| **スケーラビリティ** | 物理制約あり<br>ノード追加に時間 | ほぼ無制限<br>Fargate で自動 |
| **サービスメッシュ** | Istio (複雑な運用) | App Mesh (マネージド) |

### コスト比較（10マイクロサービス、各3レプリカ）

**オンプレミス（Kubernetes）:**
- サーバー（20台）: 2,000万円 ÷ 36ヶ月 = 約55万円/月
- ストレージ（Ceph）: 500万円 ÷ 36ヶ月 = 約14万円/月
- ネットワーク機器: 300万円 ÷ 36ヶ月 = 約8万円/月
- データセンター: 約20万円/月
- 運用コスト: 約100万円/月（2-3名）
- **合計: 約197万円/月**

**AWS ECS Fargate:**
- Fargate（0.25 vCPU, 0.5GB × 30コンテナ）: 約3万円/月
- ALB: 約0.3万円/月
- RDS/DynamoDB: 約15万円/月
- SQS/SNS: 約0.5万円/月
- **合計: 約18.8万円/月**

**コスト削減率: 約90%**

## まとめ

マイクロサービスアーキテクチャーは、大規模で複雑なアプリケーションに最適です。

**AWSでの利点:**
- **ECS/EKSで簡単にコンテナ運用**
- **Fargateでサーバー管理不要**
- **マネージドサービスで運用負荷削減**
- **柔軟なスケーリング**

**ベストプラクティス:**
1. サービスは小さく、単一責任で設計
2. サービス毎に独立したデータベース
3. 非同期通信を優先（SQS/EventBridge）
4. サービスメッシュで可視化と制御
5. X-Rayで分散トレーシング
6. CI/CDパイプラインで自動デプロイ
