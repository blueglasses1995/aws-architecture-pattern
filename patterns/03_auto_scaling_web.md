# パターン3: スケーラブルなWebアプリケーション

## 問題

ニュースサイトを運営しており、通常は1,000リクエスト/秒ですが、速報ニュース発生時には10,000リクエスト/秒まで急増します。
以下の要件を満たすスケーラブルなアーキテクチャーを設計してください。

**要件:**
- トラフィックの急激な増減に自動対応
- コスト効率の良いスケーリング
- スケールアウト/インに数分以内で対応
- ユーザー体験の維持（レスポンスタイム2秒以内）
- 最小2台、最大20台のEC2で運用

## 推奨アーキテクチャー

```
Route 53
    ↓
CloudFront (CDN)
    ↓
Application Load Balancer
    ↓
Auto Scaling Group
├─ EC2 × 2-20台 (動的)
├─ Target Tracking Policy (CPU 70%)
└─ Scheduled Scaling (予測可能な負荷)
    ↓
RDS Read Replica (読み取り負荷分散)
ElastiCache (セッション管理)
```

### 使用するAWSサービス:
- **Auto Scaling Group**: 自動スケーリング
- **CloudWatch**: メトリクス監視
- **ALB**: 自動的にターゲット追加/削除
- **CloudFront**: 静的コンテンツキャッシュ
- **ElastiCache**: セッション共有
- **RDS Read Replica**: 読み取りスケーリング

## 解説

### なぜこのアーキテクチャーなのか

#### 1. Auto Scalingの重要性

**従来の静的スケーリングの問題:**
```
ピーク時に合わせて常に大量のサーバーを稼働
→ 通常時は80%以上のリソースが無駄
→ 年間数百万円のコスト超過
```

**Auto Scalingのメリット:**
```
需要に応じて動的にスケール
→ 常に適切なキャパシティを維持
→ コスト最適化（最大70%削減可能）
```

#### 2. スケーリングポリシーの種類

**A. Target Tracking Scaling（推奨）:**
```yaml
TargetValue: 70.0  # CPU使用率70%を維持
PredefinedMetricType: ASGAverageCPUUtilization
```

**仕組み:**
- CPU使用率が70%を超えるとスケールアウト
- 70%を下回るとスケールイン
- CloudWatchが自動的に調整

**B. Step Scaling:**
```yaml
# CPU 50-70%: +1台
# CPU 70-90%: +2台
# CPU 90%以上: +4台
Adjustments:
  - MetricIntervalLowerBound: 0
    MetricIntervalUpperBound: 20
    ScalingAdjustment: 1
  - MetricIntervalLowerBound: 20
    MetricIntervalUpperBound: 40
    ScalingAdjustment: 2
  - MetricIntervalLowerBound: 40
    ScalingAdjustment: 4
```

**C. Scheduled Scaling:**
```yaml
# 毎日朝9時に10台に増やす
ScheduledActions:
  - ScheduledActionName: morning-scale-out
    Recurrence: "0 9 * * *"
    MinSize: 10
    MaxSize: 20
    DesiredCapacity: 10

  # 毎日夜11時に2台に減らす
  - ScheduledActionName: night-scale-in
    Recurrence: "0 23 * * *"
    MinSize: 2
    MaxSize: 20
    DesiredCapacity: 2
```

#### 3. ライフサイクルフック

**スケールアウト時の処理:**
```
1. インスタンス起動
2. ライフサイクルフック: Pending:Wait
   → アプリケーションのウォームアップ
   → ヘルスチェック準備
   → ログエージェント起動
3. ライフサイクルフック: Pending:Proceed
4. ALBにターゲット登録
5. InService状態
```

**スケールイン時の処理:**
```
1. ライフサイクルフック: Terminating:Wait
   → 既存接続の完了を待つ(Connection Draining)
   → ログのアップロード
   → クリーンアップ処理
2. ライフサイクルフック: Terminating:Proceed
3. インスタンス削除
```

#### 4. セッション管理の課題と解決

**問題: スケールアウト時にセッションが失われる**

**解決策A: ElastiCache (Redis/Memcached):**
```python
# Djangoでの設定例
CACHES = {
    'default': {
        'BACKEND': 'django_redis.cache.RedisCache',
        'LOCATION': 'redis://elasticache.example.com:6379/1',
        'OPTIONS': {
            'CLIENT_CLASS': 'django_redis.client.DefaultClient',
        }
    }
}

SESSION_ENGINE = 'django.contrib.sessions.backends.cache'
SESSION_CACHE_ALIAS = 'default'
```

**解決策B: Sticky Session (非推奨):**
- ALBのスティッキーセッション機能
- 同じユーザーを同じインスタンスに振り分け
- スケーリングの効果を減少させるため非推奨

### オンプレミスでの同等構成

#### 1. 手動スケーリング（従来型）

**課題:**
```
速報ニュース発生
  ↓
サーバー負荷急上昇
  ↓
インフラ担当者に連絡（夜間・休日）
  ↓
データセンターに移動
  ↓
物理サーバー追加（数時間〜数日）
  ↓
OS/アプリインストール
  ↓
ロードバランサーに登録
```

**結果: 対応に数時間〜数日かかり、機会損失**

#### 2. 仮想化基盤での半自動スケーリング

