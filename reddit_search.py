"""
Reddit Search Tool — CLI for searching Reddit via OAuth API
Reads credentials from reddit.txt in the same directory.

Usage:
  python reddit_search.py "ik_llama.cpp Qwen3.6"
  python reddit_search.py "RTX 5060 Ti local LLM" --sub LocalLLaMA --limit 10
  python reddit_search.py "ik_llama windows" --sort top --time week
  python reddit_search.py --post https://reddit.com/r/LocalLLaMA/comments/abc123/...
  python reddit_search.py --post abc123 --comments 5

Output: Post titles, scores, URLs, and self-text excerpts.
"""

import requests
import requests.auth
import argparse
import json
import re
import sys
from pathlib import Path
from urllib.parse import quote_plus

CRED_FILE = Path(__file__).parent / "reddit.txt"
USER_AGENT = "RedditSearchTool/1.0"
TOKEN_CACHE = Path(__file__).parent / ".reddit_token.json"


def load_credentials():
    """Load client_id and client_secret from reddit.txt."""
    with open(CRED_FILE, encoding="utf-8") as f:
        raw = f.read()
    key_match = re.search(r'"key":\s*"([^:]+):([^"]+)"', raw)
    if not key_match:
        print("ERROR: Could not parse credentials from reddit.txt", file=sys.stderr)
        sys.exit(1)
    return key_match.group(1), key_match.group(2)


def get_token(client_id, client_secret):
    """Get or refresh OAuth token, with caching."""
    # Check cache
    if TOKEN_CACHE.exists():
        try:
            with open(TOKEN_CACHE) as f:
                cached = json.load(f)
            # Test if token still works
            headers = {"Authorization": f'bearer {cached["access_token"]}', "User-Agent": USER_AGENT}
            r = requests.get("https://oauth.reddit.com/api/v1/me", headers=headers, timeout=5)
            if r.status_code == 200:
                return cached["access_token"]
        except Exception:
            pass

    # Get fresh token
    auth = requests.auth.HTTPBasicAuth(client_id, client_secret)
    data = {"grant_type": "client_credentials"}
    r = requests.post(
        "https://www.reddit.com/api/v1/access_token",
        auth=auth, headers={"User-Agent": USER_AGENT}, data=data, timeout=10
    )
    r.raise_for_status()
    token_data = r.json()
    access_token = token_data["access_token"]

    # Cache it
    with open(TOKEN_CACHE, "w") as f:
        json.dump({"access_token": access_token, "expires_at": token_data.get("expires_in", 86400)}, f)

    return access_token


def search_reddit(token, query, subreddit=None, sort="relevance", time="year", limit=5):
    """Search Reddit and return list of posts."""
    headers = {"Authorization": f'bearer {token}', "User-Agent": USER_AGENT}
    sub = subreddit or "all"
    url = f"https://oauth.reddit.com/r/{sub}/search.json?q={quote_plus(query)}&sort={sort}&t={time}&limit={limit}&restrict_sr=on"
    r = requests.get(url, headers=headers, timeout=15)
    r.raise_for_status()
    return r.json().get("data", {}).get("children", [])


def get_post(token, post_id_or_url, comments=0):
    """Fetch a single post by ID or URL, optionally with comments."""
    headers = {"Authorization": f'bearer {token}', "User-Agent": USER_AGENT}

    # Extract post ID from URL or use directly
    post_id = post_id_or_url
    url_match = re.search(r'/comments/([a-z0-9]+)', post_id_or_url)
    if url_match:
        post_id = url_match.group(1)

    url = f"https://oauth.reddit.com/comments/{post_id}.json?limit={comments}"
    r = requests.get(url, headers=headers, timeout=15)
    r.raise_for_status()
    return r.json()


def format_post(pd, show_text=False, text_limit=500):
    """Format a post for display."""
    title = pd.get("title", "?")
    score = pd.get("score", 0)
    author = pd.get("author", "?")
    sub = pd.get("subreddit", "?")
    permalink = f'https://reddit.com{pd.get("permalink", "")}'
    num_comments = pd.get("num_comments", 0)

    lines = [
        f'{score}pts | r/{sub} | u/{author} | {num_comments} comments',
        f'  {title}',
        f'  {permalink}',
    ]

    if show_text:
        selftext = pd.get("selftext", "")
        if selftext:
            excerpt = selftext[:text_limit]
            if len(selftext) > text_limit:
                excerpt += "..."
            lines.append(f'  Text: {excerpt}')

    return "\n".join(lines)


def format_comment(cd, limit=300):
    """Format a comment for display."""
    author = cd.get("author", "?")
    score = cd.get("score", 0)
    body = cd.get("body", "")[:limit]
    if len(cd.get("body", "")) > limit:
        body += "..."
    return f'  u/{author} ({score}pts): {body}'


def main():
    parser = argparse.ArgumentParser(description="Reddit Search Tool")
    parser.add_argument("query", nargs="?", help="Search query")
    parser.add_argument("--sub", default=None, help="Subreddit (default: all)")
    parser.add_argument("--sort", default="relevance", choices=["relevance", "top", "new", "comments"], help="Sort order")
    parser.add_argument("--time", default="year", choices=["hour", "day", "week", "month", "year", "all"], help="Time range")
    parser.add_argument("--limit", type=int, default=5, help="Max results (default: 5)")
    parser.add_argument("--text", action="store_true", help="Show post text excerpt")
    parser.add_argument("--text-limit", type=int, default=500, help="Text excerpt length (default: 500)")
    parser.add_argument("--post", help="Fetch single post by ID or URL")
    parser.add_argument("--comments", type=int, default=0, help="Number of comments to show with --post")
    parser.add_argument("--json", action="store_true", help="Output raw JSON")
    parser.add_argument("--creds", default=str(CRED_FILE), help="Path to credentials file")

    args = parser.parse_args()

    if not args.query and not args.post:
        parser.print_help()
        sys.exit(1)

    client_id, client_secret = load_credentials()
    token = get_token(client_id, client_secret)

    # Fetch single post mode
    if args.post:
        data = get_post(token, args.post, comments=args.comments)
        post = data[0]["data"]["children"][0]["data"]

        if args.json:
            print(json.dumps(data, indent=2))
            return

        print(format_post(post, show_text=True, text_limit=args.text_limit or 4000))
        print()

        if args.comments > 0 and len(data) > 1:
            comments = data[1]["data"]["children"]
            print(f"--- Top {args.comments} comments ---")
            count = 0
            for c in comments:
                if c["kind"] == "t1":
                    print(format_comment(c["data"], limit=400))
                    print()
                    count += 1
                    if count >= args.comments:
                        break
        return

    # Search mode
    results = search_reddit(token, args.query, subreddit=args.sub, sort=args.sort, time=args.time, limit=args.limit)

    if args.json:
        print(json.dumps(results, indent=2))
        return

    if not results:
        print("No results found.")
        return

    print(f'Found {len(results)} results for "{args.query}"\n')
    for p in results:
        pd = p["data"]
        print(format_post(pd, show_text=args.text, text_limit=args.text_limit))
        print()


if __name__ == "__main__":
    main()
