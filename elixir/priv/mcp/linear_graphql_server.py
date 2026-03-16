#!/usr/bin/env python3
"""MCP server exposing a linear_graphql tool over stdio transport."""

import json
import sys
import urllib.request
import urllib.error
import os

LINEAR_API_URL = "https://api.linear.app/graphql"

TOOL_DEFINITION = {
    "name": "linear_graphql",
    "description": "Execute a raw GraphQL query or mutation against Linear using Concerto's configured auth.",
    "inputSchema": {
        "type": "object",
        "required": ["query"],
        "properties": {
            "query": {
                "type": "string",
                "description": "GraphQL query or mutation document",
            },
            "variables": {
                "type": "object",
                "description": "Optional GraphQL variables",
            },
        },
    },
}


def execute_graphql(query: str, variables: dict | None = None) -> dict:
    api_key = os.environ.get("LINEAR_API_KEY")
    if not api_key:
        return {"error": "LINEAR_API_KEY environment variable is not set"}

    payload = {"query": query}
    if variables:
        payload["variables"] = variables

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        LINEAR_API_URL,
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": api_key,
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        return {"error": f"HTTP {e.code}: {body}"}
    except urllib.error.URLError as e:
        return {"error": f"URL error: {e.reason}"}


def handle_request(msg: dict) -> dict | None:
    method = msg.get("method")
    msg_id = msg.get("id")

    # Notifications have no id and expect no response
    if msg_id is None:
        return None

    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {
                "capabilities": {"tools": {}},
                "protocolVersion": "2024-11-05",
                "serverInfo": {"name": "concerto-linear", "version": "1.0.0"},
            },
        }

    if method == "tools/list":
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {"tools": [TOOL_DEFINITION]},
        }

    if method == "tools/call":
        params = msg.get("params", {})
        tool_name = params.get("name")
        arguments = params.get("arguments", {})

        if tool_name != "linear_graphql":
            return {
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps({"error": f"Unknown tool: {tool_name}"}),
                        }
                    ],
                    "isError": True,
                },
            }

        query = arguments.get("query", "")
        variables = arguments.get("variables")
        result = execute_graphql(query, variables)
        is_error = "errors" in result and "data" not in result

        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {
                "content": [{"type": "text", "text": json.dumps(result, indent=2)}],
                "isError": is_error,
            },
        }

    # Unknown method
    return {
        "jsonrpc": "2.0",
        "id": msg_id,
        "error": {"code": -32601, "message": f"Method not found: {method}"},
    }


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            print(f"concerto-linear: malformed JSON input: {line[:200]}", file=sys.stderr)
            continue

        response = handle_request(msg)
        if response is not None:
            sys.stdout.write(json.dumps(response) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
