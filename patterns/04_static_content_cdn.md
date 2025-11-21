# パターン4: 静的コンテンツ配信（CDN）

## 問題

グローバルに展開する画像共有サービスを構築します。以下の要件を満たすアーキテクチャーを設計してください。

**要件:**
- 全世界のユーザーに高速配信（レイテンシ100ms以内）
- 大量の画像・動画ファイル（10TB以上）
- 月間10億リクエスト
- オリジンサーバーの負荷軽減
- コスト効率の良い配信

## 推奨アーキテクチャー

```
[グローバルユーザー]
    ↓
[CloudFront (CDN)]
 ├─ Edge Location (200+拠点)
 └─ Regional Edge Cache
    ↓ キャッシュミス時のみ
[S3 Bucket (Origin)]
 ├─ Standard
 ├─ Intelligent-Tiering (自動最適化)
 └─ Glacier (アーカイブ)
```

### 使用するAWSサービス:
- **CloudFront**: グローバルCDN
- **S3**: 静的コンテンツストレージ
- **Lambda@Edge**: エッジでの処理
- **Route 53**: GeoDNS
- **ACM**: SSL証明書

## 解説

### なぜこのアーキテクチャーなのか

#### 1. CloudFrontの仕組み

**Edge Locationとは:**
```
世界中に200以上の拠点
├─ 日本: 東京、大阪
├─ アメリカ: 複数都市
├─ ヨーロッパ: 複数都市
└─ その他: アジア、南米、アフリカ等
```

**コンテンツ配信の流れ:**
```
1. ユーザー（東京）がリクエスト
   ↓
2. 最寄りのEdge Location（東京）に接続
   ↓
3. キャッシュ確認
   ├─ ヒット: 即座に返却（5ms）
   └─ ミス: Originから取得（200ms）
   ↓
4. Edge Locationにキャッシュ
   ↓
5. 次回以降は高速配信
```

#### 2. キャッシュヒット率の最適化

**TTL（Time To Live）設定:**
```javascript
// CloudFront設定例
{
  "CacheBehaviors": {
    "PathPattern": "/images/*",
    "MinTTL": 86400,           // 最小1日
    "MaxTTL": 31536000,        // 最大1年
    "DefaultTTL": 86400,       // デフォルト1日
    "Compress": true           // Gzip圧縮有効
  }
}
```

**Cache-Control ヘッダー:**
```http
# 変更されないコンテンツ（ファイル名にハッシュ含む）
Cache-Control: public, max-age=31536000, immutable

# 頻繁に更新されるコンテンツ
Cache-Control: public, max-age=3600, must-revalidate

# プライベートコンテンツ
Cache-Control: private, max-age=0, no-cache
```

**キャッシュヒット率目標:**
```
優: 90%以上
良: 80-90%
改善必要: 80%未満
```

#### 3. Lambda@Edgeでの高度な処理

**画像リサイズ（ViewerRequest）:**
```javascript
exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    const uri = request.uri;

    // /images/photo.jpg?w=300 → /images/photo_300.jpg
    const match = uri.match(/^(.*)\.(jpg|png)$/);
    if (match && request.querystring) {
        const params = new URLSearchParams(request.querystring);
        const width = params.get('w');

        if (width) {
            request.uri = `${match[1]}_${width}.${match[2]}`;
        }
    }

    return request;
};
```

**A/Bテスト（ViewerRequest）:**
```javascript
exports.handler = async (event) => {
    const request = event.Records[0].cf.request;
    const headers = request.headers;

    // Cookieがなければランダムに振り分け
    if (!headers.cookie) {
        const variant = Math.random() < 0.5 ? 'A' : 'B';
        headers['x-variant'] = [{ value: variant }];

        // Set-Cookieヘッダーを追加
        const response = {
            status: '302',
            headers: {
                'location': [{ value: request.uri }],
                'set-cookie': [{ value: `variant=${variant}; Max-Age=86400` }]
            }
        };
        return response;
    }

    return request;
};
```

**セキュリティヘッダー追加（OriginResponse）:**
```javascript
exports.handler = async (event) => {
    const response = event.Records[0].cf.response;
    const headers = response.headers;

    headers['strict-transport-security'] = [{
        key: 'Strict-Transport-Security',
        value: 'max-age=63072000; includeSubdomains; preload'
    }];

    headers['x-content-type-options'] = [{
        key: 'X-Content-Type-Options',
        value: 'nosniff'
    }];

    headers['x-frame-options'] = [{
        key: 'X-Frame-Options',
        value: 'DENY'
    }];

    return response;
};
```

### オンプレミスでの同等構成

#### 1. CDN事業者の利用

**Akamai:**
- 世界最大級のCDNプロバイダー
- 30万台以上のサーバー
- 月額数十万円〜数百万円
- 長期契約（1-3年）が一般的

**Cloudflare:**
- グローバルエニーキャストネットワーク
- 比較的低価格
- Pay-as-you-goプラン有り

**Fastly:**
- リアルタイム設定変更
- Varnish Cache Protocol（VCL）

#### 2. 自前CDNの構築

**構成例:**
```
[東京DC]     [シンガポールDC]   [フランクフルトDC]
   ↓              ↓                  ↓
[Nginx]        [Nginx]            [Nginx]
キャッシュ      キャッシュ          キャッシュ
   ↓              ↓                  ↓
      [オリジンサーバー（東京）]
```

