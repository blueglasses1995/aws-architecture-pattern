# パターン9: リアルタイムストリーミング処理

## 問題

オンラインゲームのプレイヤー行動をリアルタイムで分析し、不正検知やリアルタイムランキングを実装します。

**要件:**
- 秒間10万イベントのストリーミングデータ処理
- レイテンシ1秒以内でリアルタイム処理
- データの永続化（後続の機械学習にも利用）
- スケーラブルな処理基盤
- 障害時のデータ損失を最小化

## 推奨アーキテクチャー

```
[ゲームクライアント]
    ↓
[Kinesis Data Streams]
    ↓
├─ Lambda (リアルタイム処理)
│   ├─ 不正検知
│   ├─ リアルタイムランキング更新
│   └─ アラート送信
│
├─ Kinesis Data Firehose
│   └─ S3 (永続化)
│       └─ Athena (後続分析)
│
└─ Kinesis Data Analytics
    └─ SQLでストリーム分析
```

### 使用するAWSサービス:
- **Kinesis Data Streams**: ストリーミングデータ取り込み
- **Lambda**: リアルタイム処理
- **Kinesis Data Firehose**: S3への永続化
- **Kinesis Data Analytics**: SQLストリーム分析
- **DynamoDB**: リアルタイム集計結果
- **ElastiCache**: 高速キャッシュ
- **CloudWatch**: メトリクス監視

## 解説

### なぜこのアーキテクチャーなのか

#### 1. Kinesis Data Streamsの仕組み

**シャーディング:**
```
Kinesis Stream: game-events
├─ Shard 1: 1MB/秒書き込み、2MB/秒読み取り
├─ Shard 2: 1MB/秒書き込み、2MB/秒読み取り
├─ Shard 3: ...
└─ Shard N: ...

必要シャード数 = (データサイズ GB/秒 × 1024) ÷ 1
例: 0.1 GB/秒 = 100 MB/秒 → 100シャード必要
```

**パーティションキー:**
```javascript
// データ送信例
const AWS = require('aws-sdk');
const kinesis = new AWS.Kinesis();

async function sendEvent(playerId, eventType, data) {
  const params = {
    StreamName: 'game-events',
    Data: JSON.stringify({
      playerId,
      eventType,
      timestamp: Date.now(),
      data
    }),
    PartitionKey: playerId.toString()  // 同じプレイヤーは同じシャードへ
  };

  await kinesis.putRecord(params).promise();
}

// 使用例
await sendEvent('player-12345', 'item_purchased', {
  itemId: 'sword-001',
  price: 1000,
  currency: 'gold'
});
```

**バッチ送信（スループット向上）:**
```javascript
async function sendBatchEvents(events) {
  const params = {
    StreamName: 'game-events',
    Records: events.map(e => ({
      Data: JSON.stringify(e),
      PartitionKey: e.playerId.toString()
    }))
  };

  const result = await kinesis.putRecords(params).promise();

  // 失敗したレコードのリトライ
  if (result.FailedRecordCount > 0) {
    const failedRecords = result.Records
      .map((r, i) => r.ErrorCode ? events[i] : null)
      .filter(r => r !== null);

    // 指数バックオフでリトライ
    await retryWithBackoff(failedRecords);
  }
}
```

#### 2. Lambdaでのストリーム処理

**イベント駆動処理:**
```javascript
exports.handler = async (event) => {
  const records = event.Records.map(record => {
    const payload = Buffer.from(record.kinesis.data, 'base64').toString('utf-8');
    return JSON.parse(payload);
  });

  // 並列処理
  await Promise.all(records.map(async (event) => {
    switch (event.eventType) {
      case 'item_purchased':
        await processPurchase(event);
        break;
      case 'player_action':
        await detectCheating(event);
        break;
      case 'score_updated':
        await updateRanking(event);
        break;
    }
  }));

  return {
    batchItemFailures: []  // 全て成功
  };
};

// 不正検知
async function detectCheating(event) {
  const { playerId, data } = event;

  // 異常な行動パターンを検知
  const actionsPerMinute = await getRecentActionsCount(playerId);

  if (actionsPerMinute > 1000) {  // 人間では不可能な操作
    // アラート送信
    await sns.publish({
      TopicArn: 'arn:aws:sns:ap-northeast-1:123456789012:cheating-alerts',
      Message: JSON.stringify({
        playerId,
        reason: 'Excessive actions per minute',
        count: actionsPerMinute
      })
    }).promise();

    // アカウント一時停止
    await suspendPlayer(playerId);
  }
}

// リアルタイムランキング更新
async function updateRanking(event) {
  const { playerId, data } = event;
  const { score } = data;

  // ElastiCache (Redis) にランキング保存
  const redis = require('redis').createClient({
    host: process.env.REDIS_HOST,
    port: 6379
  });

  // Sorted Set で自動ソート
  await redis.zadd('global_ranking', score, playerId);

  // Top 100のみ保持
  await redis.zremrangebyrank('global_ranking', 0, -101);

  // プレイヤーの順位取得
  const rank = await redis.zrevrank('global_ranking', playerId);

  // DynamoDB に永続化
  await dynamodb.put({
    TableName: 'PlayerStats',
    Item: {
      playerId,
      score,
      rank: rank + 1,
      updatedAt: Date.now()
    }
  }).promise();
}
```

