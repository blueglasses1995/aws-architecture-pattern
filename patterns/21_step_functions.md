# パターン21: Step Functionsワークフロー

## 問題

複雑な業務フローを自動化したい（注文処理→決済→在庫確認→発送指示等）。

## 推奨アーキテクチャー

```
[Step Functions State Machine]
├─ 1. ValidateOrder (Lambda)
├─ 2. ProcessPayment (Lambda)
│   ├─ Success → 3へ
│   └─ Fail → SendErrorEmail
├─ 3. CheckInventory (Lambda)
│   ├─ InStock → 4へ
│   └─ OutOfStock → Wait 1 hour → 3へ
├─ 4. ReserveInventory (DynamoDB)
├─ 5. ShipOrder (Lambda → SQS)
└─ 6. SendConfirmationEmail (SNS)
```

### 使用するAWSサービス:
- **Step Functions**: ワークフローオーケストレーション
- **Lambda**: 各ステップの処理
- **DynamoDB**: 状態管理
- **SQS/SNS**: 非同期通知

## 解説

**State Machine定義:**
```json
{
  "StartAt": "ValidateOrder",
  "States": {
    "ValidateOrder": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ap-northeast-1:123456789012:function:ValidateOrder",
      "Next": "ProcessPayment",
      "Catch": [{
        "ErrorEquals": ["ValidationError"],
        "Next": "SendErrorEmail"
      }],
      "Retry": [{
        "ErrorEquals": ["States.TaskFailed"],
        "IntervalSeconds": 2,
        "MaxAttempts": 3,
        "BackoffRate": 2.0
      }]
    },
    "ProcessPayment": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ap-northeast-1:123456789012:function:ProcessPayment",
      "Next": "CheckInventory"
    },
    "CheckInventory": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ap-northeast-1:123456789012:function:CheckInventory",
      "Next": "InventoryAvailable?"
    },
    "InventoryAvailable?": {
      "Type": "Choice",
      "Choices": [{
        "Variable": "$.inventoryStatus",
        "StringEquals": "available",
        "Next": "ReserveInventory"
      }],
      "Default": "WaitForInventory"
    },
    "WaitForInventory": {
      "Type": "Wait",
      "Seconds": 3600,
      "Next": "CheckInventory"
    },
    "ReserveInventory": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:updateItem",
      "Parameters": {
        "TableName": "Inventory",
        "Key": {
          "ProductId": {"S.$": "$.productId"}
        },
        "UpdateExpression": "SET reserved = reserved + :qty",
        "ExpressionAttributeValues": {
          ":qty": {"N.$": "$.quantity"}
        }
      },
      "Next": "ShipOrder"
    },
    "ShipOrder": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sqs:sendMessage",
      "Parameters": {
        "QueueUrl": "https://sqs.ap-northeast-1.amazonaws.com/123456789012/shipping-queue",
        "MessageBody.$": "$"
      },
      "Next": "SendConfirmationEmail"
    },
    "SendConfirmationEmail": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "arn:aws:sns:ap-northeast-1:123456789012:order-notifications",
        "Message.$": "$.confirmationMessage"
      },
      "End": true
    },
    "SendErrorEmail": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "arn:aws:sns:ap-northeast-1:123456789012:error-notifications",
        "Message.$": "$.errorMessage"
      },
      "End": true
    }
  }
}
```

### オンプレミス

**Apache Airflow:**
```python
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime

with DAG('order_processing', start_date=datetime(2024, 1, 1)) as dag:
    validate = PythonOperator(task_id='validate', python_callable=validate_order)
    payment = PythonOperator(task_id='payment', python_callable=process_payment)
    inventory = PythonOperator(task_id='inventory', python_callable=check_inventory)

    validate >> payment >> inventory
```

**課題:**
- Airflowサーバーの運用
- 複雑なエラーハンドリング
- ビジュアルな流れが見にくい

## まとめ

Step Functionsで複雑なワークフローを簡単にオーケストレーションできます。

**ベストプラクティス:**
1. 各ステップは小さく（単一責任）
2. エラーハンドリングとリトライを適切に設定
3. Choice Stateで条件分岐
4. Wait Stateで遅延処理
5. Parallel Stateで並列処理