**Nginx キャッシュ設定:**
```nginx
# /etc/nginx/nginx.conf
http {
    # キャッシュパス設定
    proxy_cache_path /var/cache/nginx
                     levels=1:2
                     keys_zone=image_cache:100m
                     max_size=10g
                     inactive=60d
                     use_temp_path=off;

    upstream origin {
        server origin.example.com:443;
    }

    server {
        listen 80;
        server_name cdn.example.com;

        location /images/ {
            proxy_cache image_cache;
            proxy_cache_valid 200 60d;
            proxy_cache_valid 404 1m;
            proxy_cache_use_stale error timeout updating;
            proxy_cache_lock on;

            # キャッシュヘッダー
            add_header X-Cache-Status $upstream_cache_status;

            # Origin接続
            proxy_pass https://origin;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
```

**Varnish Cache設定:**
```vcl
# /etc/varnish/default.vcl
vcl 4.1;

backend origin {
    .host = "origin.example.com";
    .port = "443";
    .ssl = true;
}

sub vcl_recv {
    # 画像ファイルのみキャッシュ
    if (req.url ~ "\.(jpg|jpeg|png|gif|webp)$") {
        return (hash);
    }
}

sub vcl_backend_response {
    # 画像は60日間キャッシュ
    if (bereq.url ~ "\.(jpg|jpeg|png|gif|webp)$") {
        set beresp.ttl = 60d;
        set beresp.grace = 1h;
    }

    # Gzip圧縮
    if (beresp.http.content-type ~ "text|javascript|json") {
        set beresp.do_gzip = true;
    }
}

sub vcl_deliver {
    # キャッシュヒット/ミスを返す
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
}
```

#### 3. コンテンツ配信の課題

**A. レイテンシー問題:**
```
日本のユーザー → アメリカのサーバー
├─ 物理的距離: 約10,000km
├─ 光の速度制限: 約67ms（理論値）
├─ ルーティング遅延: 約50-100ms
└─ 合計: 150-200ms以上
```

**B. Origin負荷:**
```
全世界から直接アクセス
↓
Origin サーバーに集中
↓
帯域幅不足、処理遅延
↓
スケールアウトが必要（高コスト）
```

**C. 帯域幅コスト:**
```
データセンターからの転送
├─ 国内転送: 約1円/GB
├─ 国際転送: 約10-20円/GB
└─ 10TBの転送: 10-20万円/月
```

#### 4. GeoDNSによる振り分け

**BIND設定例:**
```
# /etc/bind/named.conf
view "asia" {
    match-clients { geoip-asia; };
    zone "cdn.example.com" {
        type master;
        file "/etc/bind/zones/cdn-asia.db";
    };
};

view "europe" {
    match-clients { geoip-europe; };
    zone "cdn.example.com" {
        type master;
        file "/etc/bind/zones/cdn-europe.db";
    };
};

view "americas" {
    match-clients { geoip-americas; };
    zone "cdn.example.com" {
        type master;
        file "/etc/bind/zones/cdn-americas.db";
    };
};
```

**Zoneファイル（アジア向け）:**
```
# /etc/bind/zones/cdn-asia.db
$TTL 300
@   IN  SOA ns1.example.com. admin.example.com. (
            2024010101 ; Serial
            3600       ; Refresh
            1800       ; Retry
            604800     ; Expire
            300 )      ; Minimum TTL

@   IN  NS  ns1.example.com.
@   IN  A   203.0.113.10    ; アジアのキャッシュサーバー
```

### オンプレミスとAWSの比較

| 項目 | オンプレミス/CDN事業者 | AWS CloudFront + S3 |
|------|---------------------|---------------------|
| **初期コスト** | 高額<br>CDN契約金: 数十万円<br>最低利用料金あり | 低額<br>初期費用ゼロ<br>従量課金のみ |
| **拠点数** | CDN事業者に依存<br>自前構築は数拠点が限界 | 200以上のEdge Location<br>常に増加中 |
| **設定変更** | 遅い<br>CDN事業者経由: 数時間〜数日<br>自前: サーバー毎に設定 | 速い<br>即座に反映（数分）<br>API/IaCで自動化 |
| **運用負荷** | 高<br>各拠点のサーバー管理<br>キャッシュクリア作業 | 低<br>マネージドサービス<br>自動管理 |
| **スケーラビリティ** | 契約に依存<br>上限があり拡張に時間 | ほぼ無制限<br>自動スケール |

### コスト比較

**オンプレミス/CDN事業者:**
- CDN契約（Akamai等）: 50-200万円/月
- Origin帯域: 10-30万円/月
- オリジンサーバー: 20万円/月
- **合計: 80-250万円/月**

**AWS CloudFront + S3:**
- S3ストレージ（10TB）: 約25,000円/月
- S3リクエスト（10億GET）: 約40,000円/月
- CloudFront転送（100TB）: 約850,000円/月
- CloudFrontリクエスト: 約10,000円/月
- **合計: 約925,000円/月**

**キャッシュヒット率90%の場合:**
- S3からの転送（10TB）: 約85,000円/月
- **合計: 約160,000円/月**

## まとめ

静的コンテンツ配信には、CloudFront + S3の組み合わせが最適です。

**メリット:**
- **グローバルに高速配信**（200+ Edge Location）
- **初期投資不要**（従量課金）
- **自動スケーリング**（無制限）
- **簡単な設定**（数クリック）
- **Lambda@Edgeで高度な処理**

**ベストプラクティス:**
1. CloudFrontのTTLを適切に設定（キャッシュヒット率90%以上目標）
2. S3のライフサイクルポリシーでコスト最適化
3. CloudFront + S3 OAI（Origin Access Identity）でセキュリティ強化
4. Lambda@Edgeで画像最適化やA/Bテスト
5. CloudWatch Metricsでパフォーマンス監視
