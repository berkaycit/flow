#!/bin/bash
cd "/Users/berkaycit/Documents/GitHub/utility/flow"
/usr/bin/env python3 python-yt-digest/yt_digest.py &
/usr/bin/env python3 python-hn-digest/hn_digest.py &
wait