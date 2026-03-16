---
name: linear
description: "Interact with Linear issues via the linear_graphql MCP tool."
---

# Linear

Use the `linear_graphql` tool to read and update Linear issues.

## Common operations

### Move issue to a state
```graphql
mutation {
  issueUpdate(id: "<issue_id>", input: { stateId: "<state_id>" }) {
    success
    issue { state { name } }
  }
}
```

### Add/update a comment
```graphql
mutation {
  commentCreate(input: { issueId: "<issue_id>", body: "<markdown>" }) {
    success
    comment { id }
  }
}
```

### Update an existing comment
```graphql
mutation {
  commentUpdate(id: "<comment_id>", input: { body: "<markdown>" }) {
    success
  }
}
```

### Attach PR URL to issue
```graphql
mutation {
  attachmentCreate(input: { issueId: "<issue_id>", url: "<pr_url>", title: "Pull Request" }) {
    success
  }
}
```

### Get issue details
```graphql
{
  issue(id: "<issue_id>") {
    identifier
    title
    state { name id }
    comments { nodes { id body } }
    attachments { nodes { url title } }
  }
}
```

## Notes

- The `linear_graphql` tool is injected via MCP by Concerto
- Always use the issue ID (UUID), not the identifier (SAM-123)
- Comment IDs are needed for updating the workpad comment
