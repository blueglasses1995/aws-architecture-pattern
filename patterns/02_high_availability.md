# パターン2: 高可用性構成（Multi-AZ）

## 問題

金融機関向けの取引システムをAWSで構築します。以下の要件を満たす高可用性アーキテクチャーを設計してください。

**要件:**
- SLA 99.99%（年間ダウンタイム52分以内）
- 単一障害点(SPOF)の排除
- データの完全性保証
- 障害発生時の自動復旧
- リージョン内での冗長化

## 推奨アーキテクチャー

```
[Route 53]
    ↓
[CloudFront] (オプション)
    ↓
[ALB - Multi-AZ]
    ↓
[AZ-1a]              [AZ-1c]
EC2 × 2              EC2 × 2
    ↓                    ↓
[RDS Primary AZ-1a] ⇄ [RDS Standby AZ-1c]
                    (同期レプリケーション)
```

### 使用するAWSサービス:
- **Route 53**: DNSフェイルオーバー
- **ALB**: 複数AZに自動配置
- **EC2**: 複数AZに分散配置
- **RDS Multi-AZ**: 自動フェイルオーバー
- **EBS**: 自動レプリケーション
- **S3**: 11 9's の耐久性

## 解説

### なぜこのアーキテクチャーなのか

#### 1. Multi-AZ構成の重要性

**アベイラビリティゾーン(AZ)とは:**
- 物理的に離れた複数のデータセンター群
- 独立した電源、ネットワーク、冷却設備
- AZ間は低遅延ネットワークで接続（通常1ms未満）

**Multi-AZ配置の利点:**
```
単一AZ: 99.5% SLA
Multi-AZ: 99.99% SLA（約20倍の可用性向上）
```

- データセンター全体の障害に対応
- 計画メンテナンス時もサービス継続
- ネットワーク分断への耐性

#### 2. ALB Multi-AZ配置

**ALBの自動Multi-AZ配置:**
- 最低2つのAZを選択（推奨は3つ以上）
- 各AZに自動的にロードバランサーノードを配置
- 1つのAZが完全に停止してもサービス継続

**ヘルスチェックの詳細設定:**
```yaml
HealthCheckPath: /health
HealthCheckIntervalSeconds: 30
HealthCheckTimeoutSeconds: 5
HealthyThresholdCount: 2
UnhealthyThresholdCount: 3
```

#### 3. EC2の配置戦略

**配置グループ(Placement Group)の活用:**

**パーティション配置グループ:**
```
AZ-1a:
  Partition-1: EC2-1, EC2-2
  Partition-2: EC2-3, EC2-4

AZ-1c:
  Partition-1: EC2-5, EC2-6
  Partition-2: EC2-7, EC2-8
```
- 各パーティションは異なるハードウェアラック
- ラック障害の影響を局所化

#### 4. RDS Multi-AZの仕組み

**同期レプリケーション:**
```
アプリケーション → [Primary DB]
                      ↓ 同期書き込み
                   [Standby DB]
```

**フェイルオーバーの流れ:**
1. Primaryの障害検知（通常30-60秒）
2. StandbyをPrimaryに昇格
3. DNS CNAMEレコードを自動更新
4. アプリケーションは自動再接続（通常1-2分）

**注意点:**
- 書き込みパフォーマンスが若干低下（同期待ち）
- Standbyからは読み取り不可（リードレプリカではない）

### オンプレミスでの同等構成

#### 1. データセンター冗長化

**最低2つのデータセンター:**

**DC-1 (Primary Site):**
- メインのアプリケーションサーバー
- マスターデータベース
- ストレージシステム

**DC-2 (Secondary Site):**
- スタンバイアプリケーションサーバー
- スレーブデータベース
- レプリケーション用ストレージ

**DC間接続:**
- 専用線（10Gbps以上推奨）
- ダークファイバー or MPLS
- 距離: 数km〜数十km
- コスト: 月額数十万円〜数百万円

#### 2. ロードバランサー冗長化

**VRRPによる冗長化:**

```
[Internet]
    ↓
[Virtual IP: 192.168.1.100]
    ↓
[LB-1 (Master)]    [LB-2 (Backup)]
  Priority: 100      Priority: 90
    ↓                    ↓
[App Servers]
```

**Keepalived設定例:**
```conf
# LB-1 (Master)
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass secret123
    }

    virtual_ipaddress {
        192.168.1.100
    }
}

# LB-2 (Backup)
vrrp_instance VI_1 {
    state BACKUP
    interface eth0
    virtual_router_id 51
    priority 90
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass secret123
    }

    virtual_ipaddress {
        192.168.1.100
    }
}
```

#### 3. データベース冗長化

**パターンA: Master-Slave レプリケーション + 自動フェイルオーバー**

