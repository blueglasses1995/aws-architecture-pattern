# パターン29: Redshiftデータウェアハウス

## 問題

大規模なデータ分析のためのデータウェアハウスを構築したい。

## 推奨アーキテクチャー

```
[データソース]
├─ RDS
├─ S3
└─ DynamoDB
    ↓
[Glue ETL]（データ変換）
    ↓
[S3]（ステージング）
    ↓
[Redshift]
├─ COPY コマンド（高速ロード）
├─ 列指向ストレージ
└─ 並列処理
    ↓
[QuickSight]（BI可視化）
[Tableau]
```

### Redshift COPY

```sql
-- S3からデータロード（並列処理で高速）
COPY sales
FROM 's3://my-bucket/sales-data/'
IAM_ROLE 'arn:aws:iam::123456789012:role/RedshiftRole'
FORMAT AS PARQUET
COMPUPDATE ON
STATUPDATE ON;
```

### 分析クエリ例

```sql
-- 日別売上集計
SELECT
    DATE_TRUNC('day', order_date) AS日付,
    SUM(amount) AS売上合計,
    COUNT(DISTINCT user_id) AS購入ユーザー数,
    AVG(amount) AS平均購入額
FROM sales
WHERE order_date >= '2024-01-01'
GROUP BY 1
ORDER BY 1 DESC;

-- 商品別ランキング
SELECT
    product_name,
    SUM(quantity) AS販売数,
    SUM(amount) AS売上額,
    RANK() OVER (ORDER BY SUM(amount) DESC) AS売上ランク
FROM sales
JOIN products ON sales.product_id = products.id
GROUP BY product_name
ORDER BY 売上額 DESC
LIMIT 100;
```

### Redshift Spectrum（S3直接クエリ）

```sql
-- 外部テーブル定義
CREATE EXTERNAL SCHEMA spectrum
FROM DATA CATALOG
DATABASE 'mydb'
IAM_ROLE 'arn:aws:iam::123456789012:role/RedshiftRole';

-- S3データを直接クエリ
SELECT
    year, month,
    COUNT(*) AS件数
FROM spectrum.weblogs
WHERE year = 2024
GROUP BY year, month;
```

## Redshift vs Athena

| 項目 | Redshift | Athena |
|------|---------|--------|
| タイプ | データウェアハウス | サーバーレスクエリ |
| コスト | 時間課金（常時稼働） | スキャン量課金 |
| 性能 | 高速（インデックス） | 中速（フルスキャン） |
| 用途 | 定期レポート | アドホッククエリ |

## まとめ

大規模データ分析にはRedshiftが最適。

**ベストプラクティス:**
1. 列指向ストレージで高速化
2. Distキー、Sortキーで最適化
3. S3からCOPYで高速ロード
4. Redshift Spectrumでコスト削減
