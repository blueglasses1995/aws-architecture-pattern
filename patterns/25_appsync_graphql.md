# パターン25: AppSync GraphQL API

## 問題

モバイルアプリ向けに、柔軟なAPI設計とリアルタイム更新を実現したい。

## 推奨アーキテクチャー

```
[モバイルアプリ]
    ↓ GraphQL
[AppSync]
├─ Resolver (Lambda)
├─ Resolver (DynamoDB)
├─ Resolver (RDS)
└─ Subscription (リアルタイム)
    ↓
[DynamoDB]
[Lambda]
[RDS]
```

### GraphQLスキーマ例

```graphql
type Post {
  id: ID!
  title: String!
  content: String!
  author: User!
  comments: [Comment]
  createdAt: AWSDateTime!
}

type User {
  id: ID!
  name: String!
  email: AWSEmail!
  posts: [Post]
}

type Query {
  getPost(id: ID!): Post
  listPosts(limit: Int, nextToken: String): PostConnection
  getUser(id: ID!): User
}

type Mutation {
  createPost(input: CreatePostInput!): Post
  updatePost(input: UpdatePostInput!): Post
  deletePost(id: ID!): Post
}

type Subscription {
  onCreatePost: Post
    @aws_subscribe(mutations: ["createPost"])
}
```

### Resolver（VTL）

```vtl
## DynamoDB GetItem
{
  "version": "2018-05-29",
  "operation": "GetItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
  }
}

## Response Mapping
$util.toJson($ctx.result)
```

### リアルタイムサブスクリプション

```javascript
// クライアント側（React）
import { API, graphqlOperation } from 'aws-amplify';

const subscription = API.graphql(
  graphqlOperation(onCreatePost)
).subscribe({
  next: ({ provider, value }) => {
    console.log('New post:', value.data.onCreatePost);
    // UIを更新
  }
});
```

## REST API vs GraphQL

| 項目 | REST API | GraphQL |
|------|---------|----------|
| データ取得 | 複数エンドポイント | 1つのエンドポイント |
| Over-fetching | あり | なし（必要なデータのみ） |
| Under-fetching | あり（複数リクエスト必要） | なし（1リクエストで完結） |
| リアルタイム | 追加実装必要 | Subscription標準対応 |

## まとめ

AppSyncでサーバーレスGraphQL APIを簡単に構築。

**メリット:**
- Over/Under-fetchingの解消
- リアルタイムサブスクリプション
- オフライン同期（AWS Amplify連携）
- 自動スケーリング
