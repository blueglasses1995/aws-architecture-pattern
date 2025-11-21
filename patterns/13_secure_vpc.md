# パターン13: セキュアなVPC設計

## 問題

金融機関向けシステムで、セキュリティ要件が厳しい環境を構築します。

**要件:**
- インターネットからの直接アクセス禁止
- DMZ、アプリケーション層、DB層の3層分離
- プライベートサブネットからのインターネットアクセス
- 全通信ログの記録
- VPC間の安全な通信

## 推奨アーキテクチャー

```
[Internet]
    ↓
[Internet Gateway]
    ↓
[パブリックサブネット]
├─ NAT Gateway
└─ ALB（DMZ）
    ↓
[プライベートサブネット（アプリ層）]
├─ EC2（アプリケーション）
└─ VPC Endpoint
    ↓
[プライベートサブネット（DB層）]
└─ RDS（インターネット接続なし）

[セキュリティ機能]
├─ Security Group（ステートフル）
├─ Network ACL（ステートレス）
├─ VPC Flow Logs
├─ GuardDuty（脅威検知）
└─ WAF（Web攻撃防御）
```

### 使用するAWSサービス:
- **VPC**: 仮想ネットワーク
- **Security Group / NACL**: ファイアウォール
- **NAT Gateway**: アウトバウンド通信
- **VPC Endpoint**: AWSサービスへのプライベート接続
- **VPC Flow Logs**: 通信ログ
- **GuardDuty**: 脅威検知
- **WAF**: Webアプリケーションファイアウォール

## 解説

### VPC設計ベストプラクティス

**1. サブネット分離:**
```
10.0.0.0/16（VPC）
├─ 10.0.1.0/24（パブリック-AZ1）
├─ 10.0.2.0/24（パブリック-AZ2）
├─ 10.0.11.0/24（プライベート-アプリ-AZ1）
├─ 10.0.12.0/24（プライベート-アプリ-AZ2）
├─ 10.0.21.0/24（プライベート-DB-AZ1）
└─ 10.0.22.0/24（プライベート-DB-AZ2）
```

**2. Security Group（最小権限）:**
```json
// ALB Security Group
{
  "IpProtocol": "tcp",
  "FromPort": 443,
  "ToPort": 443,
  "IpRanges": [{"CidrIp": "0.0.0.0/0"}]
}

// App Security Group
{
  "IpProtocol": "tcp",
  "FromPort": 8080,
  "ToPort": 8080,
  "SourceSecurityGroupId": "sg-alb-12345"  // ALBからのみ許可
}

// DB Security Group
{
  "IpProtocol": "tcp",
  "FromPort": 3306,
  "ToPort": 3306,
  "SourceSecurityGroupId": "sg-app-67890"  // Appからのみ許可
}
```

**3. VPC Endpoint（プライベート接続）:**
```bash
# S3 Gateway Endpoint（無料）
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-12345678 \
  --service-name com.amazonaws.ap-northeast-1.s3 \
  --route-table-ids rtb-12345678

# Interface Endpoint（有料）
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-12345678 \
  --service-name com.amazonaws.ap-northeast-1.ssm \
  --subnet-ids subnet-12345678 subnet-87654321 \
  --security-group-ids sg-endpoint-12345
```

### オンプレミスでの同等構成

**ファイアウォール（Palo Alto / Fortinet）:**
- 初期費用: 1,000万円〜
- 年間ライセンス: 200万円/年

**Cisco ASA設定例:**
```
interface GigabitEthernet0/0
 nameif outside
 security-level 0

interface GigabitEthernet0/1
 nameif dmz
 security-level 50

interface GigabitEthernet0/2
 nameif inside
 security-level 100

access-list outside_in extended permit tcp any host 203.0.113.100 eq https
access-list dmz_in extended permit tcp any host 192.168.1.100 eq 8080
access-list inside_in extended deny ip any any

access-group outside_in in interface outside
access-group dmz_in in interface dmz
access-group inside_in in interface inside
```

## まとめ

AWSのVPCでは、きめ細かいセキュリティ設定が可能で、オンプレミスよりも柔軟です。

**ベストプラクティス:**
1. パブリック/プライベートサブネットの適切な分離
2. Security Groupで最小権限の原則
3. VPC Endpointでプライベート接続
4. VPC Flow Logsで全通信記録
5. GuardDutyで脅威検知
