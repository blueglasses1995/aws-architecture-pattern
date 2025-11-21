# パターン14: WAFによるセキュリティ強化

## 問題

Webアプリケーションに対する攻撃（SQLインジェクション、XSS、DDoS等）を防御します。

## 推奨アーキテクチャー

```
[インターネット]
    ↓
[CloudFront + AWS WAF]
├─ Managed Rules（SQLi、XSS防御）
├─ Rate Limiting（DDoS対策）
└─ Geo Blocking
    ↓
[Shield Standard]（無料のDDoS防御）
    ↓
[ALB + AWS WAF]
    ↓
[EC2]
```

### 使用するAWSサービス:
- **AWS WAF**: Webアプリケーションファイアウォール
- **Shield Standard/Advanced**: DDoS防御
- **CloudFront**: エッジでの攻撃防御

## 解説

**WAF Managed Rules:**
```json
{
  "ManagedRuleGroupStatement": {
    "VendorName": "AWS",
    "Name": "AWSManagedRulesCommonRuleSet"
  }
}
```

**Rate Limiting:**
```json
{
  "RateBasedStatement": {
    "Limit": 2000,
    "AggregateKeyType": "IP"
  }
}
```

### オンプレミス

**F5 BIG-IP ASM:** 2,000万円〜
**Imperva WAF:** 1,000万円〜

**AWS WAF:** 月額1-5万円

## まとめ

AWS WAFは、低コストで強力なWeb攻撃防御を実現します。
