terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"

  # LocalStack用設定
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    apigateway     = "http://localstack:4566"
    cloudformation = "http://localstack:4566"
    cloudfront     = "http://localstack:4566"
    iam            = "http://localstack:4566"
    lambda         = "http://localstack:4566"
    s3             = "http://localstack:4566"
  }
}

# S3バケット（オリジン）
resource "aws_s3_bucket" "origin" {
  bucket = "cloudfront-origin-bucket"
}

resource "aws_s3_bucket_public_access_block" "origin" {
  bucket = aws_s3_bucket.origin.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# サンプルコンテンツ
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.origin.id
  key          = "index.html"
  content      = <<-HTML
    <!DOCTYPE html>
    <html lang="ja">
    <head>
        <meta charset="UTF-8">
        <title>Lambda@Edge デモ</title>
        <style>
            body {
                font-family: Arial, sans-serif;
                max-width: 1000px;
                margin: 50px auto;
                padding: 20px;
            }
            h1 { color: #FF9900; }
            .feature {
                background: #f5f5f5;
                padding: 20px;
                margin: 20px 0;
                border-radius: 5px;
            }
            .feature h2 { color: #232F3E; }
            code {
                background: #232F3E;
                color: #FF9900;
                padding: 2px 6px;
                border-radius: 3px;
            }
        </style>
    </head>
    <body>
        <h1>🚀 Lambda@Edge デモ</h1>
        <p>このページはCloudFront + Lambda@Edgeで配信されています。</p>

        <div class="feature">
            <h2>1. セキュリティヘッダー</h2>
            <p>Lambda@Edge（Viewer Response）で以下のセキュリティヘッダーが自動追加されています：</p>
            <ul>
                <li><code>Strict-Transport-Security</code></li>
                <li><code>X-Content-Type-Options</code></li>
                <li><code>X-Frame-Options</code></li>
                <li><code>X-XSS-Protection</code></li>
                <li><code>Content-Security-Policy</code></li>
            </ul>
            <button onclick="checkHeaders()">ヘッダー確認</button>
            <pre id="headers"></pre>
        </div>

        <div class="feature">
            <h2>2. デバイス判定</h2>
            <p>あなたのデバイスタイプ: <strong id="device">判定中...</strong></p>
            <p>Lambda@Edge（Viewer Request）でUser-Agentを解析しています。</p>
        </div>

        <div class="feature">
            <h2>3. A/Bテスト</h2>
            <p>あなたはバリアント: <strong id="variant">判定中...</strong></p>
            <p>Lambda@Edge（Viewer Request）でランダムに振り分けられています。</p>
        </div>

        <script>
            // デバイス判定（サーバー側で追加されたヘッダーを取得）
            fetch(window.location.href)
                .then(response => {
                    const device = response.headers.get('x-device-type') || 'desktop';
                    document.getElementById('device').textContent = device;

                    const variant = getCookie('ab_variant') || 'A';
                    document.getElementById('variant').textContent = variant;
                });

            function getCookie(name) {
                const value = `; ${document.cookie}`;
                const parts = value.split(`; ${name}=`);
                if (parts.length === 2) return parts.pop().split(';').shift();
            }

            function checkHeaders() {
                const headers = document.getElementById('headers');
                headers.textContent = 'ブラウザの開発者ツール（F12）→ Networkタブで確認してください。';
            }
        </script>
    </body>
    </html>
  HTML
  content_type = "text/html"
}

# Lambda@Edge実行ロール
resource "aws_iam_role" "lambda_edge_role" {
  name = "lambda-edge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "edgelambda.amazonaws.com"
          ]
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_edge_basic" {
  role       = aws_iam_role.lambda_edge_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda@Edge関数: Viewer Request（デバイス判定・A/Bテスト）
resource "aws_lambda_function" "viewer_request" {
  filename      = "${path.module}/lambda/viewer_request.zip"
  function_name = "cloudfront-viewer-request"
  role          = aws_iam_role.lambda_edge_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = 5
  publish       = true

  lifecycle {
    create_before_destroy = true
  }
}

# Lambda@Edge関数: Viewer Response（セキュリティヘッダー）
resource "aws_lambda_function" "viewer_response" {
  filename      = "${path.module}/lambda/viewer_response.zip"
  function_name = "cloudfront-viewer-response"
  role          = aws_iam_role.lambda_edge_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = 5
  publish       = true

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront Origin Access Identity
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for S3 origin"
}

# S3バケットポリシー（CloudFrontからのアクセスのみ許可）
resource "aws_s3_bucket_policy" "origin" {
  bucket = aws_s3_bucket.origin.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.oai.iam_arn
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.origin.arn}/*"
      }
    ]
  })
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Lambda@Edge Demo"
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.origin.bucket_regional_domain_name
    origin_id   = "S3-Origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-Origin"

    forwarded_values {
      query_string = true
      headers      = ["User-Agent"]

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true

    # Lambda@Edge関数の関連付け
    lambda_function_association {
      event_type   = "viewer-request"
      lambda_arn   = aws_lambda_function.viewer_request.qualified_arn
      include_body = false
    }

    lambda_function_association {
      event_type   = "viewer-response"
      lambda_arn   = aws_lambda_function.viewer_response.qualified_arn
      include_body = false
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Environment = "dev"
    Pattern     = "lambda-edge"
  }
}

# 出力
output "cloudfront_domain" {
  value       = aws_cloudfront_distribution.cdn.domain_name
  description = "CloudFront Distribution Domain"
}

output "cloudfront_url" {
  value       = "https://${aws_cloudfront_distribution.cdn.domain_name}"
  description = "CloudFront URL"
}

output "s3_bucket" {
  value       = aws_s3_bucket.origin.id
  description = "S3 Origin Bucket"
}
