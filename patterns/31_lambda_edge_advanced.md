# パターン31: Lambda@Edgeによる高度なエッジ処理

## 問題

グローバルユーザーに対して、エッジロケーションでの高度な処理（画像リサイズ、A/Bテスト、認証、リダイレクト等）を実現したい。

**要件:**
- オリジンサーバーの負荷軽減
- レスポンスタイムの短縮（エッジで処理）
- ユーザー体験のパーソナライゼーション
- SEO対応（User-Agent判定、リダイレクト）
- セキュリティ強化（署名付きURL、ヘッダー追加）

## 推奨アーキテクチャー

```
[ユーザー]
    ↓
[CloudFront Distribution]
    ↓
[Lambda@Edge（4つのトリガーポイント）]
├─ Viewer Request（リクエスト受信時）
│   ├─ 認証チェック
│   ├─ User-Agent判定
│   ├─ Geo判定・リダイレクト
│   └─ A/Bテスト振り分け
├─ Origin Request（オリジン転送前）
│   ├─ URLリライト
│   ├─ ヘッダー追加
│   └─ 署名付きURL生成
├─ Origin Response（オリジンレスポンス受信時）
│   ├─ ヘッダー追加
│   ├─ レスポンス変換
│   └─ キャッシュ制御
└─ Viewer Response（レスポンス返却前）
    ├─ セキュリティヘッダー追加
    ├─ Cookie設定
    └─ 圧縮
    ↓
[S3 Origin] / [ALB Origin]
```

### 使用するAWSサービス:
- **CloudFront**: グローバルCDN
- **Lambda@Edge**: エッジコンピューティング
- **CloudFront Functions**: 超軽量エッジ処理
- **S3**: オリジンストレージ
- **DynamoDB Global Tables**: エッジデータストア

## 解説

### Lambda@Edge vs CloudFront Functions

| 項目 | CloudFront Functions | Lambda@Edge |
|------|---------------------|-------------|
| **実行タイミング** | Viewer Request/Response のみ | 全4イベント |
| **実行時間** | 1ms未満 | 最大30秒 |
| **メモリ** | 2MB | 128-10240MB |
| **ネットワークアクセス** | 不可 | 可能 |
| **料金** | 超低額（$0.10/百万リクエスト） | 低額（$0.60/百万リクエスト） |
| **用途** | 超軽量処理 | 複雑な処理 |
| **言語** | JavaScript（ES5） | Node.js / Python |

### Lambda@Edgeのユースケース

#### 1. 画像リサイズ（Origin Response）

```javascript
'use strict';

const querystring = require('querystring');
const Sharp = require('sharp');
const AWS = require('aws-sdk');
const S3 = new AWS.S3({ region: 'us-east-1' });

exports.handler = async (event) => {
    const response = event.Records[0].cf.response;
    const request = event.Records[0].cf.request;

    // リサイズ済みならそのまま返す
    if (response.status === '200') {
        return response;
    }

    // クエリパラメータ取得
    const params = querystring.parse(request.querystring);
    const width = parseInt(params.w) || 800;
    const quality = parseInt(params.q) || 80;

    // S3から元画像取得
    const uri = request.uri;
    const bucket = 'my-image-bucket';

    try {
        const s3Object = await S3.getObject({
            Bucket: bucket,
            Key: uri.substring(1) // 先頭の'/'を除去
        }).promise();

        // Sharp でリサイズ
        const resizedImage = await Sharp(s3Object.Body)
            .resize(width, null, {
                fit: 'inside',
                withoutEnlargement: true
            })
            .jpeg({ quality: quality })
            .toBuffer();

        // リサイズ済み画像をS3に保存（キャッシュ）
        const resizedKey = `resized/${width}/${uri.substring(1)}`;
        await S3.putObject({
            Bucket: bucket,
            Key: resizedKey,
            Body: resizedImage,
            ContentType: 'image/jpeg',
            CacheControl: 'max-age=31536000' // 1年
        }).promise();

        // レスポンス生成
        response.status = '200';
        response.body = resizedImage.toString('base64');
        response.bodyEncoding = 'base64';
        response.headers['content-type'] = [{ value: 'image/jpeg' }];
        response.headers['cache-control'] = [{ value: 'max-age=31536000' }];

        return response;

    } catch (error) {
        console.error('Error:', error);
        return response; // 元のレスポンスを返す
    }
};
```