**エラーハンドリング:**
```javascript
exports.handler = async (event) => {
  const failedRecords = [];

  for (const record of event.Records) {
    try {
      const payload = JSON.parse(
        Buffer.from(record.kinesis.data, 'base64').toString()
      );

      await processEvent(payload);

    } catch (error) {
      console.error('Processing failed:', error);

      // 失敗したレコードを記録
      failedRecords.push({
        itemIdentifier: record.kinesis.sequenceNumber
      });
    }
  }

  // 部分的バッチ失敗レスポンス
  return {
    batchItemFailures: failedRecords
  };
};
```

#### 3. Kinesis Data Analyticsでのストリーム分析

**SQLでリアルタイム集計:**
```sql
-- 1分間のウィンドウで集計
CREATE OR REPLACE STREAM "DESTINATION_SQL_STREAM" (
    window_time TIMESTAMP,
    event_type VARCHAR(64),
    event_count INTEGER,
    avg_value DOUBLE
);

CREATE OR REPLACE PUMP "STREAM_PUMP" AS
INSERT INTO "DESTINATION_SQL_STREAM"
SELECT STREAM
    STEP("SOURCE_SQL_STREAM_001".ROWTIME BY INTERVAL '1' MINUTE) AS window_time,
    "event_type",
    COUNT(*) AS event_count,
    AVG("value") AS avg_value
FROM "SOURCE_SQL_STREAM_001"
GROUP BY
    STEP("SOURCE_SQL_STREAM_001".ROWTIME BY INTERVAL '1' MINUTE),
    "event_type";
```

**異常検知（スパイク検知）:**
```sql
-- 移動平均との比較で異常検知
CREATE OR REPLACE STREAM "ANOMALY_STREAM" (
    event_type VARCHAR(64),
    current_count INTEGER,
    avg_count DOUBLE,
    is_anomaly BOOLEAN
);

CREATE OR REPLACE PUMP "ANOMALY_PUMP" AS
INSERT INTO "ANOMALY_STREAM"
SELECT STREAM
    "event_type",
    "event_count" AS current_count,
    AVG("event_count") OVER W1 AS avg_count,
    CASE
        WHEN "event_count" > AVG("event_count") OVER W1 * 2
        THEN TRUE
        ELSE FALSE
    END AS is_anomaly
FROM "DESTINATION_SQL_STREAM"
WINDOW W1 AS (
    PARTITION BY "event_type"
    RANGE INTERVAL '10' MINUTE PRECEDING
);
```

#### 4. Kinesis Data Firehoseでの永続化

**S3への自動配信:**
```json
{
  "DeliveryStreamName": "game-events-to-s3",
  "S3DestinationConfiguration": {
    "BucketARN": "arn:aws:s3:::game-analytics",
    "Prefix": "events/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/",
    "ErrorOutputPrefix": "errors/",
    "BufferingHints": {
      "SizeInMBs": 128,
      "IntervalInSeconds": 300
    },
    "CompressionFormat": "GZIP",
    "DataFormatConversionConfiguration": {
      "SchemaConfiguration": {
        "DatabaseName": "game_analytics",
        "TableName": "events",
        "Region": "ap-northeast-1"
      },
      "InputFormatConfiguration": {
        "Deserializer": {
          "OpenXSerDe": {}
        }
      },
      "OutputFormatConfiguration": {
        "Serializer": {
          "ParquetSerDe": {}  # Parquet形式に変換
        }
      }
    }
  }
}
```

### オンプレミスでの同等構成

#### 1. Apache Kafka

**Kafkaクラスタ構成:**
```
ZooKeeper クラスタ (3台):
├─ クラスタメタデータ管理
└─ Leader選出

Kafka Broker (5台):
├─ トピック: game-events (10パーティション、レプリケーション3)
├─ ディスク: 2TB SSD × 4
└─ RAM: 64GB

スキーマレジストリ (Confluent):
└─ Avroスキーマ管理
```

**トピック設定:**
```bash
# トピック作成
kafka-topics.sh --create \
  --bootstrap-server kafka1:9092 \
  --topic game-events \
  --partitions 10 \
  --replication-factor 3 \
  --config retention.ms=604800000 \  # 7日間保持
  --config segment.bytes=1073741824   # 1GB セグメント
```

**プロデューサー（データ送信）:**
```python
from kafka import KafkaProducer
import json

producer = KafkaProducer(
    bootstrap_servers=['kafka1:9092', 'kafka2:9092', 'kafka3:9092'],
    value_serializer=lambda v: json.dumps(v).encode('utf-8'),
    acks='all',  # 全レプリカへの書き込み確認
    retries=3,
    compression_type='snappy'
)

def send_event(player_id, event_type, data):
    message = {
        'playerId': player_id,
        'eventType': event_type,
        'timestamp': time.time(),
        'data': data
    }

    future = producer.send(
        'game-events',
        value=message,
        key=str(player_id).encode('utf-8')  # パーティションキー
    )

    # 送信確認
    record_metadata = future.get(timeout=10)
    print(f"Sent to partition {record_metadata.partition}")
```

