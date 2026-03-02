#!/usr/bin/env python3
"""Create a NotebookLM notebook from a URL and open it."""

import argparse
import asyncio
import sys

from notebooklm import NotebookLMClient


async def main(url: str, title: str) -> None:
    async with await NotebookLMClient.from_storage() as client:
        nb = await client.notebooks.create(title)
        await client.sources.add_url(nb.id, url, wait=True)

        print(f"https://notebooklm.google.com/notebook/{nb.id}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--title", required=True)
    args = parser.parse_args()

    try:
        asyncio.run(main(args.url, args.title))
    except FileNotFoundError:
        sys.exit(2)  # Auth missing -- storage_state.json not found
    except Exception as e:
        if "authenticate" in str(e).lower():
            sys.exit(2)
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