#### 2. A/Bテスト（Viewer Request）

```javascript
'use strict';

exports.handler = (event, context, callback) => {
    const request = event.Records[0].cf.request;
    const headers = request.headers;

    // Cookie確認
    let variant = null;
    if (headers.cookie) {
        const cookies = headers.cookie[0].value.split(';');
        for (let cookie of cookies) {
            const [key, value] = cookie.trim().split('=');
            if (key === 'ab_variant') {
                variant = value;
                break;
            }
        }
    }

    // 新規ユーザーの場合、ランダムに振り分け
    if (!variant) {
        variant = Math.random() < 0.5 ? 'A' : 'B';
    }

    // バリアント情報をヘッダーに追加（オリジンで使用）
    request.headers['x-ab-variant'] = [{ value: variant }];

    // URIを書き換え（バリアント別のコンテンツ）
    if (variant === 'B') {
        request.uri = request.uri.replace(/^\//, '/variant-b/');
    }

    callback(null, request);
};
```

#### 3. 認証チェック（Viewer Request）

```javascript
'use strict';

const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET;
const COOKIE_NAME = 'auth_token';

exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    const headers = request.headers;

    // 公開パスは認証不要
    const publicPaths = ['/login', '/signup', '/static'];
    if (publicPaths.some(path => request.uri.startsWith(path))) {
        return request;
    }

    // Cookie からトークン取得
    let token = null;
    if (headers.cookie) {
        const cookies = headers.cookie[0].value.split(';');
        for (let cookie of cookies) {
            const [key, value] = cookie.trim().split('=');
            if (key === COOKIE_NAME) {
                token = value;
                break;
            }
        }
    }

    // トークン検証
    if (!token) {
        return generateUnauthorizedResponse('No token provided');
    }

    try {
        const decoded = jwt.verify(token, JWT_SECRET);

        // ユーザー情報をヘッダーに追加（オリジンで使用）
        request.headers['x-user-id'] = [{ value: decoded.userId }];
        request.headers['x-user-email'] = [{ value: decoded.email }];

        return request;

    } catch (error) {
        return generateUnauthorizedResponse('Invalid token');
    }
};

function generateUnauthorizedResponse(message) {
    return {
        status: '401',
        statusDescription: 'Unauthorized',
        headers: {
            'content-type': [{ value: 'text/html' }],
            'cache-control': [{ value: 'no-store' }]
        },
        body: `
            <!DOCTYPE html>
            <html>
            <head><title>Unauthorized</title></head>
            <body>
                <h1>401 Unauthorized</h1>
                <p>${message}</p>
                <a href="/login">Login</a>
            </body>
            </html>
        `
    };
}
```

#### 4. デバイス判定・リダイレクト（Viewer Request）

```javascript
'use strict';

exports.handler = (event, context, callback) => {
    const request = event.Records[0].cf.request;
    const headers = request.headers;

    // User-Agent取得
    const userAgent = headers['user-agent'] ? headers['user-agent'][0].value : '';

    // モバイルデバイス判定
    const mobilePattern = /Mobile|Android|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i;
    const isMobile = mobilePattern.test(userAgent);

    // タブレット判定
    const tabletPattern = /iPad|Android(?!.*Mobile)/i;
    const isTablet = tabletPattern.test(userAgent);

    // デバイスタイプをヘッダーに追加
    let deviceType = 'desktop';
    if (isTablet) {
        deviceType = 'tablet';
    } else if (isMobile) {
        deviceType = 'mobile';
    }

    request.headers['x-device-type'] = [{ value: deviceType }];

    // モバイルユーザーをモバイルサイトにリダイレクト
    if (isMobile && !request.uri.startsWith('/mobile/')) {
        const response = {
            status: '302',
            statusDescription: 'Found',
            headers: {
                'location': [{
                    value: `https://m.example.com${request.uri}`
                }],
                'cache-control': [{
                    value: 'no-cache, no-store, must-revalidate'
                }]
            }
        };
        callback(null, response);
        return;
    }

    callback(null, request);
};
```

#### 5. Geo判定・リダイレクト（Viewer Request）

```javascript
'use strict';

