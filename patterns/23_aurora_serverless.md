# パターン23: Aurora Serverlessでのコスト最適化

## 問題

開発環境や不定期アクセスのDBで、常時稼働のコストを削減したい。

## 推奨アーキテクチャー

```
[Aurora Serverless v2]
├─ 自動スケーリング（0.5 ACU 〜 128 ACU）
├─ アクセスなし時は最小ACUまで縮小
├─ アクセス増加時は自動拡張
└─ 数秒でスケーリング完了
```

### Aurora Serverless v2 設定例

```bash
aws rds create-db-cluster \
  --db-cluster-identifier mydb-serverless \
  --engine aurora-postgresql \
  --engine-version 14.6 \
  --master-username admin \
  --master-user-password password \
  --serverless-v2-scaling-configuration \
    MinCapacity=0.5,MaxCapacity=16
```

## コスト比較

**通常のRDS（db.r5.large）:**
- 月額: 約$200（24時間稼働）

**Aurora Serverless v2:**
- 開発環境（8時間/日利用）: 約$40/月
- **80%コスト削減**

## まとめ

不定期アクセスのDBはServerlessで大幅コスト削減。

**適用シーン:**
- 開発/テスト環境
- 定期バッチ処理用DB
- 営業時間のみアクセスされるシステム
