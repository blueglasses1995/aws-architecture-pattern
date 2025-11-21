# パターン8: データレイクアーキテクチャ

## 問題

複数のデータソース（Webログ、アプリログ、IoTセンサー、業務DB等）からデータを集約し、
データアナリストがSQL分析できる環境を構築します。

**要件:**
- 多様なデータ形式（JSON、CSV、Parquet等）
- ペタバイト級のスケーラビリティ
- 低コストなストレージ
- SQLでアドホッククエリ実行
- データカタログによるデータ管理

## 推奨アーキテクチャー

```
[データソース]
├─ Webログ → Kinesis Firehose
├─ アプリログ → Kinesis Firehose
├─ IoTデータ → IoT Core
└─ 業務DB → DMS / Glue
    ↓
[S3 Data Lake]
├─ Raw（生データ）
├─ Processed（加工データ）
└─ Curated（分析用）
    ↓
[Glue Crawler] → [Glue Data Catalog]
    ↓
[Athena / Redshift Spectrum]
    ↓
[QuickSight] (BI可視化)
```

### 使用するAWSサービス:
- **S3**: データレイクストレージ
- **Glue**: ETL、Data Catalog
- **Athena**: サーバーレスSQL
- **Kinesis Firehose**: ストリーミング取り込み
- **Lake Formation**: データレイク管理
- **QuickSight**: BI/可視化

## 解説

### なぜこのアーキテクチャーなのか

#### 1. データレイク vs データウェアハウス

**データウェアハウス（従来型）:**
```
特徴:
├─ 構造化データのみ
├─ スキーマオンライト（事前定義）
├─ 高コスト
└─ ETL処理が必要

用途: 定型レポート、BI分析
```

**データレイク:**
```
特徴:
├─ 全てのデータ形式（構造化/非構造化）
├─ スキーマオンリード（読み取り時に定義）
├─ 低コスト（S3）
└─ 生データを保持

用途: 探索的分析、機械学習、ログ分析
```

#### 2. S3をデータレイクとして使う理由

**S3の利点:**
```
耐久性: 99.999999999% (11 9's)
可用性: 99.99%
容量: 実質無制限
コスト: ~$0.023/GB/月（Standard）
        ~$0.004/GB/月（Glacier Deep Archive）
```

**データレイヤー設計:**
```
s3://my-data-lake/
├─ raw/              # 生データ（そのまま保存）
│   ├─ weblogs/
│   │   └─ year=2024/month=01/day=01/
│   ├─ applogs/
│   └─ iot/
├─ processed/        # クレンジング済み
│   ├─ weblogs_cleaned/
│   │   └─ year=2024/month=01/day=01/
│   └─ applogs_normalized/
└─ curated/          # 分析用（集計済み）
    ├─ user_daily_stats/
    │   └─ year=2024/month=01/
    └─ product_hourly_sales/
```

**パーティション設計:**
```python
# Hive形式パーティション
s3://bucket/table/year=2024/month=01/day=15/hour=10/data.parquet

# Athena クエリで自動的にパーティションプルーニング
SELECT * FROM weblogs
WHERE year = 2024 AND month = 1 AND day = 15
-- スキャンするデータ量が大幅に削減される
```

#### 3. Glue Crawlerとデータカタログ

**Glue Crawlerの仕組み:**
```
1. S3バケットをスキャン
2. データ形式を自動検出（JSON、CSV、Parquet等）
3. スキーマを推論
4. パーティションを検出
5. Data Catalogに登録
```

**Crawler設定例:**
```json
{
  "Name": "weblog-crawler",
  "Role": "arn:aws:iam::123456789012:role/GlueCrawlerRole",
  "DatabaseName": "analytics_db",
  "Targets": {
    "S3Targets": [
      {
        "Path": "s3://my-data-lake/processed/weblogs/",
        "Exclusions": [
          "**.tmp",
          "**_metadata"
        ]
      }
    ]
  },
  "SchemaChangePolicy": {
    "UpdateBehavior": "UPDATE_IN_DATABASE",
    "DeleteBehavior": "LOG"
  },
  "Schedule": {
    "ScheduleExpression": "cron(0 1 * * ? *)"
  }
}
```