exports.handler = (event, context, callback) => {
    const request = event.Records[0].cf.request;
    const headers = request.headers;

    // CloudFrontが自動的に追加するGeoヘッダー
    const country = headers['cloudfront-viewer-country']
        ? headers['cloudfront-viewer-country'][0].value
        : 'US';

    // 国別リダイレクト
    const countryToDomain = {
        'JP': 'https://jp.example.com',
        'US': 'https://us.example.com',
        'GB': 'https://uk.example.com',
        'DE': 'https://de.example.com',
        'FR': 'https://fr.example.com'
    };

    const targetDomain = countryToDomain[country] || 'https://www.example.com';
    const currentHost = headers.host[0].value;

    // 既に正しいドメインの場合はそのまま
    if (currentHost.includes(targetDomain.replace('https://', ''))) {
        callback(null, request);
        return;
    }

    // リダイレクト
    const response = {
        status: '302',
        statusDescription: 'Found',
        headers: {
            'location': [{
                value: `${targetDomain}${request.uri}${request.querystring ? '?' + request.querystring : ''}`
            }],
            'cache-control': [{
                value: 'max-age=3600' // 1時間キャッシュ
            }]
        }
    };

    callback(null, response);
};
```

#### 6. セキュリティヘッダー追加（Viewer Response）

```javascript
'use strict';

exports.handler = (event, context, callback) => {
    const response = event.Records[0].cf.response;
    const headers = response.headers;

    // セキュリティヘッダー追加
    headers['strict-transport-security'] = [{
        key: 'Strict-Transport-Security',
        value: 'max-age=63072000; includeSubdomains; preload'
    }];

    headers['content-security-policy'] = [{
        key: 'Content-Security-Policy',
        value: "default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.example.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' https://fonts.gstatic.com; connect-src 'self' https://api.example.com"
    }];

    headers['x-content-type-options'] = [{
        key: 'X-Content-Type-Options',
        value: 'nosniff'
    }];

    headers['x-frame-options'] = [{
        key: 'X-Frame-Options',
        value: 'DENY'
    }];

    headers['x-xss-protection'] = [{
        key: 'X-XSS-Protection',
        value: '1; mode=block'
    }];

    headers['referrer-policy'] = [{
        key: 'Referrer-Policy',
        value: 'strict-origin-when-cross-origin'
    }];

    headers['permissions-policy'] = [{
        key: 'Permissions-Policy',
        value: 'geolocation=(), microphone=(), camera=()'
    }];

    callback(null, response);
};
```

#### 7. 署名付きCookie生成（Origin Response）

```javascript
'use strict';

const AWS = require('aws-sdk');
const crypto = require('crypto');

const PRIVATE_KEY = `-----BEGIN RSA PRIVATE KEY-----
...
-----END RSA PRIVATE KEY-----`;

const KEY_PAIR_ID = 'APKAXXXXXXXXXX';

