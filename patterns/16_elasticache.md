# パターン16: ElastiCacheによる高速化

## 問題

データベースの読み取り負荷が高く、レスポンスタイムを改善したい。

## 推奨アーキテクチャー

```
[アプリケーション]
    ↓ キャッシュチェック
[ElastiCache (Redis)]
├─ キャッシュヒット → 即座にレスポンス（1-5ms）
└─ キャッシュミス
    ↓
[RDS]（100-500ms）
    ↓ キャッシュに保存
[ElastiCache]
```

### 使用するAWSサービス:
- **ElastiCache for Redis**: インメモリキャッシュ
- **ElastiCache for Memcached**: シンプルなキャッシュ

## 解説

**Redis vs Memcached:**

| 機能 | Redis | Memcached |
|------|-------|-----------|
| データ構造 | 豊富（文字列、リスト、セット等） | Key-Value のみ |
| 永続化 | 可能 | 不可 |
| レプリケーション | 可能 | 不可 |
| トランザクション | 可能 | 不可 |
| 用途 | セッション、ランキング | シンプルなキャッシュ |

**Redis使用例:**
```python
import redis

# Redis接続
r = redis.Redis(
    host='my-redis.xxxx.cache.amazonaws.com',
    port=6379,
    decode_responses=True
)

def get_user(user_id):
    # キャッシュチェック
    cache_key = f'user:{user_id}'
    cached = r.get(cache_key)

    if cached:
        return json.loads(cached)

    # DB から取得
    user = db.query('SELECT * FROM users WHERE id = %s', user_id)

    # キャッシュに保存（TTL 1時間）
    r.setex(cache_key, 3600, json.dumps(user))

    return user
```

**セッション管理:**
```python
# Flask-Sessionでの設定
from flask import Flask, session
from flask_session import Session

app = Flask(__name__)
app.config['SESSION_TYPE'] = 'redis'
app.config['SESSION_REDIS'] = redis.Redis(
    host='my-redis.xxxx.cache.amazonaws.com',
    port=6379
)
Session(app)
```

### オンプレミス

**Redis Cluster:**
```bash
# Redis Cluster作成（6ノード）
redis-cli --cluster create \
  192.168.1.11:6379 192.168.1.12:6379 192.168.1.13:6379 \
  192.168.1.14:6379 192.168.1.15:6379 192.168.1.16:6379 \
  --cluster-replicas 1
```

**課題:**
- クラスタ管理の複雑さ
- フェイルオーバー設定
- バックアップ運用

**ElastiCache:**
- 自動フェイルオーバー
- 自動バックアップ
- マネージド運用

## まとめ

ElastiCacheでレスポンスタイムを90%以上改善可能です。

**ベストプラクティス:**
1. 頻繁にアクセスされるデータをキャッシュ
2. 適切なTTL設定
3. Cache-Asideパターン推奨
4. Redis Cluster Modeで高可用性