**コンシューマー（データ処理）:**
```python
from kafka import KafkaConsumer

consumer = KafkaConsumer(
    'game-events',
    bootstrap_servers=['kafka1:9092', 'kafka2:9092'],
    group_id='event-processor',
    auto_offset_reset='earliest',
    enable_auto_commit=False,  # 手動コミット
    value_deserializer=lambda m: json.loads(m.decode('utf-8'))
)

for message in consumer:
    try:
        event = message.value

        # 処理
        process_event(event)

        # オフセットコミット
        consumer.commit()

    except Exception as e:
        print(f"Error processing: {e}")
        # Dead Letter Queue へ送信
        send_to_dlq(message)
```

#### 2. Apache Flink

**Flinkクラスタ:**
```
JobManager (2台 - HA):
├─ タスク管理
└─ チェックポイント調整

TaskManager (10台):
├─ vCPU: 16
├─ RAM: 64GB
└─ ストリーム処理実行
```

**Flinkジョブ例:**
```java
// DataStream API
StreamExecutionEnvironment env =
    StreamExecutionEnvironment.getExecutionEnvironment();

// Kafkaソース
FlinkKafkaConsumer<String> consumer = new FlinkKafkaConsumer<>(
    "game-events",
    new SimpleStringSchema(),
    properties
);

DataStream<GameEvent> events = env
    .addSource(consumer)
    .map(json -> parseGameEvent(json));

// ウィンドウ集計
DataStream<EventStats> stats = events
    .keyBy(event -> event.getEventType())
    .window(TumblingProcessingTimeWindows.of(Time.minutes(1)))
    .aggregate(new CountAggregator());

// 結果をKafkaに出力
stats.addSink(new FlinkKafkaProducer<>(
    "event-stats",
    new EventStatsSerializer(),
    properties
));

env.execute("Game Event Processing");
```

**チェックポイント設定:**
```java
env.enableCheckpointing(60000);  // 1分毎
env.getCheckpointConfig().setCheckpointingMode(
    CheckpointingMode.EXACTLY_ONCE
);
env.getCheckpointConfig().setMinPauseBetweenCheckpoints(30000);
env.getCheckpointConfig().setCheckpointTimeout(600000);
```

#### 3. Redis / Druid

**Redis（リアルタイム集計）:**
```bash
# Redis Cluster (6ノード)
redis-cli --cluster create \
  redis1:6379 redis2:6379 redis3:6379 \
  redis4:6379 redis5:6379 redis6:6379 \
  --cluster-replicas 1
```

**Druid（OLAP分析）:**
```yaml
# Druid クラスタ構成
Master:
  - Coordinator: クラスタ管理
  - Overlord: タスク管理

Query:
  - Broker: クエリルーティング
  - Router: API ゲートウェイ

Data:
  - Historical: 履歴データ
  - MiddleManager: リアルタイム取り込み
```

### オンプレミスとAWSの比較

| 項目 | オンプレミス（Kafka + Flink） | AWS Kinesis |
|------|---------------------------|-------------|
| **初期構築** | 複雑<br>Kafka、Zookeeper、Flink | 簡単<br>数クリック |
| **運用負荷** | 高い<br>クラスタ管理、バージョンアップ | 低い<br>マネージドサービス |
| **スケーリング** | 手動<br>Broker/パーティション追加 | 自動<br>シャード増減 |
| **データ保持** | ディスク容量に依存<br>通常7-30日 | 最大365日<br>追加コストなし |
| **初期投資** | 高額（数千万円）<br>20台以上のサーバー | ゼロ<br>従量課金 |

### コスト比較（秒間10万イベント、1日86億イベント）

**オンプレミス（Kafka + Flink）:**
- サーバー（20台）: 2,000万円 ÷ 36ヶ月 = 約55万円/月
- ストレージ（200TB）: 500万円 ÷ 36ヶ月 = 約14万円/月
- ネットワーク: 約5万円/月
- 運用コスト: 約100万円/月（2名）
- **合計: 約174万円/月**

**AWS Kinesis:**
- Kinesis Data Streams（100シャード）: 約150万円/月
- Lambda処理: 約10万円/月
- Kinesis Firehose: 約5万円/月
- S3ストレージ: 約5万円/月
- **合計: 約170万円/月**

**運用人件費を考慮するとAWSが有利**

## まとめ

リアルタイムストリーミング処理では、AWSのマネージドサービスで運用負荷を大幅に削減できます。

**ベストプラクティス:**
1. Kinesis Data Streams で取り込み
2. Lambda でリアルタイム処理
3. Firehose で S3 に永続化
4. Data Analytics で SQL 分析
5. CloudWatch でメトリクス監視
6. 適切なシャード数設計

**注意点:**
- シャード数は事前計画が重要
- Lambdaのタイムアウトとバッチサイズ調整
- データ損失防止のためのエラーハンドリング
