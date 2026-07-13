#!/usr/bin/env python3
"""Sync GitHub issues from .github/project-backlog.json.

Used locally (`gh auth login`) or in CI (GITHUB_TOKEN with issues: write).
Idempotent: upsert matches open issues by title; skips create if title exists.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"
REPO = os.environ.get("GITHUB_REPOSITORY", "panagiod/infra")
TOKEN = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
BACKLOG = os.environ.get(
    "PROJECT_BACKLOG_FILE",
    os.path.join(os.path.dirname(__file__), "..", ".github", "project-backlog.json"),
)


def request(method: str, path: str, body: dict | None = None) -> dict | list | None:
    if not TOKEN:
        print("ERROR: set GITHUB_TOKEN or GH_TOKEN", file=sys.stderr)
        sys.exit(1)
    url = f"{API}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode()
        print(f"HTTP {exc.code} {method} {path}: {detail}", file=sys.stderr)
        sys.exit(1)


def list_issues() -> list[dict]:
    issues: list[dict] = []
    page = 1
    while True:
        batch = request("GET", f"/repos/{REPO}/issues?state=all&per_page=100&page={page}")
        assert isinstance(batch, list)
        if not batch:
            break
        issues.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    return [i for i in issues if "pull_request" not in i]


def close_issue(number: int, comment: str) -> None:
    issue = request("GET", f"/repos/{REPO}/issues/{number}")
    assert isinstance(issue, dict)
    if issue.get("state") != "open":
        print(f"skip close #{number}: already {issue.get('state')}")
        return
    request("POST", f"/repos/{REPO}/issues/{number}/comments", {"body": comment})
    request("PATCH", f"/repos/{REPO}/issues/{number}", {"state": "closed"})
    print(f"closed #{number}")


def set_labels(number: int, labels: list[str]) -> None:
    request("PUT", f"/repos/{REPO}/issues/{number}/labels", {"labels": labels})


def find_issue(issues: list[dict], title: str) -> dict | None:
    matches = [i for i in issues if i.get("title") == title]
    if not matches:
        return None
    open_matches = [i for i in matches if i.get("state") == "open"]
    return (open_matches or matches)[0]


def upsert_issue(spec: dict, issues: list[dict]) -> None:
    title = spec["title"]
    match = spec.get("match_title", title)
    existing = find_issue(issues, match) or find_issue(issues, title)
    body = {"title": title, "body": spec["body"], "state": spec.get("state", "open")}
    labels = spec.get("labels", [])

    if existing:
        number = existing["number"]
        if existing.get("state") == "closed" and spec.get("state", "open") == "open":
            request("PATCH", f"/repos/{REPO}/issues/{number}", {"state": "open"})
        request("PATCH", f"/repos/{REPO}/issues/{number}", body)
        if labels:
            set_labels(number, labels)
        print(f"updated #{number} {title!r}")
        return

    created = request("POST", f"/repos/{REPO}/issues", body)
    assert isinstance(created, dict)
    number = created["number"]
    if labels:
        set_labels(number, labels)
    print(f"created #{number} {title!r}")


def main() -> None:
    with open(BACKLOG, encoding="utf-8") as fh:
        backlog = json.load(fh)

    for item in backlog.get("close", []):
        close_issue(item["number"], item["comment"])

    issues = list_issues()

    for spec in backlog.get("upsert", []):
        upsert_issue(spec, issues)


if __name__ == "__main__":
    main()
