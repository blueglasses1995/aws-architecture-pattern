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
    cloudwatch     = "http://localstack:4566"
    dynamodb       = "http://localstack:4566"
    iam            = "http://localstack:4566"
    lambda         = "http://localstack:4566"
    s3             = "http://localstack:4566"
    sts            = "http://localstack:4566"
  }
}

# S3バケット（静的Webホスティング）
resource "aws_s3_bucket" "website" {
  bucket = "serverless-website-bucket"
}

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website.arn}/*"
      }
    ]
  })
}

# index.htmlをアップロード
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.website.id
  key          = "index.html"
  content      = <<-HTML
    <!DOCTYPE html>
    <html lang="ja">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>サーバーレスWebアプリ</title>
        <style>
            body {
                font-family: Arial, sans-serif;
                max-width: 800px;
                margin: 50px auto;
                padding: 20px;
            }
            h1 { color: #FF9900; }
            .api-test {
                margin-top: 30px;
                padding: 20px;
                background: #f5f5f5;
                border-radius: 5px;
            }
            button {
                background: #FF9900;
                color: white;
                border: none;
                padding: 10px 20px;
                border-radius: 5px;
                cursor: pointer;
            }
            button:hover { background: #EC7211; }
            #result {
                margin-top: 20px;
                padding: 10px;
                background: white;
                border: 1px solid #ddd;
                border-radius: 5px;
                min-height: 100px;
            }
        </style>
    </head>
    <body>
        <h1>🚀 サーバーレスWebアプリケーション</h1>
        <p>このページはS3でホスティングされています。</p>
        <p>API GatewayとLambdaを使ってバックエンド処理を実行できます。</p>

        <div class="api-test">
            <h2>API テスト</h2>
            <button onclick="createUser()">ユーザー作成</button>
            <button onclick="getUsers()">ユーザー一覧取得</button>
            <div id="result"></div>
        </div>

        <script>
            const API_ENDPOINT = '${aws_apigatewayv2_stage.api.invoke_url}';

            async function createUser() {
                const result = document.getElementById('result');
                result.textContent = '処理中...';

                try {
                    const response = await fetch(`$${API_ENDPOINT}/users`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            name: 'テストユーザー',
                            email: 'test@example.com'
                        })
                    });
                    const data = await response.json();
                    result.textContent = JSON.stringify(data, null, 2);
                } catch (error) {
                    result.textContent = 'エラー: ' + error.message;
                }
            }

            async function getUsers() {
                const result = document.getElementById('result');
                result.textContent = '処理中...';

                try {
                    const response = await fetch(`$${API_ENDPOINT}/users`);
                    const data = await response.json();
                    result.textContent = JSON.stringify(data, null, 2);
                } catch (error) {
                    result.textContent = 'エラー: ' + error.message;
                }
            }
        </script>
    </body>
    </html>
  HTML
  content_type = "text/html"
}

# DynamoDBテーブル
resource "aws_dynamodb_table" "users" {
  name           = "Users"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "email"
    type = "S"
  }

  global_secondary_index {
    name            = "EmailIndex"
    hash_key        = "email"
    projection_type = "ALL"
  }

  tags = {
    Environment = "dev"
    Pattern     = "serverless"
  }
}

# Lambda実行ロール
resource "aws_iam_role" "lambda_role" {
  name = "serverless-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "serverless-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = [
          aws_dynamodb_table.users.arn,
          "${aws_dynamodb_table.users.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda関数: ユーザー作成
resource "aws_lambda_function" "create_user" {
  filename      = "${path.module}/lambda/create_user.zip"
  function_name = "serverless-create-user"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = 30

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.users.name
    }
  }
}

# Lambda関数: ユーザー一覧取得
resource "aws_lambda_function" "list_users" {
  filename      = "${path.module}/lambda/list_users.zip"
  function_name = "serverless-list-users"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  timeout       = 30

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.users.name
    }
  }
}

# API Gateway (HTTP API)
resource "aws_apigatewayv2_api" "api" {
  name          = "serverless-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
  }
}

# Lambda統合
resource "aws_apigatewayv2_integration" "create_user" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.create_user.invoke_arn
}

resource "aws_apigatewayv2_integration" "list_users" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.list_users.invoke_arn
}

# ルート定義
resource "aws_apigatewayv2_route" "create_user" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /users"
  target    = "integrations/${aws_apigatewayv2_integration.create_user.id}"
}

resource "aws_apigatewayv2_route" "list_users" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /users"
  target    = "integrations/${aws_apigatewayv2_integration.list_users.id}"
}

# ステージ
resource "aws_apigatewayv2_stage" "api" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "dev"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }
}

# CloudWatch Logs
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/serverless-api"
  retention_in_days = 7
}

# Lambda許可
resource "aws_lambda_permission" "create_user" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_user.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "list_users" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_users.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# 出力
output "website_url" {
  value       = "http://${aws_s3_bucket.website.bucket}.s3-website-${data.aws_region.current.name}.amazonaws.com"
  description = "静的WebサイトのURL"
}

output "api_endpoint" {
  value       = aws_apigatewayv2_stage.api.invoke_url
  description = "API GatewayエンドポイントURL"
}

output "dynamodb_table" {
  value       = aws_dynamodb_table.users.name
  description = "DynamoDBテーブル名"
}

data "aws_region" "current" {}
