'use strict';

exports.handler = (event, context, callback) => {
    const request = event.Records[0].cf.request;
    const headers = request.headers;

    console.log('Viewer Request Event:', JSON.stringify(event, null, 2));

    // User-Agent取得
    const userAgent = headers['user-agent'] ? headers['user-agent'][0].value : '';

    // デバイス判定
    const mobilePattern = /Mobile|Android|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i;
    const tabletPattern = /iPad|Android(?!.*Mobile)/i;

    let deviceType = 'desktop';
    if (tabletPattern.test(userAgent)) {
        deviceType = 'tablet';
    } else if (mobilePattern.test(userAgent)) {
        deviceType = 'mobile';
    }

    // デバイスタイプをヘッダーに追加
    request.headers['x-device-type'] = [{ value: deviceType }];

    // A/Bテスト
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

    // バリアント情報をヘッダーに追加
    request.headers['x-ab-variant'] = [{ value: variant }];

    // Cookieがない場合は設定するためのレスポンスを返す
    // （実際のCookie設定はViewer Responseで行う）

    console.log(`Device: ${deviceType}, A/B Variant: ${variant}`);

    callback(null, request);
};
