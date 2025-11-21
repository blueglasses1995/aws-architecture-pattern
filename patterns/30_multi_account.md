# パターン30: マルチアカウント管理

## 問題

開発・ステージング・本番環境を分離し、組織全体でAWSを管理したい。

## 推奨アーキテクチャー

```
[AWS Organizations]
├─ マスターアカウント
│   └─ 請求統合
├─ OU: Production
│   ├─ 本番アカウント（東京）
│   └─ 本番アカウント（大阪）
├─ OU: Development
│   ├─ 開発アカウント
│   └─ テストアカウント
├─ OU: Shared Services
│   ├─ ログアーカイブアカウント
│   └─ セキュリティアカウント
└─ OU: Sandbox
    └─ 検証アカウント

[Control Tower]
├─ ガードレール（強制ルール）
├─ アカウント自動プロビジョニング
└─ 集中ログ管理
```

### Organizations設定

```bash
# Organization作成
aws organizations create-organization \
  --feature-set ALL

# OU作成
aws organizations create-organizational-unit \
  --parent-id r-xxxx \
  --name Production

# アカウント作成
aws organizations create-account \
  --email prod@example.com \
  --account-name "Production Account"
```

### Service Control Policy（SCP）

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Action": [
        "ec2:RunInstances"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "ec2:InstanceType": [
            "t3.micro",
            "t3.small",
            "t3.medium"
          ]
        }
      }
    }
  ]
}
```

**開発アカウントで大型インスタンス起動を禁止**

### クロスアカウントアクセス

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:role/DevRole"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "unique-external-id"
        }
      }
    }
  ]
}
```

### 統合ログ管理

```
全アカウント
    ↓ CloudTrail
[ログアーカイブアカウント S3]
    ↓
[Athena]（ログ分析）
[GuardDuty]（脅威検知）
```

## ベストプラクティス

**1. アカウント分離:**
- 本番・開発・共有サービスで分離
- 環境毎に完全に独立

**2. SCPで制御:**
- リージョン制限
- サービス制限
- インスタンスタイプ制限

**3. 集中ログ管理:**
- CloudTrail全アカウント統合
- GuardDutyで脅威検知
- Security Hub統合

**4. 請求統合:**
- 一括請求で管理簡素化
- タグベースでコスト配分

## まとめ

Organizations + Control Towerで大規模組織のAWS管理を実現。

**メリット:**
- 環境完全分離（セキュリティ向上）
- 一括請求（コスト管理簡素化）
- ガードレール（ポリシー強制）
- アカウント自動プロビジョニング
