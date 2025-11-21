# パターン11: ディザスタリカバリ（DR）構成

## 問題

本番環境が災害で停止した場合に備えて、DR環境を構築します。
RPO（目標復旧時点）1時間、RTO（目標復旧時間）4時間を満たす構成を設計してください。

**要件:**
- RPO: 1時間（最大1時間分のデータ損失許容）
- RTO: 4時間（4時間以内にサービス復旧）
- 通常時のDR環境コストを最小化
- 本番リージョン: 東京、DRリージョン: 大阪
- データベース、ファイル、設定の全てをバックアップ

## 推奨アーキテクチャー

```
[東京リージョン - 本番環境]
├─ EC2 (Auto Scaling)
├─ RDS Multi-AZ
├─ S3 (アプリデータ)
└─ Route 53 (Primary)
    ↓ レプリケーション
[大阪リージョン - DR環境]
├─ AMI (EC2のスナップショット)
├─ RDS リードレプリカ (クロスリージョン)
├─ S3 (クロスリージョンレプリケーション)
└─ Route 53 (Failover)
```

### 使用するAWSサービス:
- **S3 Cross-Region Replication**: S3データレプリケーション
- **RDS Cross-Region Read Replica**: DBレプリケーション
- **AMI**: EC2イメージバックアップ
- **AWS Backup**: 統合バックアップ
- **Route 53 Health Check**: ヘルスチェック
- **CloudFormation**: インフラコード化

## 解説

### なぜこのアーキテクチャーなのか

#### 1. DR戦略の4つのパターン

| パターン | RPO | RTO | コスト | 説明 |
|---------|-----|-----|--------|------|
| **Backup & Restore** | 時間単位 | 数時間〜数日 | ★ | バックアップから復元 |
| **Pilot Light** | 分単位 | 数時間 | ★★ | 最小限のDR環境を常時稼働 |
| **Warm Standby** | 秒単位 | 数分 | ★★★ | 縮小版を常時稼働 |
| **Multi-Site Active/Active** | ほぼゼロ | ほぼゼロ | ★★★★ | 両リージョンで完全稼働 |

**今回の要件（RPO 1時間、RTO 4時間）: Pilot Light が最適**

#### 2. Pilot Light 構成の詳細

**平常時:**
```
東京リージョン（本番稼働）:
├─ EC2: Auto Scaling（稼働中）
├─ RDS: Multi-AZ（稼働中）
└─ S3: データ保存（稼働中）

大阪リージョン（最小限）:
├─ AMI: 最新イメージを保持（課金なし）
├─ RDS Read Replica: 継続レプリケーション（課金あり）
└─ S3: CRR でレプリケーション（課金あり）
```

**災害発生時:**
```
1. RDS Read Replica を昇格（数分）
2. AMI から EC2 を起動（10-20分）
3. Route 53 で大阪にフェイルオーバー（自動）
4. Auto Scaling で必要台数まで拡張（5-10分）
5. 動作確認（1-2時間）

合計: 約2-3時間（RTO 4時間以内）
```

#### 3. S3 クロスリージョンレプリケーション

**設定例:**
```json
{
  "Role": "arn:aws:iam::123456789012:role/s3-replication-role",
  "Rules": [
    {
      "Status": "Enabled",
      "Priority": 1,
      "Filter": {
        "Prefix": ""
      },
      "Destination": {
        "Bucket": "arn:aws:s3:::dr-bucket-osaka",
        "ReplicationTime": {
          "Status": "Enabled",
          "Time": {
            "Minutes": 15
          }
        },
        "Metrics": {
          "Status": "Enabled",
          "EventThreshold": {
            "Minutes": 15
          }
        },
        "StorageClass": "STANDARD_IA"
      },
      "DeleteMarkerReplication": {
        "Status": "Enabled"
      }
    }
  ]
}
```

**S3 Replication Time Control (RTC):**
- 99.99%のオブジェクトを15分以内にレプリケーション
- SLA付きレプリケーション
- 追加コスト: ~$0.015/GB

#### 4. RDS クロスリージョンリードレプリカ

**作成コマンド:**
```bash
aws rds create-db-instance-read-replica \
  --db-instance-identifier mydb-replica-osaka \
  --source-db-instance-identifier arn:aws:rds:ap-northeast-1:123456789012:db:mydb-tokyo \
  --db-instance-class db.r5.large \
  --region ap-northeast-3  # 大阪リージョン
```

**昇格（Promote）:**
```bash
# 災害時にRead Replicaを独立したDBに昇格
aws rds promote-read-replica \
  --db-instance-identifier mydb-replica-osaka \
  --region ap-northeast-3
```

**注意点:**
- 昇格には5-15分かかる
- 昇格後は元のDBとの接続が切断される
- Multi-AZに自動変換可能

#### 5. Route 53 フェイルオーバー

