'use strict';

exports.handler = (event, context, callback) => {
    const response = event.Records[0].cf.response;
    const request = event.Records[0].cf.request;
    const headers = response.headers;

    console.log('Viewer Response Event:', JSON.stringify(event, null, 2));

    // セキュリティヘッダー追加
    headers['strict-transport-security'] = [{
        key: 'Strict-Transport-Security',
        value: 'max-age=63072000; includeSubdomains; preload'
    }];

    headers['content-security-policy'] = [{
        key: 'Content-Security-Policy',
        value: "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:;"
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

    // デバイスタイプをレスポンスヘッダーに追加（デモ用）
    if (request.headers['x-device-type']) {
        headers['x-device-type'] = [{
            key: 'X-Device-Type',
            value: request.headers['x-device-type'][0].value
        }];
    }

    // A/BテストのCookie設定
    if (request.headers['x-ab-variant']) {
        const variant = request.headers['x-ab-variant'][0].value;

        // 既存のSet-Cookieがあれば保持
        const existingCookies = headers['set-cookie'] || [];

        // 新しいCookieを追加
        headers['set-cookie'] = [
            ...existingCookies,
            {
                key: 'Set-Cookie',
                value: `ab_variant=${variant}; Path=/; Max-Age=86400; HttpOnly; Secure`
            }
        ];
    }

    // Lambda@Edgeの実行リージョンを追加（デバッグ用）
    headers['x-lambda-region'] = [{
        key: 'X-Lambda-Region',
        value: process.env.AWS_REGION || 'unknown'
    }];

    console.log('Added security headers and cookies');

    callback(null, response);
};
