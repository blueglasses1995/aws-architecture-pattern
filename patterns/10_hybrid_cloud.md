# パターン10: ハイブリッドクラウド接続

## 問題

既存のオンプレミスデータセンターを維持しつつ、AWSクラウドを活用したい企業があります。
以下の要件を満たすハイブリッドクラウドアーキテクチャーを設計してください。

**要件:**
- オンプレミスとAWS間でセキュアな通信
- 低レイテンシ（10ms以内）での接続
- 既存システムのクラウド移行を段階的に実施
- Active Directoryの統合認証
- オンプレミスDBとクラウドアプリの連携

## 推奨アーキテクチャー

```
[オンプレミスDC]
├─ Active Directory
├─ 既存業務システム
└─ Oracle/SQL Server DB
    ↓
[AWS Direct Connect]
 または
[Site-to-Site VPN]
    ↓
[AWS VPC]
├─ EC2 (クラウドアプリ)
├─ Directory Service (AD Connector)
└─ Storage Gateway (ハイブリッドストレージ)
    ↓
[AWS Services]
├─ S3 (オブジェクトストレージ)
├─ RDS (マネージドDB)
└─ Lambda (サーバーレス処理)
```

### 使用するAWSサービス:
- **Direct Connect / VPN**: オンプレミス接続
- **VPC**: 仮想ネットワーク
- **Directory Service**: AD統合
- **Storage Gateway**: ハイブリッドストレージ
- **Database Migration Service**: DB移行
- **Transit Gateway**: ネットワーク統合
- **Route 53 Resolver**: DNS統合

## 解説

### なぜこのアーキテクチャーなのか

#### 1. 接続方式の選択

**A. AWS Direct Connect（推奨）:**

**特徴:**
```
専用線接続:
├─ 帯域: 1Gbps / 10Gbps / 100Gbps
├─ レイテンシ: 1-10ms（低遅延）
├─ セキュリティ: プライベート接続
├─ 安定性: SLA 99.9%
└─ コスト: 月額固定費 + 転送量課金
```

**接続構成:**
```
オンプレミス
    ↓
[お客様ルーター]
    ↓
[DX Location] (東京、大阪等)
    ↓ 専用線
[AWS Direct Connect Endpoint]
    ↓
[Virtual Private Gateway / Transit Gateway]
    ↓
[VPC]
```

**冗長化構成:**
```
プライマリ経路:
オンプレミス → DX (東京) → VPC

セカンダリ経路:
オンプレミス → DX (大阪) → VPC

バックアップ:
オンプレミス → VPN → VPC
```

**B. Site-to-Site VPN:**

**特徴:**
```
インターネットVPN:
├─ 帯域: ~1Gbps（実効500Mbps程度）
├─ レイテンシ: 変動あり（10-50ms）
├─ セキュリティ: IPsec暗号化
├─ 安定性: インターネット依存
└─ コスト: 低コスト（時間課金 約$0.05/時間）
```

**設定例:**
```json
{
  "CustomerGatewayConfiguration": {
    "CustomerGatewayId": "cgw-12345678",
    "IpAddress": "203.0.113.1",
    "BgpAsn": 65000
  },
  "VpnGatewayId": "vgw-12345678",
  "Type": "ipsec.1",
  "Options": {
    "StaticRoutesOnly": false,
    "TunnelOptions": [
      {
        "TunnelInsideCidr": "169.254.10.0/30",
        "PreSharedKey": "MyPreSharedKey123"
      },
      {
        "TunnelInsideCidr": "169.254.11.0/30",
        "PreSharedKey": "MyPreSharedKey456"
      }
    ]
  }
}
```

**選択基準:**
```
Direct Connect を選ぶべき場合:
├─ 大量のデータ転送（> 1TB/月）
├─ 低レイテンシが必須（< 10ms）
├─ 安定した帯域が必要
└─ コンプライアンス要件（専用線必須）

VPN を選ぶべき場合:
├─ 初期コストを抑えたい
├─ 小規模なデータ転送（< 100GB/月）
├─ 短期間の利用
└─ テスト・検証用途
```

#### 2. Active Directory統合

**A. AWS Directory Service (AD Connector):**

**仕組み:**
```
AWSアプリケーション
    ↓
[AD Connector] (プロキシ)
    ↓ Direct Connect / VPN
[オンプレミス Active Directory]
```

**設定例:**
```json
{
  "Name": "corp.example.com",
  "Size": "Small",
  "ConnectSettings": {
    "VpcId": "vpc-12345678",
    "SubnetIds": ["subnet-12345678", "subnet-87654321"],
    "CustomerDnsIps": ["192.168.1.10", "192.168.1.11"],
    "CustomerUserName": "Administrator"
  }
}
```

**用途:**
- EC2のドメイン参加
- AWS WorkSpaces/WorkDocs の認証
- AWS Management Console の SAML認証

**B. AWS Managed Microsoft AD:**