**ヘルスチェック:**
```json
{
  "Type": "HTTPS",
  "ResourcePath": "/health",
  "FullyQualifiedDomainName": "www.example.com",
  "Port": 443,
  "RequestInterval": 30,
  "FailureThreshold": 3,
  "MeasureLatency": true,
  "EnableSNI": true
}
```

**フェイルオーバーレコード:**
```json
{
  "Name": "www.example.com",
  "Type": "A",
  "SetIdentifier": "Tokyo-Primary",
  "Failover": "PRIMARY",
  "AliasTarget": {
    "HostedZoneId": "Z2M4EHUR26P7ZW",
    "DNSName": "tokyo-alb-12345.ap-northeast-1.elb.amazonaws.com",
    "EvaluateTargetHealth": true
  },
  "HealthCheckId": "hc-tokyo-12345"
}

{
  "Name": "www.example.com",
  "Type": "A",
  "SetIdentifier": "Osaka-Secondary",
  "Failover": "SECONDARY",
  "AliasTarget": {
    "HostedZoneId": "Z1YSHQZHG15GKL",
    "DNSName": "osaka-alb-67890.ap-northeast-3.elb.amazonaws.com",
    "EvaluateTargetHealth": false
  }
}
```

### オンプレミスでの同等構成

#### 1. 遠隔地DCでのDR環境

**構成:**
```
東京DC（本番）:
├─ アプリサーバー: 10台稼働
├─ DBサーバー: Master-Slave構成
├─ ストレージ: SAN（10TB）
└─ 専用線 → 大阪DC

大阪DC（DR）:
├─ アプリサーバー: 最小2台（待機）
├─ DBサーバー: レプリケーション受信
├─ ストレージ: SAN（10TB、レプリケーション先）
└─ 専用線 ← 東京DC
```

**コスト:**
- 東京DC初期投資: 5,000万円
- 大阪DC初期投資: 3,000万円
- 専用線: 150万円/月
- 両DC運用: 200万円/月
- **合計: 約350万円/月**

#### 2. データレプリケーション

**SAN レプリケーション（Dell EMC VPLEX）:**
```
東京DC SAN
  ↓ 同期/非同期レプリケーション
大阪DC SAN
```

**コスト:**
- VPLEX ライセンス: 2,000万円
- 年間保守: 400万円/年

**データベースレプリケーション（Oracle DataGuard）:**
```sql
-- プライマリDB（東京）
ALTER SYSTEM SET LOG_ARCHIVE_DEST_2=
  'SERVICE=osaka_standby ASYNC VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)';

-- スタンバイDB（大阪）
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT;
```

**RPO:** 数分〜数十分（非同期の場合）

#### 3. フェイルオーバー手順（手動）

```
1. 障害検知（監視ツール/人手）: 10-30分
2. 意思決定（経営判断）: 30分〜2時間
3. DNSレコード変更: 5-10分
4. DB昇格作業:
   - ログ適用確認: 10-30分
   - 昇格コマンド実行: 5-10分
5. アプリサーバー起動: 10-30分
6. 動作確認: 1-3時間

合計: 3-7時間（RTO達成困難な場合も）
```

### オンプレミスとAWSの比較

| 項目 | オンプレミス | AWS |
|------|------------|-----|
| **DR構築期間** | 6-12ヶ月<br>DC契約、機器調達、設置 | 数日<br>レプリケーション設定のみ |
| **初期投資** | 超高額（数億円）<br>2つのDC分の機器 | 低額<br>設定費用のみ |
| **平常時コスト** | 高額（350万円/月）<br>待機系も維持費 | 中程度（50万円/月）<br>レプリケーションのみ |
| **フェイルオーバー** | 手動<br>3-7時間 | 半自動<br>2-3時間 |
| **テスト** | 困難<br>本番影響リスク | 容易<br>いつでも実施可能 |

### コスト比較

**オンプレミス:**
- 初期投資償却（5年）: 約130万円/月
- DR環境維持: 約150万円/月
- 専用線: 約150万円/月
- **合計: 約430万円/月**

**AWS:**
- RDS Read Replica: 約10万円/月
- S3 CRR: 約5万円/月
- AMIストレージ: 約1万円/月
- Route 53: 約1,000円/月
- **合計: 約16万円/月**

**DR環境のコスト削減率: 約96%**

## まとめ

AWSのDR構成は、オンプレミスと比較して圧倒的に低コストで実現できます。

**ベストプラクティス:**
1. 要件に応じたDR戦略を選択（Pilot Light推奨）
2. S3 CRRで自動レプリケーション
3. RDS クロスリージョンリードレプリカ
4. Route 53 ヘルスチェックで自動フェイルオーバー
5. CloudFormation でDR環境を即座に構築
6. 定期的なDR訓練（年2回以上推奨）

**DR訓練の重要性:**
- 年2回以上のフェイルオーバー訓練
- 手順書の更新
- RTO/RPOの検証
- チーム教育
