# パターン18: 監視・通知システム

## 問題

システムの異常を早期に検知し、迅速に対応したい。

## 推奨アーキテクチャー

```
[AWS Resources]
    ↓ メトリクス
[CloudWatch Metrics]
    ↓ アラーム評価
[CloudWatch Alarms]
    ↓ 通知
[SNS Topic]
    ↓
├─ Email
├─ Slack (Lambda経由)
├─ PagerDuty
└─ Auto Scaling (自動復旧)

[CloudWatch Logs]
├─ Log Insights（ログ分析）
└─ Metric Filters（ログからメトリクス生成）

[X-Ray]（分散トレーシング）
```

### 使用するAWSサービス:
- **CloudWatch**: メトリクス・ログ・アラーム
- **SNS**: 通知
- **X-Ray**: 分散トレーシング
- **EventBridge**: イベント駆動

## 解説

**アラーム設定例:**
```json
{
  "AlarmName": "high-cpu-usage",
  "MetricName": "CPUUtilization",
  "Namespace": "AWS/EC2",
  "Statistic": "Average",
  "Period": 300,
  "EvaluationPeriods": 2,
  "Threshold": 80.0,
  "ComparisonOperator": "GreaterThanThreshold",
  "AlarmActions": [
    "arn:aws:sns:ap-northeast-1:123456789012:alerts"
  ]
}
```

**Slack通知（Lambda）:**
```python
import json
import urllib3

http = urllib3.PoolManager()

def lambda_handler(event, context):
    message = json.loads(event['Records'][0]['Sns']['Message'])

    slack_message = {
        "text": f"⚠️ CloudWatch Alarm",
        "attachments": [{
            "color": "danger",
            "fields": [
                {"title": "Alarm", "value": message['AlarmName']},
                {"title": "Reason", "value": message['NewStateReason']}
            ]
        }]
    }

    http.request(
        'POST',
        'https://hooks.slack.com/services/YOUR/WEBHOOK/URL',
        body=json.dumps(slack_message),
        headers={'Content-Type': 'application/json'}
    )
```

**CloudWatch Logs Insights:**
```sql
fields @timestamp, @message
| filter @message like /ERROR/
| stats count() by bin(5m)
```

### オンプレミス

**Zabbix:**
- サーバー構築・運用が必要
- エージェント導入
- カスタマイズ可能だが複雑

**Prometheus + Grafana:**
```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'web-servers'
    static_configs:
      - targets: ['192.168.1.10:9100', '192.168.1.11:9100']
```

**課題:**
- 監視サーバーの運用
- アラート設定の複雑さ
- ログ集約の仕組み構築

## まとめ

CloudWatchで統合監視を簡単に実現できます。

**ベストプラクティス:**
1. 重要なメトリクスにアラーム設定
2. ログは集約してInsightsで分析
3. X-Rayでパフォーマンスボトルネック特定
4. SNSで複数チャネルに通知