exports.handler = async (event) => {
    const response = event.Records[0].cf.response;
    const request = event.Records[0].cf.request;

    // プレミアムコンテンツへのアクセスチェック
    if (request.uri.startsWith('/premium/')) {

        // 署名付きCookie生成
        const policy = {
            Statement: [{
                Resource: `https://d111111abcdef8.cloudfront.net/premium/*`,
                Condition: {
                    DateLessThan: {
                        'AWS:EpochTime': Math.floor(Date.now() / 1000) + 3600 // 1時間有効
                    }
                }
            }]
        };

        const policyString = JSON.stringify(policy);
        const signature = crypto.sign('RSA-SHA1', Buffer.from(policyString), PRIVATE_KEY);
        const signatureBase64 = signature.toString('base64')
            .replace(/\+/g, '-')
            .replace(/=/g, '_')
            .replace(/\//g, '~');

        // Set-Cookie ヘッダー追加
        response.headers['set-cookie'] = [
            {
                key: 'Set-Cookie',
                value: `CloudFront-Policy=${Buffer.from(policyString).toString('base64').replace(/\+/g, '-').replace(/=/g, '_').replace(/\//g, '~')}; Path=/; Secure; HttpOnly`
            },
            {
                key: 'Set-Cookie',
                value: `CloudFront-Signature=${signatureBase64}; Path=/; Secure; HttpOnly`
            },
            {
                key: 'Set-Cookie',
                value: `CloudFront-Key-Pair-Id=${KEY_PAIR_ID}; Path=/; Secure; HttpOnly`
            }
        ];
    }

    return response;
};
```

### オンプレミスでの同等構成

#### Nginx + Luaでのエッジ処理

```nginx
# /etc/nginx/nginx.conf
http {
    lua_package_path "/usr/local/share/lua/5.1/?.lua;;";
    lua_shared_dict ab_test 10m;

    server {
        listen 443 ssl;
        server_name www.example.com;

        # A/Bテスト
        location / {
            access_by_lua_block {
                local variant = ngx.var.cookie_ab_variant

                if not variant then
                    -- ランダムに振り分け
                    math.randomseed(ngx.now())
                    variant = math.random() < 0.5 and "A" or "B"

                    -- Cookie設定
                    ngx.header["Set-Cookie"] = "ab_variant=" .. variant .. "; Path=/; Max-Age=86400"
                end

                ngx.var.ab_variant = variant
            }

            # バリアント別のバックエンド
            if ($ab_variant = "B") {
                proxy_pass http://backend_b;
            }
            if ($ab_variant = "A") {
                proxy_pass http://backend_a;
            }
        }

        # 画像リサイズ
        location ~* ^/images/(.+)$ {
            set $width 800;
            set $quality 80;

            if ($arg_w) {
                set $width $arg_w;
            }
            if ($arg_q) {
                set $quality $arg_q;
            }

            content_by_lua_block {
                local magick = require("magick")

                -- 元画像読み込み
                local img = magick.load_image("/var/www/images/" .. ngx.var[1])

                -- リサイズ
                img:resize(tonumber(ngx.var.width), nil)
                img:set_quality(tonumber(ngx.var.quality))

                -- 出力
                ngx.header.content_type = "image/jpeg"
                ngx.print(img:get_blob())
            }
        }

        # デバイス判定
        location / {
            set $device_type "desktop";

            if ($http_user_agent ~* "(Mobile|Android|iPhone|iPad)") {
                set $device_type "mobile";
            }

            if ($http_user_agent ~* "(iPad|Android(?!.*Mobile))") {
                set $device_type "tablet";
            }

            # モバイルリダイレクト
            if ($device_type = "mobile") {
                return 302 https://m.example.com$request_uri;
            }

            proxy_set_header X-Device-Type $device_type;
            proxy_pass http://backend;
        }

        # セキュリティヘッダー
        add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "DENY" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Content-Security-Policy "default-src 'self'" always;
    }
}
```

**課題:**
- Nginxサーバーの運用が必要
- グローバル展開には複数拠点にNginx配置
- 画像処理にImageMagick等のライブラリ必要
- スケーリングが困難

#### Varnish Cache + VCL

```vcl
# /etc/varnish/default.vcl
vcl 4.1;

import std;
import directors;

backend backend_a {
    .host = "backend-a.internal";
    .port = "80";
}

backend backend_b {
    .host = "backend-b.internal";
    .port = "80";
}

sub vcl_recv {
    # A/Bテスト
    if (!req.http.Cookie ~ "ab_variant") {
        # ランダムに振り分け
        set req.http.X-AB-Variant = std.random(0, 100) < 50 ? "A" : "B";
    } else {
        set req.http.X-AB-Variant = regsub(req.http.Cookie, ".*ab_variant=([AB]).*", "\1");
    }

    # バックエンド選択
    if (req.http.X-AB-Variant == "B") {
        set req.backend_hint = backend_b;
    } else {
        set req.backend_hint = backend_a;
    }

    # デバイス判定
    if (req.http.User-Agent ~ "(?i)(mobile|android|iphone)") {
        set req.http.X-Device-Type = "mobile";
        return (synth(302, "https://m.example.com" + req.url));
    }
}

sub vcl_deliver {
    # セキュリティヘッダー
    set resp.http.Strict-Transport-Security = "max-age=63072000";
    set resp.http.X-Content-Type-Options = "nosniff";
    set resp.http.X-Frame-Options = "DENY";

    # A/B Cookie設定
    if (req.http.X-AB-Variant) {
        set resp.http.Set-Cookie = "ab_variant=" + req.http.X-AB-Variant + "; Path=/; Max-Age=86400";
    }
}
```

### Lambda@Edge デプロイ

**CloudFormation/SAM:**
```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31

Resources:
  EdgeFunction:
    Type: AWS::Serverless::Function
    Properties:
      FunctionName: cloudfront-viewer-request
      Runtime: nodejs18.x
      Handler: index.handler
      CodeUri: ./lambda-edge/
      MemorySize: 128
      Timeout: 5
      Role: !GetAtt EdgeFunctionRole.Arn
      AutoPublishAlias: live

  EdgeFunctionRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service:
                - lambda.amazonaws.com
                - edgelambda.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

  CloudFrontDistribution:
    Type: AWS::CloudFront::Distribution
    Properties:
      DistributionConfig:
        Enabled: true
        Origins:
          - Id: S3Origin
            DomainName: my-bucket.s3.amazonaws.com
            S3OriginConfig:
              OriginAccessIdentity: !Sub 'origin-access-identity/cloudfront/${CloudFrontOAI}'
        DefaultCacheBehavior:
          TargetOriginId: S3Origin
          ViewerProtocolPolicy: redirect-to-https
          AllowedMethods: [GET, HEAD, OPTIONS]
          CachedMethods: [GET, HEAD, OPTIONS]
          ForwardedValues:
            QueryString: true
            Cookies:
              Forward: all
          LambdaFunctionAssociations:
            - EventType: viewer-request
              LambdaFunctionARN: !Ref EdgeFunction.Version

  CloudFrontOAI:
    Type: AWS::CloudFront::CloudFrontOriginAccessIdentity
    Properties:
      CloudFrontOriginAccessIdentityConfig:
        Comment: OAI for S3 Origin
```

### パフォーマンス比較

| 処理 | オリジン処理 | Lambda@Edge | CloudFront Functions |
|------|------------|-------------|---------------------|
| リクエスト時間 | 200-500ms | 50-150ms | 1ms未満 |
| コスト（百万リクエスト） | $10-50 | $0.60 | $0.10 |
| スケーラビリティ | 手動 | 自動 | 自動 |
| グローバル配信 | 困難 | 自動（200+拠点） | 自動（200+拠点） |

## まとめ

Lambda@Edgeで、エッジロケーションでの高度な処理を実現できます。

**ベストプラクティス:**
1. 軽量処理はCloudFront Functions、複雑処理はLambda@Edge
2. Viewer Requestで認証・リダイレクト
3. Origin Requestで動的コンテンツ生成
4. Origin Responseでヘッダー追加・変換
5. Viewer Responseでセキュリティヘッダー
6. us-east-1リージョンでデプロイ（必須）
7. メモリは最小限（コスト削減）
8. CloudWatch Logsでデバッグ（各リージョン）

**注意点:**
- Lambda@Edgeはus-east-1でのみデプロイ可能
- 環境変数は使用不可（コード内にハードコード or Parameter Store使用）
- パッケージサイズ制限: 1MB（圧縮時）、50MB（展開時）
- 実行時間制限: Viewer Request/Response 5秒、Origin Request/Response 30秒
