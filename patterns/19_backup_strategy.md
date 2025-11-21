# パターン19: 統合バックアップ戦略

## 問題

複数のAWSリソース（EC2、RDS、EFS、DynamoDB等）を統合的にバックアップ管理したい。

## 推奨アーキテクチャー

```
[AWS Backup]
├─ バックアッププラン
│   ├─ 日次バックアップ（保持7日）
│   ├─ 週次バックアップ（保持4週）
│   └─ 月次バックアップ（保持12ヶ月）
├─ リソース選択（タグベース）
│   ├─ EC2（EBS スナップショット）
│   ├─ RDS（自動スナップショット）
│   ├─ EFS（バックアップ）
│   ├─ DynamoDB（ポイントインタイムリカバリ）
│   └─ S3（バージョニング）
└─ クロスリージョンコピー
```

### 使用するAWSサービス:
- **AWS Backup**: 統合バックアップ管理
- **EBS Snapshots**: EC2ボリュームバックアップ
- **RDS Automated Backups**: DBバックアップ
- **DynamoDB PITR**: ポイントインタイムリカバリ

## 解説

**バックアッププラン:**
```json
{
  "BackupPlanName": "daily-backup-plan",
  "Rules": [
    {
      "RuleName": "DailyBackups",
      "TargetBackupVaultName": "Default",
      "ScheduleExpression": "cron(0 5 * * ? *)",
      "StartWindowMinutes": 60,
      "CompletionWindowMinutes": 120,
      "Lifecycle": {
        "DeleteAfterDays": 7
      }
    },
    {
      "RuleName": "MonthlyBackups",
      "TargetBackupVaultName": "Default",
      "ScheduleExpression": "cron(0 5 1 * ? *)",
      "Lifecycle": {
        "MoveToColdStorageAfterDays": 30,
        "DeleteAfterDays": 365
      }
    }
  ]
}
```

**タグベースの自動バックアップ:**
```json
{
  "SelectionName": "production-resources",
  "IamRoleArn": "arn:aws:iam::123456789012:role/AWSBackupRole",
  "Resources": ["*"],
  "ListOfTags": [
    {
      "ConditionType": "STRINGEQUALS",
      "ConditionKey": "Environment",
      "ConditionValue": "Production"
    },
    {
      "ConditionType": "STRINGEQUALS",
      "ConditionKey": "BackupEnabled",
      "ConditionValue": "true"
    }
  ]
}
```

### 3-2-1 バックアップルール

```
3つのコピー: 本番 + バックアップ2つ
2つのメディア: EBS + S3
1つはオフサイト: クロスリージョンコピー
```

### オンプレミス

**Veeam Backup & Replication:**
- ライセンス: 数百万円
- バックアップサーバー運用
- ストレージ管理

**NetBackup:**
- 高額なライセンス
- 複雑な設定

## まとめ

AWS Backupで全リソースを統合管理できます。

**ベストプラクティス:**
1. タグベースで自動バックアップ
2. 3-2-1ルールを遵守
3. 定期的なリストアテスト
4. クロスリージョンコピーでDR対策
