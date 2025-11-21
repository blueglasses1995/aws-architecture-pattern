const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand } = require('@aws-sdk/lib-dynamodb');
const { randomUUID } = require('crypto');

// LocalStack用の設定
const client = new DynamoDBClient({
  region: process.env.AWS_REGION || 'ap-northeast-1',
  endpoint: process.env.AWS_ENDPOINT_URL || 'http://localstack:4566',
  credentials: {
    accessKeyId: 'test',
    secretAccessKey: 'test'
  }
});

const docClient = DynamoDBDocumentClient.from(client);

exports.handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));

  try {
    // リクエストボディ解析
    const body = JSON.parse(event.body || '{}');
    const { name, email } = body;

    // バリデーション
    if (!name || !email) {
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          error: 'name and email are required'
        })
      };
    }

    // ユーザーID生成
    const userId = randomUUID();

    // DynamoDBに保存
    const params = {
      TableName: process.env.TABLE_NAME,
      Item: {
        userId,
        name,
        email,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      }
    };

    await docClient.send(new PutCommand(params));

    // レスポンス
    return {
      statusCode: 201,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        message: 'User created successfully',
        user: params.Item
      })
    };

  } catch (error) {
    console.error('Error:', error);

    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        error: 'Internal server error',
        message: error.message
      })
    };
  }
};
