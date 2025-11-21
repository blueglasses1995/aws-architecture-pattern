# パターン20: Transit Gatewayネットワーク統合

## 問題

複数のVPC、オンプレミス、複数のAWSアカウントを統合的に接続したい。

## 推奨アーキテクチャー

```
[Transit Gateway]
    ├─ VPC-1 (本番環境)
    ├─ VPC-2 (開発環境)
    ├─ VPC-3 (共有サービス)
    ├─ VPC-4 (別アカウント)
    ├─ Direct Connect Gateway（オンプレミス）
    └─ VPN（リモートオフィス）

[ルートテーブル]
├─ Production Route Table
│   └─ VPC-1 ⇄ 共有サービスVPC のみ
├─ Development Route Table
│   └─ VPC-2 ⇄ 共有サービスVPC のみ
└─ Shared Services Route Table
    └─ 全VPCと通信可能
```

### 使用するAWSサービス:
- **Transit Gateway**: VPC統合ハブ
- **Resource Access Manager**: アカウント間共有
- **Direct Connect Gateway**: オンプレミス接続

## 解説

**従来のVPC Peering vs Transit Gateway:**

**VPC Peering（スケールしない）:**
```
VPC数: N
必要なPeering数: N(N-1)/2

例: 10 VPC → 45個のPeering接続
```

**Transit Gateway（スケールする）:**
```
VPC数: N
必要な接続: N個

例: 10 VPC → 10個の接続のみ
```

**Transit Gateway作成:**
```bash
aws ec2 create-transit-gateway \
  --description "Main Transit Gateway" \
  --options \
    AmazonSideAsn=64512,\
    DefaultRouteTableAssociation=enable,\
    DefaultRouteTablePropagation=enable,\
    VpnEcmpSupport=enable,\
    DnsSupport=enable
```

**VPC アタッチ:**
```bash
aws ec2 create-transit-gateway-vpc-attachment \
  --transit-gateway-id tgw-12345678 \
  --vpc-id vpc-12345678 \
  --subnet-ids subnet-12345678 subnet-87654321
```

### オンプレミス

**従来のHub-Spokeネットワーク:**
```
[中央ルーター]
├─ VLAN 10（本番）
├─ VLAN 20（開発）
├─ VLAN 30（共有）
└─ VPN（リモート）
```

**Cisco設定例:**
```
interface GigabitEthernet0/0.10
 encapsulation dot1Q 10
 ip address 10.0.10.1 255.255.255.0

interface GigabitEthernet0/0.20
 encapsulation dot1Q 20
 ip address 10.0.20.1 255.255.255.0
```

**課題:**
- 中央ルーターがSPOF
- スケーリング限界
- 複雑な設定

## まとめ

Transit Gatewayで複雑なネットワークを簡単に統合できます。

**ベストプラクティス:**
1. 用途別にルートテーブル分離
2. Direct Connect Gatewayでオンプレミス統合
3. RAM（Resource Access Manager）でアカウント間共有
4. ネットワークACLで制御
