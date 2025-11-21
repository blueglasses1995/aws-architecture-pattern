# パターン17: S3ライフサイクル管理

## 問題

大量のログファイルをS3に保存していますが、ストレージコストが増大しています。

## 推奨アーキテクチャー

```
[アプリケーション]
    ↓ アップロード
[S3 Standard]（最初の30日）
    ↓ 自動移行
[S3 Standard-IA]（31-90日）
    ↓ 自動移行
[S3 Glacier Instant Retrieval]（91-365日）
    ↓ 自動移行
[S3 Glacier Deep Archive]（366日以降）
    ↓ 自動削除
削除（7年後）
```

### ライフサイクルポリシー例

```json
{
  "Rules": [
    {
      "Id": "log-lifecycle",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "logs/"
      },
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 90,
          "StorageClass": "GLACIER_IR"
        },
        {
          "Days": 365,
          "StorageClass": "DEEP_ARCHIVE"
        }
      ],
      "Expiration": {
        "Days": 2555
      }
    }
  ]
}
```

## ストレージクラス比較

| クラス | 料金/GB/月 | 取り出し時間 | 用途 |
|--------|-----------|------------|------|
| **Standard** | $0.025 | 即座 | 頻繁アクセス |
| **Standard-IA** | $0.014 | 即座 | 月1回程度 |
| **Glacier IR** | $0.005 | ミリ秒 | 四半期1回 |
| **Glacier Flexible** | $0.004 | 1-5分/3-5時間 | 年1回程度 |
| **Deep Archive** | $0.002 | 12-48時間 | アーカイブ |

## コスト削減例

**ライフサイクル適用前:**
- 10TB（全てStandard）: $250/月

**ライフサイクル適用後:**
- 1TB Standard: $25/月
- 2TB Standard-IA: $28/月
- 3TB Glacier IR: $15/月
- 4TB Deep Archive: $8/月
- **合計: $76/月（70%削減）**

## まとめ

S3ライフサイクル管理で、ストレージコストを最大90%削減可能です。