**Data Catalogのメリット:**
```
一元管理:
├─ Athena
├─ Redshift Spectrum
├─ EMR
├─ Glue ETL
└─ QuickSight
   ↓ 全て同じカタログを参照
   統一されたスキーマ管理
```

#### 4. Athenaでのクエリ最適化

**基本クエリ:**
```sql
-- Athenaクエリ例
SELECT
    date_trunc('hour', timestamp) AS hour,
    endpoint,
    COUNT(*) AS request_count,
    AVG(response_time) AS avg_response_time,
    PERCENTILE_APPROX(response_time, 0.95) AS p95_response_time
FROM weblogs
WHERE year = 2024
  AND month = 1
  AND day = 15
GROUP BY 1, 2
ORDER BY 1 DESC, 3 DESC
```

**コスト最適化:**

**1. Parquet形式への変換:**
```python
# Glue ETL ジョブ
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

# JSON読み込み（圧縮）
df = spark.read.json('s3://bucket/raw/weblogs/')

# Parquet形式で保存（列指向、圧縮）
df.write \
    .mode('overwrite') \
    .partitionBy('year', 'month', 'day') \
    .parquet('s3://bucket/processed/weblogs/')
```

**効果:**
```
JSON (Gzip):     10 GB → スキャン料金: $0.05
Parquet (Snappy): 1 GB → スキャン料金: $0.005

約90%のコスト削減
```

**2. パーティションプルーニング:**
```sql
-- NG: 全データスキャン
SELECT * FROM weblogs
WHERE timestamp >= DATE '2024-01-15'

-- OK: パーティションのみスキャン
SELECT * FROM weblogs
WHERE year = 2024 AND month = 1 AND day >= 15
```

**3. 列選択:**
```sql
-- NG: 不要な列も取得
SELECT * FROM weblogs

-- OK: 必要な列のみ
SELECT user_id, endpoint, response_time FROM weblogs
```

#### 5. Lake Formationでのアクセス制御

**従来のS3アクセス制御の課題:**
```
IAMポリシー:
├─ バケット単位の制御
├─ パス単位の制御
└─ 細かい制御は困難
```

**Lake Formationの利点:**
```
データベース/テーブル単位の制御:
├─ データベース: analytics_db
│   ├─ テーブル: weblogs (全列アクセス可)
│   └─ テーブル: user_pii (特定列のみアクセス可)
├─ 行レベルフィルタリング
└─ 列レベルマスキング
```

**アクセス許可例:**
```python
# Lake Formation アクセス許可
{
  "Principal": {
    "DataLakePrincipalIdentifier": "arn:aws:iam::123456789012:role/DataAnalystRole"
  },
  "Resource": {
    "TableWithColumns": {
      "DatabaseName": "analytics_db",
      "TableName": "users",
      "ColumnNames": ["user_id", "name", "country"],
      "ColumnWildcard": {
        "ExcludedColumnNames": ["email", "phone", "ssn"]  # PII除外
      }
    }
  },
  "Permissions": ["SELECT"],
  "PermissionsWithGrantOption": []
}
```

### オンプレミスでの同等構成

#### 1. Hadoop Data Lake

**HDFSクラスタ:**
```
NameNode (2台 - HA):
├─ メタデータ管理
├─ RAM: 128GB以上
└─ 高速SSD

DataNode (50-100台):
├─ データ保存
├─ Disk: 12 x 10TB HDD
└─ レプリケーション係数: 3
```

**容量計算:**
```
物理容量: 100台 × 12 × 10TB = 12PB
実効容量: 12PB ÷ 3 (レプリケーション) = 4PB

初期投資: 約2億円
```

**Hive メタストア:**
```sql
-- Hive テーブル定義
CREATE EXTERNAL TABLE weblogs (
    user_id STRING,
    timestamp TIMESTAMP,
    endpoint STRING,
    response_time INT
)
PARTITIONED BY (year INT, month INT, day INT)
STORED AS PARQUET
LOCATION 'hdfs:///data/weblogs';

-- パーティション追加
ALTER TABLE weblogs ADD PARTITION (year=2024, month=1, day=15)
LOCATION 'hdfs:///data/weblogs/year=2024/month=01/day=15';
```