**仕組み:**
```
[オンプレミス AD] ⇄ Trust関係 ⇄ [AWS Managed AD]
    ↓                               ↓
既存ユーザー                     AWSアプリ
```

**設定例:**
```bash
# オンプレミスADとの信頼関係作成
aws ds create-trust \
  --directory-id d-12345678 \
  --remote-domain-name onprem.example.com \
  --trust-password MyTrustPassword \
  --trust-direction Two-Way \
  --trust-type Forest
```

#### 3. ハイブリッドストレージ

**AWS Storage Gateway:**

**ファイルゲートウェイ（NFSv3/SMB）:**
```
オンプレミスアプリ
    ↓ NFS/SMB
[Storage Gateway VM] (キャッシュ)
    ↓
[S3 Bucket]
```

**使用例:**
```bash
# オンプレミスからマウント
mount -t nfs -o nolock,hard \
  192.168.1.100:/export/mybucket \
  /mnt/s3bucket

# ファイル書き込み → 自動的にS3へアップロード
cp /data/large-file.dat /mnt/s3bucket/
```

**ボリュームゲートウェイ（iSCSI）:**
```
オンプレミスアプリ
    ↓ iSCSI
[Storage Gateway] (キャッシュ)
    ↓
[S3 (EBS スナップショット)]
```

**キャッシュボリューム:**
```
頻繁にアクセスされるデータ: ローカルキャッシュ（高速）
それ以外のデータ: S3（低コスト）
```

#### 4. データベース移行戦略

**AWS Database Migration Service (DMS):**

**フェーズ1: 初期レプリケーション:**
```
[オンプレミス Oracle]
    ↓ DMS (初期フルコピー)
[RDS Oracle / Aurora PostgreSQL]
```

**設定例:**
```json
{
  "ReplicationInstanceIdentifier": "dms-instance",
  "ReplicationInstanceClass": "dms.c5.xlarge",
  "AllocatedStorage": 100,
  "VpcSecurityGroupIds": ["sg-12345678"],
  "ReplicationSubnetGroupIdentifier": "dms-subnet-group",
  "MultiAZ": true,
  "EngineVersion": "3.4.7"
}
```

**タスク設定:**
```json
{
  "SourceEndpoint": {
    "ServerName": "oracle.onprem.local",
    "Port": 1521,
    "DatabaseName": "ORCL",
    "Username": "dms_user",
    "Password": "password",
    "EngineName": "oracle"
  },
  "TargetEndpoint": {
    "ServerName": "mydb.xxxx.ap-northeast-1.rds.amazonaws.com",
    "Port": 5432,
    "DatabaseName": "postgres",
    "Username": "admin",
    "Password": "password",
    "EngineName": "aurora-postgresql"
  },
  "MigrationType": "full-load-and-cdc",  # 初期コピー + 継続的レプリケーション
  "TableMappings": {
    "rules": [
      {
        "rule-type": "selection",
        "rule-id": "1",
        "rule-name": "include-all-tables",
        "object-locator": {
          "schema-name": "HR",
          "table-name": "%"
        },
        "rule-action": "include"
      }
    ]
  }
}
```

**フェーズ2: カットオーバー:**
```
1. DMSでデータ同期を継続
2. アプリケーションをメンテナンスモードに
3. 最終的なデータ同期確認
4. アプリケーションの接続先をRDSに変更
5. サービス再開
```

### オンプレミスでの同等構成

#### 1. マルチデータセンター接続

**専用線（MPLS / 広域イーサネット）:**
```
[東京DC] ⇄ 専用線（100Mbps-10Gbps）⇄ [大阪DC]
```

**コスト:**
- 初期費用: 50-200万円
- 月額費用: 10-100万円（帯域による）
- 契約期間: 通常2-3年

**VPNトンネル（IPsec）:**
```
[東京DC]
    ↓
[ファイアウォール]
    ↓ インターネット（IPsec暗号化）
[リモートサイト ファイアウォール]
    ↓
[リモートサイト]
```

**Cisco ASA 設定例:**
```
! IKEv2 設定
crypto ikev2 policy 10
 encryption aes-256
 integrity sha256
 group 14
 prf sha256
 lifetime seconds 86400

crypto ikev2 keyring KEYRING
 peer REMOTE-SITE
  address 203.0.113.100
  pre-shared-key MySecretKey

! IPsec設定
crypto ipsec transform-set ESP-AES256-SHA256 esp-aes-256 esp-sha256-hmac
 mode tunnel

crypto ipsec profile IPSEC-PROFILE
 set transform-set ESP-AES256-SHA256
 set ikev2-profile IKEV2-PROFILE

! トンネルインターフェース
interface Tunnel0
 ip address 10.0.0.1 255.255.255.252
 tunnel source GigabitEthernet0/0
 tunnel destination 203.0.113.100
 tunnel mode ipsec ipv4
 tunnel protection ipsec profile IPSEC-PROFILE
```

