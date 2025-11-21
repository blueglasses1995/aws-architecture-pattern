# パターン1: 基本的な3層Webアプリケーション

## 問題

あなたの会社は、オンラインショッピングサイトを構築する予定です。以下の要件を満たすAWSアーキテクチャーを設計してください。

**要件:**
- Webサーバー、アプリケーションサーバー、データベースの3層構成
- 月間10万PV程度のトラフィック
- 可用性は99%以上
- データベースには顧客情報と商品情報を格納
- SSLによる暗号化通信が必要

## 推奨アーキテクチャー

```
Internet
    ↓
Application Load Balancer (ALB)
    ↓
EC2 (Web/Appサーバー) × 2台以上
    ↓
RDS (MySQL/PostgreSQL) - Multi-AZ構成
```

### 使用するAWSサービス:
- **VPC**: 仮想ネットワーク
- **Application Load Balancer (ALB)**: レイヤー7ロードバランサー
- **EC2**: Webサーバー/アプリケーションサーバー
- **RDS**: リレーショナルデータベース（Multi-AZ）
- **Route 53**: DNS
- **ACM**: SSL証明書管理

## 解説

### なぜこのアーキテクチャーなのか

#### 1. Application Load Balancer (ALB)を使う理由

**負荷分散とヘルスチェック:**
- 複数のEC2インスタンスにトラフィックを均等に分散
- ヘルスチェック機能により、異常なインスタンスを自動的に切り離し
- SSL/TLS終端をALBで行うことで、EC2の負荷を軽減

**スケーラビリティ:**
- トラフィックの増減に応じて自動的にスケール
- 固定IPアドレスの管理が不要（DNSベース）

**セキュリティ:**
- AWS Certificate Manager (ACM)と統合してSSL証明書を無料で管理
- セキュリティグループでアクセス制御

#### 2. EC2を複数台配置する理由

**高可用性:**
- 最低2台を異なるアベイラビリティゾーン(AZ)に配置
- 1台が故障しても、もう1台で継続稼働

**メンテナンス性:**
- ローリングアップデートが可能
- ダウンタイムなしでアプリケーションを更新

#### 3. RDS Multi-AZ構成を使う理由

**自動フェイルオーバー:**
- プライマリDBが故障した場合、自動的にスタンバイに切り替え
- 通常1-2分でフェイルオーバー完了

**自動バックアップ:**
- ポイントインタイムリカバリが可能
- 最大35日間のバックアップ保持

**パッチ適用の自動化:**
- メンテナンスウィンドウで自動的にパッチ適用
- フェイルオーバーを活用してダウンタイム最小化

### オンプレミスでの同等構成

オンプレミスで同じ構成を実現する場合、以下のような機器とソフトウェアが必要です：

#### 1. ロードバランサー層

**ハードウェアロードバランサー:**
- F5 BIG-IP
- Citrix NetScaler (ADC)
- A10 Networks Thunder ADC

**ソフトウェアロードバランサー:**
- Nginx (nginx.conf設定例)
  ```nginx
  upstream backend {
      server app-server-1:8080;
      server app-server-2:8080;
  }

  server {
      listen 443 ssl;
      server_name www.example.com;

      ssl_certificate /etc/nginx/ssl/server.crt;
      ssl_certificate_key /etc/nginx/ssl/server.key;

      location / {
          proxy_pass http://backend;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
      }
  }
  ```

- HAProxy
  ```
  frontend http-in
      bind *:443 ssl crt /etc/ssl/certs/cert.pem
      default_backend servers

  backend servers
      balance roundrobin
      server server1 192.168.1.10:8080 check
      server server2 192.168.1.11:8080 check
  ```

**冗長化構成:**
- ロードバランサーを2台用意し、VRRP (Virtual Router Redundancy Protocol)で冗長化
- Keepalivedを使った仮想IP管理

#### 2. アプリケーションサーバー層

**物理/仮想サーバー:**
- Dell PowerEdge、HP ProLiant等の物理サーバー
- VMware vSphere、KVM等の仮想化基盤上のVM

**Webサーバー/APサーバー:**
- Apache HTTP Server + Tomcat
- Nginx + uWSGI/Gunicorn
- IIS + .NET

#### 3. データベース層

**データベースサーバー:**
- MySQL/PostgreSQL/Oracle/SQL Serverの商用またはOSS版
- マスター・スレーブ構成（レプリケーション）
  ```sql
  -- MySQLのマスター設定例
  [mysqld]
  server-id = 1
  log-bin = mysql-bin
  binlog-do-db = production_db

  -- スレーブ設定例
  [mysqld]
  server-id = 2
  relay-log = mysql-relay-bin
  ```

**共有ストレージ:**
- SAN (Storage Area Network)
- NAS (Network Attached Storage)
- データベースクラスタリング（Oracle RAC、PostgreSQL + Patroni等）

#### 4. ネットワーク機器

**ファイアウォール:**
- Cisco ASA
- Palo Alto Networks
- Fortinet FortiGate

**スイッチ:**
- Cisco Catalyst (レイヤー3スイッチ)
- VLAN設定でネットワークセグメント分離

**ルーター:**
- Cisco ISR (Integrated Services Router)
- インターネット接続用

### オンプレミスとAWSの比較

| 項目 | オンプレミス | AWS |
|------|------------|-----|
| **初期コスト** | 高額（数百万〜数千万円）<br>- サーバー購入<br>- ネットワーク機器<br>- ラック、電源、冷房設備 | 低額（従量課金）<br>- 初期投資ほぼゼロ |
| **構築期間** | 2-3ヶ月<br>- 機器調達<br>- データセンター準備<br>- 設置・配線・設定 | 数時間〜数日<br>- コンソールまたはIaCで即座に構築 |
| **運用負荷** | 高<br>- ハードウェア障害対応<br>- OS/ミドルウェアパッチ適用<br>- 物理的な保守作業 | 低<br>- マネージドサービスで大部分を自動化<br>- AWS側でハードウェア管理 |
| **スケーラビリティ** | 困難<br>- サーバー追加に時間とコスト<br>- キャパシティプランニングが必須 | 容易<br>- Auto Scalingで自動スケール<br>- 需要に応じて柔軟に調整 |
| **冗長化コスト** | 高額<br>- 全ての機器を2重化<br>- 待機系も同等のコスト | 比較的低額<br>- Multi-AZは追加コスト小<br>- 使った分だけ課金 |

### コスト試算例（月額）

**オンプレミス（3年償却）:**
- サーバー機器: 500万円 ÷ 36ヶ月 = 約14万円/月
- ネットワーク機器: 300万円 ÷ 36ヶ月 = 約8万円/月
- データセンター費用: 約10万円/月
- 運用人件費: 約50万円/月（1-2名）
- **合計: 約82万円/月**

**AWS:**
- ALB: 約3,000円/月
- EC2 (t3.medium × 2): 約10,000円/月
- RDS (db.t3.medium Multi-AZ): 約25,000円/月
- データ転送: 約5,000円/月
- **合計: 約43,000円/月**

※運用人件費を除外すれば、AWSは大幅にコスト削減可能

## まとめ

3層Webアプリケーションは、AWSで最も基本的かつ重要なアーキテクチャーパターンです。
オンプレミスと比較して、AWSでは：

- **初期投資を大幅に削減**
- **運用負荷を軽減**（マネージドサービスの活用）
- **柔軟なスケーラビリティ**
- **高可用性を低コストで実現**

このパターンをベースに、Auto Scaling、CloudFront、WAF等を追加することで、
より高度なアーキテクチャーに発展させることができます。
