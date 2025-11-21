# パターン28: MediaConvert動画変換

## 問題

ユーザーがアップロードした動画を複数フォーマットに変換し、配信したい。

## 推奨アーキテクチャー

```
[ユーザー]
    ↓ アップロード
[S3]（入力バケット）
    ↓ S3イベント
[Lambda]
    ↓ ジョブ作成
[MediaConvert]
├─ トランスコード
├─ 複数解像度（1080p, 720p, 480p）
├─ HLS/DASH出力
└─ サムネイル生成
    ↓
[S3]（出力バケット）
    ↓
[CloudFront]（配信）
```

### MediaConvertジョブ作成

```python
import boto3

mediaconvert = boto3.client('mediaconvert', endpoint_url='https://xxxxxxxx.mediaconvert.ap-northeast-1.amazonaws.com')

response = mediaconvert.create_job(
    Role='arn:aws:iam::123456789012:role/MediaConvertRole',
    Settings={
        'Inputs': [{
            'FileInput': 's3://input-bucket/input-video.mp4',
            'AudioSelectors': {
                'Audio Selector 1': {'DefaultSelection': 'DEFAULT'}
            },
            'VideoSelector': {}
        }],
        'OutputGroups': [
            {
                'Name': 'HLS',
                'OutputGroupSettings': {
                    'Type': 'HLS_GROUP_SETTINGS',
                    'HlsGroupSettings': {
                        'Destination': 's3://output-bucket/hls/',
                        'SegmentLength': 10
                    }
                },
                'Outputs': [
                    {
                        'NameModifier': '_1080p',
                        'VideoDescription': {
                            'Width': 1920,
                            'Height': 1080,
                            'CodecSettings': {
                                'Codec': 'H_264',
                                'H264Settings': {
                                    'Bitrate': 5000000
                                }
                            }
                        }
                    },
                    {
                        'NameModifier': '_720p',
                        'VideoDescription': {
                            'Width': 1280,
                            'Height': 720,
                            'CodecSettings': {
                                'Codec': 'H_264',
                                'H264Settings': {
                                    'Bitrate': 3000000
                                }
                            }
                        }
                    }
                ]
            }
        ]
    }
)
```

## オンプレミス

**FFmpeg:**
```bash
# 手動でトランスコード
ffmpeg -i input.mp4 \
  -vf scale=1920:1080 -b:v 5M output_1080p.mp4

ffmpeg -i input.mp4 \
  -vf scale=1280:720 -b:v 3M output_720p.mp4
```

**課題:**
- サーバーリソース管理
- 並列処理の実装
- 長時間処理のジョブ管理

## まとめ

MediaConvertでサーバーレス動画変換を実現。

**メリット:**
- 自動スケーリング
- 複数フォーマット一括変換
- 従量課金（$0.015/分〜）