#### 2. ストレージレプリケーション

**SAN レプリケーション:**
```
[東京DC SAN] ⇄ 同期/非同期レプリケーション ⇄ [大阪DC SAN]
```

**NetApp SnapMirror:**
```bash
# SnapMirror 関係作成
snapmirror create -source-path svm1:vol1 \
  -destination-path svm2:vol1_mirror \
  -type XDP \
  -policy MirrorAllSnapshots

# レプリケーション実行
snapmirror initialize -destination-path svm2:vol1_mirror

# 状態確認
snapmirror show
```

**Dell EMC RecoverPoint:**
- 同期/非同期レプリケーション
- RPO: 数秒〜数分
- コスト: 数百万円〜数千万円

#### 3. Active Directory サイト間レプリケーション

**ADレプリケーション:**
```
[東京DC]
├─ DC1 (ドメインコントローラー)
├─ DC2 (ドメインコントローラー)
    ↓ AD レプリケーション
[大阪DC]
├─ DC3 (ドメインコントローラー)
└─ DC4 (ドメインコントローラー)
```

**サイト設定:**
```powershell
# ADサイト作成
New-ADReplicationSite -Name "Tokyo"
New-ADReplicationSite -Name "Osaka"

# サブネット割り当て
New-ADReplicationSubnet -Name "192.168.1.0/24" -Site "Tokyo"
New-ADReplicationSubnet -Name "192.168.2.0/24" -Site "Osaka"

# サイトリンク設定
New-ADReplicationSiteLink -Name "Tokyo-Osaka" \
  -SitesIncluded "Tokyo","Osaka" \
  -Cost 100 \
  -ReplicationFrequencyInMinutes 15
```

#### 4. データベースレプリケーション

**Oracle DataGuard:**
```sql
-- プライマリDB
ALTER SYSTEM SET LOG_ARCHIVE_DEST_2=
  'SERVICE=standby LGWR ASYNC VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=standby';

-- スタンバイDB（別DC）
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT FROM SESSION;
```

**SQL Server Always On:**
```sql
-- 可用性グループ作成
CREATE AVAILABILITY GROUP [AG1]
FOR DATABASE [MyDatabase]
REPLICA ON
  'TOKYO-SQL01' WITH (
    ENDPOINT_URL = 'TCP://tokyo-sql01.example.com:5022',
    AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
    FAILOVER_MODE = AUTOMATIC
  ),
  'OSAKA-SQL01' WITH (
    ENDPOINT_URL = 'TCP://osaka-sql01.example.com:5022',
    AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
    FAILOVER_MODE = MANUAL
  );
```

### オンプレミスとAWSの比較

| 項目 | オンプレミス（マルチDC） | AWS Hybrid |
|------|---------------------|-----------|
| **接続構築期間** | 2-6ヶ月<br>回線申込、工事 | 数日〜2週間<br>Direct Connect |
| **初期費用** | 高額（数百万円）<br>回線工事、機器 | 低額（数万円）<br>機器のみ |
| **月額コスト** | 高額（50-200万円）<br>回線、DC費用 | 中程度（10-50万円）<br>従量課金中心 |
| **帯域拡張** | 困難<br>回線再契約、工事 | 容易<br>LAG追加、即時 |
| **運用負荷** | 高い<br>両DC管理、回線管理 | 低い<br>AWSはマネージド |

### コスト比較

**オンプレミス（マルチDC、10Gbps専用線）:**
- 初期費用: 約300万円
- 専用線月額: 約150万円/月
- 両DC運用: 約200万円/月
- **合計: 約350万円/月（初期費用別）**

**AWS Hybrid（Direct Connect 10Gbps）:**
- 初期費用: 約30万円（ルーター等）
- Direct Connectポート: 約22万円/月
- データ転送（1TB/月）: 約10万円/月
- VPC、サービス利用: 約20万円/月
- **合計: 約52万円/月**

**コスト削減率: 約85%**

## まとめ

ハイブリッドクラウドは、既存資産を活かしつつクラウドの利点を享受できます。

**AWSでの利点:**
- **Direct Connect で低レイテンシ接続**
- **段階的なクラウド移行**
- **AD統合で既存認証活用**
- **Storage Gateway でシームレスなストレージ統合**
- **DMS で簡単なDB移行**

**ベストプラクティス:**
1. Direct Connect + VPN の冗長化構成
2. Transit Gateway で複数VPC統合
3. AD Connector / Managed AD でシングルサインオン
4. Storage Gateway でデータ段階的移行
5. DMS で継続的レプリケーション
6. Route 53 Resolver でDNS統合

**移行ステップ:**
1. Direct Connect / VPN構築
2. Storage Gateway でストレージ統合
3. 開発環境をクラウド化
4. 段階的にワークロード移行
5. DR環境としてクラウド活用
6. 最終的に本番環境移行
