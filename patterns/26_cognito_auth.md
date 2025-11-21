# パターン26: Cognitoでの認証認可

## 問題

モバイル/Webアプリでユーザー認証を実装したい。

## 推奨アーキテクチャー

```
[クライアント]
    ↓ サインアップ/サインイン
[Cognito User Pool]
├─ ユーザー管理
├─ MFA
├─ パスワードポリシー
└─ JWTトークン発行
    ↓
[API Gateway]
├─ Cognito Authorizer
└─ Lambda
    ↓
[Cognito Identity Pool]
├─ AWS認証情報取得
└─ S3/DynamoDB直接アクセス
```

### User Pool設定

```bash
aws cognito-idp create-user-pool \
  --pool-name my-user-pool \
  --policies '{
    "PasswordPolicy": {
      "MinimumLength": 8,
      "RequireUppercase": true,
      "RequireLowercase": true,
      "RequireNumbers": true,
      "RequireSymbols": true
    }
  }' \
  --mfa-configuration OPTIONAL \
  --email-configuration '{
    "EmailSendingAccount": "DEVELOPER",
    "SourceArn": "arn:aws:ses:ap-northeast-1:123456789012:identity/noreply@example.com"
  }'
```

### サインアップ/サインイン（SDK）

```javascript
import { CognitoUserPool, CognitoUser, AuthenticationDetails } from 'amazon-cognito-identity-js';

// サインアップ
const userPool = new CognitoUserPool({
  UserPoolId: 'ap-northeast-1_XXXXXXXXX',
  ClientId: 'xxxxxxxxxxxxxxxxxxxx'
});

userPool.signUp('username', 'Password123!', [
  { Name: 'email', Value: 'user@example.com' }
], null, (err, result) => {
  if (err) {
    console.error(err);
    return;
  }
  console.log('User registered:', result.user);
});

// サインイン
const authenticationDetails = new AuthenticationDetails({
  Username: 'username',
  Password: 'Password123!'
});

const cognitoUser = new CognitoUser({
  Username: 'username',
  Pool: userPool
});

cognitoUser.authenticateUser(authenticationDetails, {
  onSuccess: (result) => {
    const idToken = result.getIdToken().getJwtToken();
    console.log('ID Token:', idToken);
  },
  onFailure: (err) => {
    console.error(err);
  }
});
```

### API Gateway Authorizer

```json
{
  "Type": "COGNITO_USER_POOLS",
  "ProviderARNs": [
    "arn:aws:cognito-idp:ap-northeast-1:123456789012:userpool/ap-northeast-1_XXXXXXXXX"
  ],
  "IdentitySource": "method.request.header.Authorization"
}
```

## オンプレミス

**自前認証システム:**
- データベース設計
- パスワードハッシュ化
- セッション管理
- MFA実装
- パスワードリセット
- メール送信

**開発工数: 数ヶ月**

**Auth0等のSaaS:**
- 月額: $23〜
- Cognitoより高額

## まとめ

Cognitoで認証システムを数時間で構築可能。

**ベストプラクティス:**
1. User Poolでユーザー管理
2. Identity Poolで一時認証情報取得
3. MFA有効化でセキュリティ強化
4. Lambda Triggerでカスタム処理