**MHA (Master High Availability) for MySQL:**
```perl
# MHA設定例
[server default]
manager_workdir=/var/log/mha
manager_log=/var/log/mha/manager.log
remote_workdir=/var/log/mha

[server1]
hostname=db1.example.com
candidate_master=1
check_repl_delay=0

[server2]
hostname=db2.example.com
candidate_master=1
check_repl_delay=0

[server3]
hostname=db3.example.com
no_master=1
```

**PostgreSQL + Patroni + etcd:**
```yaml
# Patroni設定例
scope: postgres-cluster
namespace: /db/
name: postgres1

restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.1.10:8008

etcd:
  hosts: 192.168.1.20:2379,192.168.1.21:2379,192.168.1.22:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.1.10:5432
  data_dir: /var/lib/postgresql/data
  pgpass: /tmp/pgpass

  authentication:
    replication:
      username: replicator
      password: rep_password
    superuser:
      username: postgres
      password: super_password
```

**パターンB: 共有ストレージ型クラスタ**

**Oracle RAC (Real Application Clusters):**
```
[Node1]     [Node2]     [Node3]
   ↓           ↓           ↓
    ← [共有ストレージ(SAN)] →
```

- ASM (Automatic Storage Management)
- クラスタウェア (Grid Infrastructure)
- 高額なライセンスコスト

#### 4. ストレージ冗長化

**RAID構成:**
```
RAID 1: ミラーリング（冗長性重視）
RAID 5: パリティ分散（容量効率重視）
RAID 10: RAID1+0（性能と冗長性の両立）
```

**SAN レプリケーション:**
```
DC-1 [SAN-1] ⇄ 同期/非同期レプリケーション ⇄ DC-2 [SAN-2]
```

使用製品例:
- Dell EMC PowerStore/Unity
- NetApp FAS/AFF
- HPE 3PAR

#### 5. ネットワーク冗長化

**スイッチのスタック/VSS構成:**

**Cisco StackWise:**
```
[Core Switch 1] ⇄ StackWise Cable ⇄ [Core Switch 2]
        ↓                                    ↓
[Access Switch]                     [Access Switch]
```

**HSRP (Hot Standby Router Protocol):**
```
[Router 1]    [Router 2]
  Active       Standby
    ↓              ↓
  [Virtual Gateway: 192.168.1.1]
```

```
interface GigabitEthernet0/0
 ip address 192.168.1.2 255.255.255.0
 standby 1 ip 192.168.1.1
 standby 1 priority 110
 standby 1 preempt
```

### オンプレミスとAWSの比較

| 項目 | オンプレミス | AWS Multi-AZ |
|------|------------|--------------|
| **構築複雑度** | 非常に高い<br>- 複数DC<br>- レプリケーション設定<br>- フェイルオーバー設計 | 低い<br>- チェックボックス1つ<br>- 自動設定 |
| **初期投資** | 非常に高額（億単位）<br>- 2つのDC<br>- 2重化された機器<br>- 専用線 | 低額<br>- 追加コスト小（約2倍）<br>- 初期投資不要 |
| **フェイルオーバー時間** | 5-30分<br>- 手動操作必要な場合あり<br>- DNS切り替え<br>- 動作確認 | 1-2分<br>- 完全自動<br>- DNS自動更新 |
| **運用難易度** | 高い<br>- レプリケーション監視<br>- フェイルオーバー訓練<br>- 手順書整備 | 低い<br>- AWS側で自動管理<br>- 監視はCloudWatch |
| **テストの容易性** | 困難<br>- 本番環境でのテスト困難<br>- 障害訓練には計画必要 | 容易<br>- RDS強制フェイルオーバー機能<br>- いつでもテスト可能 |

### コスト比較（年間）

**オンプレミス（5年償却）:**
- DC設備投資: 1億円 ÷ 5年 = 2,000万円/年
- サーバー/NW機器: 5,000万円 ÷ 5年 = 1,000万円/年
- 専用線: 50万円/月 × 12ヶ月 = 600万円/年
- DC利用料: 100万円/月 × 12ヶ月 = 1,200万円/年
- 運用人件費: 80万円/月 × 12ヶ月 = 960万円/年
- **合計: 約5,760万円/年**

**AWS Multi-AZ:**
- EC2 (c5.xlarge × 4): 約70万円/年
- RDS Multi-AZ (db.r5.xlarge): 約240万円/年
- ALB: 約4万円/年
- データ転送: 約20万円/年
- **合計: 約334万円/年**

※運用人件費を含めてもAWSは大幅に低コスト

## まとめ

高可用性を実現するには、オンプレミスでは莫大なコストと複雑な設計が必要ですが、
AWSのMulti-AZ構成を使えば：

- **簡単に99.99%のSLAを達成**
- **自動フェイルオーバーで運用負荷削減**
- **初期投資を大幅に削減**
- **テストとメンテナンスが容易**

金融、医療、基幹システムなど、高可用性が求められるシステムには必須のパターンです。
