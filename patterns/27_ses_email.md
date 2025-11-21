# パターン27: SESメール送信システム

## 問題

大量のメール（通知、マーケティング等）を低コストで送信したい。

## 推奨アーキテクチャー

```
[アプリケーション]
    ↓
[SQS]（メール送信キュー）
    ↓
[Lambda]
    ↓
[Amazon SES]
    ↓
[受信者]

[SNS]（バウンス/苦情通知）
    ↓
[Lambda]（配信不可リスト管理）
```

### SES送信例

```python
import boto3

ses = boto3.client('ses', region_name='ap-northeast-1')

response = ses.send_email(
    Source='noreply@example.com',
    Destination={
        'ToAddresses': ['user@example.com']
    },
    Message={
        'Subject': {
            'Data': '注文確認',
            'Charset': 'UTF-8'
        },
        'Body': {
            'Html': {
                'Data': '<h1>ご注文ありがとうございます</h1><p>注文番号: #12345</p>',
                'Charset': 'UTF-8'
            },
            'Text': {
                'Data': 'ご注文ありがとうございます\n注文番号: #12345',
                'Charset': 'UTF-8'
            }
        }
    }
)
```

### テンプレートメール

```python
# テンプレート作成
ses.create_template(
    Template={
        'TemplateName': 'OrderConfirmation',
        'SubjectPart': '【{{companyName}}】ご注文確認',
        'HtmlPart': '<h1>{{customerName}}様</h1><p>注文番号: {{orderId}}</p>',
        'TextPart': '{{customerName}}様\n注文番号: {{orderId}}'
    }
)

# テンプレート使用
ses.send_templated_email(
    Source='noreply@example.com',
    Destination={'ToAddresses': ['user@example.com']},
    Template='OrderConfirmation',
    TemplateData=json.dumps({
        'companyName': 'Example Corp',
        'customerName': '山田太郎',
        'orderId': '#12345'
    })
)
```

## コスト比較

| サービス | 料金 |
|---------|------|
| **SendGrid** | $19.95/月〜（10,000通） |
| **Mailchimp** | $20/月〜（500通） |
| **Amazon SES** | $0.10/1,000通 |

**SESの圧倒的な低コスト！**

## まとめ

SESで大量メールを低コストで送信可能。

**ベストプラクティス:**
1. SQS経由で非同期送信
2. バウンス/苦情をSNSで受信
3. 配信不可リストを管理
4. Configuration Setで分析
