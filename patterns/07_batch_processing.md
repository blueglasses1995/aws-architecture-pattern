# パターン7: バッチ処理システム

## 問題

毎日深夜に大量のログデータを集計・分析し、レポートを生成する必要があります。
以下の要件を満たすバッチ処理システムを設計してください。

**要件:**
- 毎日数百万件のログレコードを処理
- 処理時間は2-3時間
- コスト効率が重要（夜間のみ実行）
- エラー時のリトライと通知
- 処理状況の可視化

## 推奨アーキテクチャー

```
[EventBridge (cron)]
    ↓
[Step Functions] (ワークフロー管理)
    ↓
├─ Lambda (データ取得)
├─ AWS Batch / Fargate (重い処理)
├─ Glue (ETL処理)
└─ Lambda (レポート生成)
    ↓
[S3] (結果保存)
    ↓
[SNS] (完了通知)
```

### 使用するAWSサービス:
- **EventBridge**: スケジュール実行
- **Step Functions**: ワークフロー管理
- **AWS Batch / Fargate**: コンピューティング
- **Lambda**: 軽量処理
- **Glue**: ETL処理
- **S3**: データストレージ
- **SNS**: 通知
- **CloudWatch**: 監視

## 解説

### なぜこのアーキテクチャーなのか

#### 1. Step Functionsによるワークフロー管理

**複雑なバッチ処理の課題:**
```
従来のcronジョブ:
├─ エラーハンドリングが困難
├─ 処理の依存関係管理が複雑
├─ リトライロジックを個別に実装
└─ 処理状況の可視化が困難
```

**Step Functionsの利点:**
```
ビジュアルワークフロー:
├─ 処理の流れが一目瞭然
├─ 自動リトライ設定
├─ エラーハンドリングの統一
└─ 実行履歴の完全な可視性
```

**ワークフロー定義例:**
```json
{
  "Comment": "Daily Log Processing Workflow",
  "StartAt": "FetchLogs",
  "States": {
    "FetchLogs": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ap-northeast-1:123456789012:function:FetchLogs",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "NotifyFailure"
        }
      ],
      "Next": "ProcessInParallel"
    },
    "ProcessInParallel": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "AggregateUserStats",
          "States": {
            "AggregateUserStats": {
              "Type": "Task",
              "Resource": "arn:aws:states:::batch:submitJob.sync",
              "Parameters": {
                "JobDefinition": "user-stats-job",
                "JobName": "user-stats",
                "JobQueue": "batch-queue"
              },
              "End": true
            }
          }
        },
        {
          "StartAt": "AggregateProductStats",
          "States": {
            "AggregateProductStats": {
              "Type": "Task",
              "Resource": "arn:aws:states:::batch:submitJob.sync",
              "Parameters": {
                "JobDefinition": "product-stats-job",
                "JobName": "product-stats",
                "JobQueue": "batch-queue"
              },
              "End": true
            }
          }
        }
      ],
      "Next": "GenerateReport"
    },
    "GenerateReport": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ap-northeast-1:123456789012:function:GenerateReport",
      "Next": "NotifySuccess"
    },
    "NotifySuccess": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "arn:aws:sns:ap-northeast-1:123456789012:batch-notifications",
        "Message": "Batch processing completed successfully"
      },
      "End": true
    },
    "NotifyFailure": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "arn:aws:sns:ap-northeast-1:123456789012:batch-notifications",
        "Message.$": "$.error"
      },
      "End": true
    }
  }
}
```

#### 2. AWS Batch vs Lambda vs Fargate

**処理時間と選択:**
```
Lambda:
├─ 実行時間: 最大15分
├─ メモリ: 最大10GB
├─ 用途: 軽量・短時間処理
└─ コスト: 実行時間のみ課金

AWS Batch:
├─ 実行時間: 無制限
├─ リソース: EC2 / Fargate
├─ 用途: 大規模・長時間処理
└─ コスト: EC2/Fargate料金

Fargate:
├─ 実行時間: 無制限
├─ メモリ: 最大120GB
├─ 用途: コンテナベース処理
└─ コスト: vCPU/メモリ × 実行時間
```

**AWS Batch ジョブ定義:**
```json
{
  "jobDefinitionName": "log-aggregation",
  "type": "container",
  "containerProperties": {
    "image": "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/log-processor:latest",
    "vcpus": 4,
    "memory": 8192,
    "command": [
      "python",
      "aggregate.py",
      "--date",
      "Ref::date",
      "--output",
      "s3://my-bucket/results/"
    ],
    "jobRoleArn": "arn:aws:iam::123456789012:role/BatchJobRole",
    "environment": [
      {
        "name": "AWS_DEFAULT_REGION",
        "value": "ap-northeast-1"
      }
    ],
    "resourceRequirements": [
      {
        "type": "GPU",
        "value": "1"
      }
    ]
  },
  "retryStrategy": {
    "attempts": 3
  },
  "timeout": {
    "attemptDurationSeconds": 10800
  }
}
```

