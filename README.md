# AWSアーキテクチャーパターン集

AWSの各種サービスを使った実践的なアーキテクチャーパターンの問題と解説集です。

## 概要

このリポジトリには、AWS上で構築する典型的なアーキテクチャーパターンを30個収録しています。
各パターンには以下の内容が含まれています：

- 問題文（シナリオベース）
- 推奨されるAWSアーキテクチャー
- **なぜそのアーキテクチャーを選択するのか**の詳細な解説
- **オンプレミス環境での同等構成**との比較

## 対象者

- AWS認定試験（SAA、SAP、DevOps等）の学習者
- AWSアーキテクチャーの設計を学びたい方
- オンプレミスからクラウドへの移行を検討している方

## パターン一覧

### 基本パターン（1-10）
1. [基本的な3層Webアプリケーション](patterns/01_three_tier_web_app.md)
2. [高可用性構成（Multi-AZ）](patterns/02_high_availability.md)
3. [スケーラブルなWebアプリケーション](patterns/03_auto_scaling_web.md)
4. [静的コンテンツ配信](patterns/04_static_content_cdn.md)
5. [サーバーレスWebアプリケーション](patterns/05_serverless_web_app.md)
6. [マイクロサービスアーキテクチャ](patterns/06_microservices.md)
7. [バッチ処理システム](patterns/07_batch_processing.md)
8. [データレイクアーキテクチャ](patterns/08_data_lake.md)
9. [リアルタイムストリーミング処理](patterns/09_realtime_streaming.md)
10. [ハイブリッドクラウド接続](patterns/10_hybrid_cloud.md)

### 高度なパターン（11-20）
11. [ディザスタリカバリ（DR）構成](patterns/11_disaster_recovery.md)
12. [グローバルコンテンツ配信](patterns/12_global_cdn.md)
13. [セキュアなVPC設計](patterns/13_secure_vpc.md)
14. [WAFによるセキュリティ強化](patterns/14_waf_security.md)
15. [RDSリードレプリカ構成](patterns/15_rds_read_replica.md)
16. [ElastiCacheによる高速化](patterns/16_elasticache.md)
17. [S3ライフサイクル管理](patterns/17_s3_lifecycle.md)
18. [監視・通知システム](patterns/18_monitoring_alerting.md)
19. [統合バックアップ戦略](patterns/19_backup_strategy.md)
20. [Transit Gatewayネットワーク統合](patterns/20_transit_gateway.md)

### 専門的なパターン（21-30）
21. [Step Functionsワークフロー](patterns/21_step_functions.md)
22. [イベント駆動アーキテクチャ](patterns/22_event_driven.md)
23. [Aurora Serverlessでのコスト最適化](patterns/23_aurora_serverless.md)
24. [Fargateコンテナ運用](patterns/24_fargate_containers.md)
25. [AppSync GraphQL API](patterns/25_appsync_graphql.md)
26. [Cognitoでの認証認可](patterns/26_cognito_auth.md)
27. [SESメール送信システム](patterns/27_ses_email.md)
28. [MediaConvert動画変換](patterns/28_media_convert.md)
29. [Redshiftデータウェアハウス](patterns/29_redshift_dwh.md)
30. [マルチアカウント管理](patterns/30_multi_account.md)

## 使い方

1. 各パターンの問題文を読む
2. 自分でアーキテクチャーを考える
3. 解説を読んで理解を深める
4. オンプレミスとの比較で理解を補完する

## ライセンス

MIT License
