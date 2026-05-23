#!/bin/bash
cd "$(dirname "$0")"
/usr/bin/env python3 python-yt-digest/yt_digest.py &
/usr/bin/env python3 python-hn-digest/hn_digest.py &
/usr/bin/env python3 python-reddit-digest/reddit_digest.py &
wait