**VMware vSphere + vRealize Automation:**

**テンプレート準備:**
```bash
# VMテンプレート作成
1. マスターVMを作成
2. アプリケーションをプリインストール
3. Sysprepで一般化
4. テンプレート化
```

**自動デプロイスクリプト:**
```python
# vSphere API使用例
from pyVim.connect import SmartConnect
from pyVmomi import vim

def clone_vm(template_name, vm_name):
    # テンプレートからVMをクローン
    template = get_vm(template_name)

    clone_spec = vim.vm.CloneSpec()
    clone_spec.location = vim.vm.RelocateSpec()
    clone_spec.powerOn = True
    clone_spec.template = False

    task = template.Clone(
        folder=get_folder(),
        name=vm_name,
        spec=clone_spec
    )

    wait_for_task(task)

    # ロードバランサーに登録
    add_to_load_balancer(vm_name)
```

**監視ツールと連携:**
```
Zabbix/Nagios
  ↓ CPU使用率監視
Webhook/API
  ↓ 閾値超過時
vRealize Automation
  ↓ VM自動デプロイ
新しいVM起動
  ↓
ロードバランサーに自動登録
```

**課題:**
- デプロイに5-10分かかる
- ライセンス費用が高額
- ストレージ容量の事前確保が必要
- 物理サーバーのキャパシティ限界

#### 3. Kubernetes (オンプレミス)

**Horizontal Pod Autoscaler (HPA):**
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web-app
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

**Cluster Autoscaler:**
```yaml
# ノード（物理サーバー/VM）のスケーリング
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-autoscaler
  namespace: kube-system
data:
  min-nodes: "3"
  max-nodes: "10"
```

**課題:**
- ノードのスケーリングには時間がかかる
- 物理サーバーは事前に用意が必要
- 複雑な運用が必要

#### 4. ロードバランサーの動的設定

**F5 BIG-IP iControl API:**
```python
import requests

def add_pool_member(server_ip):
    url = "https://bigip.example.com/mgmt/tm/ltm/pool/~Common~web_pool/members"

    payload = {
        "name": f"{server_ip}:80",
        "address": server_ip
    }

    response = requests.post(
        url,
        json=payload,
        auth=('admin', 'password'),
        verify=False
    )

    return response.json()

def remove_pool_member(server_ip):
    url = f"https://bigip.example.com/mgmt/tm/ltm/pool/~Common~web_pool/members/{server_ip}:80"

    response = requests.delete(
        url,
        auth=('admin', 'password'),
        verify=False
    )

    return response.status_code
```

**Nginx動的設定:**
```bash
# Consul Template使用例
# /etc/nginx/conf.d/upstream.conf.ctmpl
upstream backend {
{{- range service "web-app" }}
  server {{ .Address }}:{{ .Port }};
{{- end }}
}

# Consulに新しいサーバーを登録
curl -X PUT -d '{"ID": "web-1", "Name": "web-app", "Address": "192.168.1.10", "Port": 8080}' \
  http://localhost:8500/v1/agent/service/register

# Consul Templateが自動的にNginx設定を更新
# nginx reload
```

### オンプレミスとAWSの比較

| 項目 | オンプレミス | AWS Auto Scaling |
|------|------------|------------------|
| **スケーリング速度** | 5-30分<br>（VMクローン作成） | 1-5分<br>（AMIから起動） |
| **スケーリング限界** | 物理リソースに依存<br>（事前に購入済みのサーバー） | ほぼ無制限<br>（AWSの巨大なキャパシティ） |
| **初期投資** | 高額<br>ピーク時対応の機器を事前購入 | 低額<br>使った分だけ課金 |
| **設定の複雑さ** | 高い<br>仮想化基盤、監視、自動化ツール | 低い<br>GUIまたはIaCで簡単設定 |
| **運用負荷** | 高い<br>テンプレート管理、監視、障害対応 | 低い<br>AWS側で自動管理 |

### コスト比較シミュレーション

**シナリオ: 通常時4台、ピーク時16台が必要**

**オンプレミス（3年償却）:**
- サーバー16台分を常備: 1,600万円 ÷ 36ヶ月 = 約44万円/月
- 仮想化ライセンス: 約10万円/月
- ストレージ: 約5万円/月
- 運用コスト: 約30万円/月
- **合計: 約89万円/月**

**AWS Auto Scaling:**
- 通常時(4台 × 20時間/日): 約4万円/月
- ピーク時(16台 × 4時間/日): 約3万円/月
- ALB: 約0.3万円/月
- データ転送: 約2万円/月
- **合計: 約9.3万円/月**

**コスト削減率: 約90%**

## まとめ

Auto Scalingは、変動するトラフィックに対応する現代のWebアプリケーションに必須の機能です。

**AWSの利点:**
- **数分で自動スケーリング**（オンプレミスは数時間〜数日）
- **初期投資不要**（オンプレミスは数千万円必要）
- **完全自動化**（オンプレミスは複雑な運用）
- **コスト最適化**（最大90%削減）

**ベストプラクティス:**
1. Target Tracking Scalingを基本とする
2. 予測可能な負荷にはScheduled Scalingを併用
3. セッションは外部ストア（ElastiCache）に保存
4. CloudFrontで静的コンテンツをキャッシュ
5. RDS Read Replicaでデータベースもスケール
