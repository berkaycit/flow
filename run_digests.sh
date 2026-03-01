#!/bin/bash
cd "$(dirname "$0")"
python3 python-yt-digest/yt_digest.py &
python3 python-hn-digest/hn_digest.py &
wait
