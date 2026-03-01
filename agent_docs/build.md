# Build & Run

## Swift App (Xcode)
```bash
# Build from command line (requires Xcode.app, not just CLI tools)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project flow.xcodeproj -scheme flow -destination 'platform=macOS' build

# Resolve Swift packages
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project flow.xcodeproj -scheme flow -resolvePackageDependencies
```

Or open `flow.xcodeproj` in Xcode and build normally (Cmd+B).

## Python Scripts
```bash
# Install dependencies
pip3 install -r python-yt-digest/requirements.txt
pip3 install -r python-hn-digest/requirements.txt

# Run individually
python3 python-yt-digest/yt_digest.py          # today's new videos only
python3 python-hn-digest/hn_digest.py          # today's new stories only
python3 python-yt-digest/yt_digest.py --all    # last 3 videos per channel
python3 python-hn-digest/hn_digest.py --all    # all front page stories

# Run both in parallel
./run_digests.sh
```

Scripts require Claude CLI (`claude`) on PATH. They filter out the `CLAUDECODE` env var to prevent recursion when invoked from Claude Code.
