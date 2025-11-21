# パターン15: RDSリードレプリカ構成

## 問題

読み取り負荷が高いアプリケーションで、データベースのスケーリングが必要です。

## 推奨アーキテクチャー

```
[アプリケーション]
├─ 書き込み → [RDS Master]
│                 ↓ 非同期レプリケーション
└─ 読み取り → [RDS Read Replica × 5]
               ├─ レプリカ1（分析用）
               ├─ レプリカ2（レポート用）
               ├─ レプリカ3（Web表示用）
               ├─ レプリカ4（API用）
               └─ レプリカ5（DR用、別リージョン）
```

### 使用するAWSサービス:
- **RDS Read Replica**: 読み取りスケーリング
- **Aurora**: 最大15個のリードレプリカ
- **ProxySQL**: 読み書き分離プロキシ

## 解説

**リードレプリカ作成:**
```bash
aws rds create-db-instance-read-replica \
  --db-instance-identifier mydb-replica-1 \
  --source-db-instance-identifier mydb-master
```

**読み書き分離（アプリ側）:**
```python
# Django設定例
DATABASES = {
    'default': {  # 書き込み
        'ENGINE': 'django.db.backends.mysql',
        'HOST': 'mydb-master.xxxx.rds.amazonaws.com',
        'NAME': 'mydb',
    },
    'read_replica': {  # 読み取り
        'ENGINE': 'django.db.backends.mysql',
        'HOST': 'mydb-replica.xxxx.rds.amazonaws.com',
        'NAME': 'mydb',
    }
}

DATABASE_ROUTERS = ['myapp.db_router.ReplicaRouter']
```

### オンプレミス

**MySQL Master-Slave:**
```sql
-- Master設定
[mysqld]
server-id = 1
log-bin = mysql-bin

-- Slave設定
[mysqld]
server-id = 2
relay-log = mysql-relay-bin

CHANGE MASTER TO
  MASTER_HOST='192.168.1.10',
  MASTER_USER='repl',
  MASTER_PASSWORD='password',
  MASTER_LOG_FILE='mysql-bin.000001',
  MASTER_LOG_POS=107;

START SLAVE;
```

**課題:**
- レプリケーション遅延の監視
- スレーブ追加の手間
- 障害時の手動昇格

## まとめ

RDS Read Replicaで簡単に読み取りスケーリングが可能です。

**ベストプラクティス:**
1. 用途別にリードレプリカを分ける
2. レプリケーション遅延を監視
3. 別リージョンにDR用レプリカ