#### 3. Glue ETL処理

**AWS Glue の利点:**
- サーバーレスなETL
- 自動スケーリング
- Apache Spark ベース
- Data Catalog との統合

**Glue ジョブ例（PySpark）:**
```python
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'input_path', 'output_path'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# S3から生ログ読み込み
logs_df = spark.read.json(args['input_path'])

# データクレンジング
cleaned_df = logs_df \
    .filter(logs_df.status_code.isNotNull()) \
    .filter(logs_df.timestamp.isNotNull()) \
    .dropDuplicates(['request_id'])

# 集計処理
from pyspark.sql.functions import col, count, avg, sum, hour

hourly_stats = cleaned_df \
    .withColumn('hour', hour(col('timestamp'))) \
    .groupBy('hour', 'endpoint') \
    .agg(
        count('*').alias('request_count'),
        avg('response_time').alias('avg_response_time'),
        sum('bytes_sent').alias('total_bytes')
    )

# S3に結果保存（Parquet形式）
hourly_stats.write \
    .mode('overwrite') \
    .partitionBy('hour') \
    .parquet(args['output_path'])

job.commit()
```

### オンプレミスでの同等構成

#### 1. cron + シェルスクリプト

**従来のバッチ処理:**
```bash
# /etc/crontab
0 2 * * * batch_user /opt/batch/daily_process.sh

# /opt/batch/daily_process.sh
#!/bin/bash

set -e

LOG_FILE="/var/log/batch/$(date +%Y%m%d).log"
ERROR_FILE="/var/log/batch/$(date +%Y%m%d)_error.log"

exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$ERROR_FILE")

echo "$(date): Starting batch process"

# データ取得
python /opt/batch/fetch_logs.py || {
    echo "Error: Failed to fetch logs"
    /opt/batch/send_alert.sh "Batch failed: fetch_logs.py"
    exit 1
}

# 並列処理
python /opt/batch/aggregate_users.py &
PID1=$!

python /opt/batch/aggregate_products.py &
PID2=$!

# 待機
wait $PID1 || {
    echo "Error: User aggregation failed"
    /opt/batch/send_alert.sh "Batch failed: aggregate_users.py"
    exit 1
}

wait $PID2 || {
    echo "Error: Product aggregation failed"
    /opt/batch/send_alert.sh "Batch failed: aggregate_products.py"
    exit 1
}

# レポート生成
python /opt/batch/generate_report.py || {
    echo "Error: Report generation failed"
    /opt/batch/send_alert.sh "Batch failed: generate_report.py"
    exit 1
}

echo "$(date): Batch process completed"
/opt/batch/send_alert.sh "Batch completed successfully"
```

**課題:**
- エラーハンドリングが煩雑
- リトライロジックを自前実装
- ログ管理が分散
- 処理状況の可視化困難

#### 2. ジョブスケジューラー（JP1 / Hinemos / Rundeck）

**JP1/AJS（日立）:**
```
# ジョブネット定義
JOB_NET: DailyBatch
├─ UNIT_1: FetchLogs
│   ├─ Start: 02:00
│   ├─ Script: /opt/batch/fetch_logs.sh
│   └─ Retry: 3 times
├─ UNIT_2: ParallelProcessing (UNIT_1完了後)
│   ├─ JOB_2A: AggregateUsers
│   └─ JOB_2B: AggregateProducts
└─ UNIT_3: GenerateReport (UNIT_2完了後)
    └─ Script: /opt/batch/generate_report.sh
```

**コスト:**
- ライセンス費用: 数百万円/年
- 保守費用: 数十万円/年

**Rundeck（OSS）:**
```yaml
# job.yaml
- id: daily-batch
  name: Daily Batch Processing
  scheduleEnabled: true
  schedule:
    cron: '0 2 * * *'
  sequence:
    keepgoing: false
    strategy: node-first
    commands:
      - script: |
          #!/bin/bash
          python /opt/batch/fetch_logs.py
        errorhandler:
          script: |
            curl -X POST https://slack.com/api/chat.postMessage \
              -d "text=Fetch logs failed"
      - script: |
          #!/bin/bash
          python /opt/batch/aggregate_users.py &
          python /opt/batch/aggregate_products.py &
          wait
      - script: |
          #!/bin/bash
          python /opt/batch/generate_report.py
  notification:
    onsuccess:
      email:
        recipients: admin@example.com
        subject: 'Batch Completed'
    onfailure:
      email:
        recipients: admin@example.com
        subject: 'Batch Failed'
```

