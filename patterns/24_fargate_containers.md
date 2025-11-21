# パターン24: Fargateコンテナ運用

## 問題

コンテナを使いたいが、EC2管理は避けたい。

## 推奨アーキテクチャー

```
[ECS Fargate]
├─ タスク定義
│   ├─ vCPU: 0.25〜16
│   ├─ Memory: 0.5GB〜120GB
│   └─ コンテナイメージ（ECR）
├─ サービス
│   ├─ 希望タスク数: 3
│   ├─ Auto Scaling
│   └─ ALB統合
└─ インフラ管理不要
```

### タスク定義例

```json
{
  "family": "web-app",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [
    {
      "name": "web",
      "image": "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/web:latest",
      "portMappings": [{
        "containerPort": 80,
        "protocol": "tcp"
      }],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/web-app",
          "awslogs-region": "ap-northeast-1",
          "awslogs-stream-prefix": "web"
        }
      }
    }
  ]
}
```

## EC2 vs Fargate

| 項目 | EC2 | Fargate |
|------|-----|---------|
| インフラ管理 | 必要 | 不要 |
| 起動時間 | 数分 | 数十秒 |
| コスト | 安い（長時間稼働） | 高い（短時間利用向け） |
| スケーリング | EC2追加が必要 | 即座にスケール |

## まとめ

Fargateでサーバー管理不要のコンテナ運用を実現。

**ベストプラクティス:**
1. 短時間タスクに最適
2. Auto Scalingで柔軟にスケール
3. Spot Fargate でコスト削減
