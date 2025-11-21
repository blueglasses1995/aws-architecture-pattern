# パターン12: グローバルコンテンツ配信（マルチリージョン）

## 問題

グローバル展開するSaaSサービスで、世界中のユーザーに低レイテンシでサービスを提供します。

**要件:**
- 全世界のユーザーにレイテンシ100ms以内
- 動的コンテンツと静的コンテンツの両方
- マルチリージョン展開（米国、欧州、アジア）
- リージョン障害時の自動フェイルオーバー
- セッション維持

## 推奨アーキテクチャー

```
[CloudFront]
├─ Edge Location（200+拠点）
├─ Origin Shield（リージョン毎）
└─ Lambda@Edge
    ↓
[米国リージョン]    [欧州リージョン]    [アジアリージョン]
├─ ALB            ├─ ALB            ├─ ALB
├─ EC2            ├─ EC2            ├─ EC2
└─ RDS            └─ RDS            └─ RDS
    ↓
[Global Accelerator] (低レイテンシルーティング)
[Route 53] (Geolocation / Latency Routing)
[DynamoDB Global Tables] (グローバルDB)
```

### 使用するAWSサービス:
- **CloudFront**: グローバルCDN
- **Global Accelerator**: 最適ルーティング
- **Route 53**: GeoDNS
- **DynamoDB Global Tables**: マルチリージョンDB
- **Aurora Global Database**: グローバルRDS
- **S3 Cross-Region Replication**: ストレージレプリケーション

## 解説

### なぜこのアーキテクチャーなのか

#### 1. CloudFront vs Global Accelerator

| 機能 | CloudFront | Global Accelerator |
|------|-----------|-------------------|
| **用途** | 静的/動的コンテンツキャッシュ | TCP/UDPトラフィック高速化 |
| **レイヤー** | L7（HTTP/HTTPS） | L4（TCP/UDP） |
| **キャッシュ** | あり | なし |
| **IP** | 変動 | 固定（2つのAnycast IP） |
| **最適化** | コンテンツキャッシュ | AWSバックボーン経由ルーティング |

**使い分け:**
- 静的コンテンツ → CloudFront
- 動的API → CloudFront + Global Accelerator
- ゲーム、WebSocket → Global Accelerator

#### 2. DynamoDB Global Tables

**マルチリージョン自動レプリケーション:**
```
[米国リージョン]
DynamoDB Table
    ⇅ 双方向レプリケーション
[欧州リージョン]
DynamoDB Table
    ⇅
[アジアリージョン]
DynamoDB Table
```

**レプリケーションラグ: 通常1秒未満**

**設定例:**
```bash
aws dynamodb create-global-table \
  --global-table-name Users \
  --replication-group \
    RegionName=us-east-1 \
    RegionName=eu-west-1 \
    RegionName=ap-northeast-1
```

**競合解決: Last Writer Wins（最後の書き込みが優先）**

### オンプレミスでの同等構成

**マルチリージョンDC:**
- 米国DC: 初期投資1億円
- 欧州DC: 初期投資1億円
- アジアDC: 初期投資1億円
- 国際専用線: 500万円/月
- **合計: 約3億円 + 運用費1,000万円/月**

**AWSの場合: 約200万円/月（運用費込み）**

## まとめ

グローバル展開では、AWSのマネージドサービスで大幅なコスト削減が可能です。

**ベストプラクティス:**
1. CloudFront + Global Accelerator併用
2. DynamoDB Global Tablesでグローバルデータ同期
3. Aurora Global Databaseでリージョン間レプリケーション
4. Route 53 Geolocation/Latency Routingで最適ルーティング