#### 3. Apache Airflow

**DAG定義:**
```python
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from datetime import datetime, timedelta

default_args = {
    'owner': 'data-team',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email': ['admin@example.com'],
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 3,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'daily_batch_processing',
    default_args=default_args,
    description='Daily log aggregation',
    schedule_interval='0 2 * * *',
    catchup=False,
)

fetch_logs = BashOperator(
    task_id='fetch_logs',
    bash_command='python /opt/batch/fetch_logs.py',
    dag=dag,
)

aggregate_users = BashOperator(
    task_id='aggregate_users',
    bash_command='python /opt/batch/aggregate_users.py',
    dag=dag,
)

aggregate_products = BashOperator(
    task_id='aggregate_products',
    bash_command='python /opt/batch/aggregate_products.py',
    dag=dag,
)

generate_report = BashOperator(
    task_id='generate_report',
    bash_command='python /opt/batch/generate_report.py',
    dag=dag,
)

# 依存関係
fetch_logs >> [aggregate_users, aggregate_products] >> generate_report
```

**課題:**
- Airflowサーバーの運用が必要
- スケーリングが困難（ワーカー数に制限）
- 高可用性構成が複雑

#### 4. Hadoop/Spark クラスタ

**Hadoop YARN + Spark:**
```bash
# Spark ジョブ投入
spark-submit \
  --master yarn \
  --deploy-mode cluster \
  --num-executors 10 \
  --executor-cores 4 \
  --executor-memory 8G \
  --conf spark.sql.shuffle.partitions=200 \
  /opt/batch/log_aggregation.py \
  --input hdfs:///data/logs/2024-01-01 \
  --output hdfs:///data/results/2024-01-01
```

**クラスタ構成:**
```
Master Nodes (3台):
├─ YARN ResourceManager
├─ HDFS NameNode
└─ Spark Master

Worker Nodes (20台):
├─ YARN NodeManager
├─ HDFS DataNode
└─ Spark Executor
```

**初期投資:**
- サーバー（23台）: 約3,000万円
- ストレージ（500TB）: 約1,000万円
- ネットワーク: 約300万円
- **合計: 約4,300万円**

**運用コスト:**
- 電気代: 約50万円/月
- データセンター: 約30万円/月
- 運用人件費: 約150万円/月（2-3名）
- **合計: 約230万円/月**

### オンプレミスとAWSの比較

| 項目 | オンプレミス | AWS Step Functions + Batch |
|------|------------|---------------------------|
| **ワークフロー管理** | ジョブスケジューラー<br>（JP1/Airflow等） | Step Functions<br>（ビジュアル、簡単） |
| **スケーラビリティ** | 固定リソース<br>ピーク時対応で過剰投資 | 動的スケール<br>必要な時だけリソース確保 |
| **コスト（夜間のみ）** | 高い<br>24時間サーバー稼働 | 低い<br>実行時間のみ課金 |
| **エラーハンドリング** | 自前実装<br>複雑なスクリプト | 組み込み機能<br>宣言的に定義 |
| **可視化** | 限定的<br>追加ツールが必要 | 標準機能<br>実行履歴が完全に可視化 |

### コスト比較（毎日3時間のバッチ処理）

**オンプレミス（Hadoop クラスタ）:**
- 初期投資償却（3年）: 約120万円/月
- 運用コスト: 約230万円/月
- **合計: 約350万円/月**

**AWS:**
- Step Functions: 約100円/月（30実行）
- AWS Batch (Fargate): 約1.5万円/月（4 vCPU × 3時間 × 30日）
- S3ストレージ: 約2,500円/月
- Glue: 約5,000円/月
- **合計: 約2.3万円/月**

**コスト削減率: 約99%**

## まとめ

バッチ処理システムでは、AWS のサーバーレスサービスを活用することで、
オンプレミスと比較して圧倒的なコスト削減と運用負荷軽減が可能です。

**ベストプラクティス:**
1. Step Functions でワークフロー管理
2. Lambda（軽量処理）と Batch（重い処理）を使い分け
3. Glue で大規模データ変換
4. S3 で結果保存（ライフサイクル設定でコスト最適化）
5. CloudWatch でモニタリング
6. SNS でアラート通知

**注意点:**
- Lambda は15分制限（長時間処理はBatch/Fargate）
- Step Functions は25,000イベント/実行の制限
- Glue は最小10分課金（短時間処理には不向き）