**Presto / Hive でクエリ:**
```sql
-- Presto クエリ
SELECT
    date_trunc('hour', timestamp) AS hour,
    endpoint,
    COUNT(*) AS request_count
FROM weblogs
WHERE year = 2024 AND month = 1 AND day = 15
GROUP BY 1, 2
```

**課題:**
- 高額な初期投資（数億円）
- 運用負荷が高い（50-100台のサーバー管理）
- ストレージ拡張が困難
- 障害対応が複雑

#### 2. クラウドストレージ（MinIO等）

**MinIO クラスタ:**
```yaml
# docker-compose.yml (分散モード)
version: '3.7'

services:
  minio1:
    image: minio/minio
    volumes:
      - data1:/data
    environment:
      MINIO_ROOT_USER: admin
      MINIO_ROOT_PASSWORD: password
    command: server http://minio{1...4}/data

  minio2:
    image: minio/minio
    volumes:
      - data2:/data
    environment:
      MINIO_ROOT_USER: admin
      MINIO_ROOT_PASSWORD: password
    command: server http://minio{1...4}/data

  # minio3, minio4 ...

volumes:
  data1:
  data2:
  data3:
  data4:
```

**課題:**
- S3と完全互換ではない
- 運用ノウハウが必要
- 耐久性がS3より低い

#### 3. データカタログ（Apache Atlas / Amundsen）

**Apache Atlas:**
```bash
# Atlas サーバー起動
export MANAGE_LOCAL_HBASE=true
export MANAGE_LOCAL_SOLR=true
./atlas/bin/atlas_start.py

# メタデータ登録
curl -X POST http://localhost:21000/api/atlas/v2/entity \
  -H 'Content-Type: application/json' \
  -d '{
    "entity": {
      "typeName": "hive_table",
      "attributes": {
        "name": "weblogs",
        "qualifiedName": "weblogs@prod",
        "owner": "data-team",
        "description": "Web access logs"
      }
    }
  }'
```

**課題:**
- セットアップが複雑
- 各ツールとの統合が手動

### オンプレミスとAWSの比較

| 項目 | オンプレミス（Hadoop） | AWS Data Lake |
|------|---------------------|---------------|
| **初期投資** | 超高額（数億円）<br>100台以上のサーバー | ゼロ<br>従量課金 |
| **ストレージコスト** | 高い<br>3重レプリケーション<br>電気代、設置費用 | 低い<br>S3: $0.023/GB/月 |
| **スケーラビリティ** | 困難<br>サーバー追加に時間 | 無制限<br>即座にスケール |
| **耐久性** | 3-4 9's | 11 9's |
| **運用負荷** | 極めて高い<br>専任チーム必要 | 低い<br>マネージドサービス |
| **クエリエンジン** | Hive/Presto<br>（運用必要） | Athena<br>（サーバーレス） |

### コスト比較（1PBデータ、月間10TBスキャン）

**オンプレミス（Hadoop）:**
- 初期投資償却（5年）: 約330万円/月
- サーバー電気代: 約50万円/月
- データセンター: 約50万円/月
- 運用人件費: 約300万円/月（3-4名）
- **合計: 約730万円/月**

**AWS Data Lake:**
- S3ストレージ（1PB）: 約250万円/月
- Athena クエリ（10TBスキャン）: 約5万円/月
- Glue Crawler: 約5,000円/月
- Data Transfer: 約10万円/月
- **合計: 約265万円/月**

**運用人件費を含めると約64%削減**

## まとめ

データレイクアーキテクチャーは、多様なデータを低コストで保存・分析する最適な方法です。

**AWSでの利点:**
- **S3の低コスト・高耐久性**（11 9's）
- **サーバーレスクエリ**（Athena）
- **自動スキーマ検出**（Glue Crawler）
- **統合データカタログ**（複数ツールで共有）
- **細かいアクセス制御**（Lake Formation）

**ベストプラクティス:**
1. データをレイヤー分け（Raw → Processed → Curated）
2. Parquet形式で保存（コスト最適化）
3. 適切なパーティション設計
4. Glue Crawlerで自動カタログ化
5. Lake Formationでアクセス制御
6. ライフサイクルポリシーで古いデータをGlacierへ
