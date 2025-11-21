# パターン22: イベント駆動アーキテクチャ

## 問題

マイクロサービス間の疎結合な連携を実現したい。

## 推奨アーキテクチャー

```
[EventBridge]
├─ ルール1: OrderCreated
│   ├─ ターゲット: Lambda (在庫更新)
│   ├─ ターゲット: SQS (メール送信キュー)
│   └─ ターゲット: Step Functions (配送処理)
├─ ルール2: PaymentFailed
│   └─ ターゲット: SNS (アラート)
└─ ルール3: InventoryLow
    └─ ターゲット: Lambda (発注処理)
```

### 使用するAWSサービス:
- **EventBridge**: イベントバス
- **SNS**: Pub/Subメッセージング
- **SQS**: キューイング
- **Lambda**: イベント処理

## 解説

**イベント発行:**
```python
import boto3

events = boto3.client('events')

# イベント発行
events.put_events(
    Entries=[
        {
            'Source': 'order.service',
            'DetailType': 'OrderCreated',
            'Detail': json.dumps({
                'orderId': 'order-123',
                'userId': 'user-456',
                'amount': 10000
            }),
            'EventBusName': 'default'
        }
    ]
)
```

**EventBridgeルール:**
```json
{
  "EventPattern": {
    "source": ["order.service"],
    "detail-type": ["OrderCreated"]
  },
  "Targets": [
    {
      "Arn": "arn:aws:lambda:ap-northeast-1:123456789012:function:UpdateInventory",
      "Id": "1"
    },
    {
      "Arn": "arn:aws:sqs:ap-northeast-1:123456789012:email-queue",
      "Id": "2"
    }
  ]
}
```

### オンプレミス

**RabbitMQ:**
```python
import pika

connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
channel = connection.channel()

# Exchange作成
channel.exchange_declare(exchange='orders', exchange_type='fanout')

# メッセージ発行
channel.basic_publish(
    exchange='orders',
    routing_key='',
    body=json.dumps({'orderId': '123'})
)
```

**Apache Kafka:**
```python
from kafka import KafkaProducer

producer = KafkaProducer(bootstrap_servers=['localhost:9092'])

producer.send('order-events', b'{"orderId": "123"}')
```

## まとめ

EventBridgeでイベント駆動アーキテクチャを簡単に実現できます。

**メリット:**
- サービス間の疎結合
- スケーラビリティ
- 柔軟な拡張性
