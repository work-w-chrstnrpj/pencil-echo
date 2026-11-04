#!/bin/bash
# Simulator-independent checks against exact application/model/provider sources.
# Rendering/thumbnail shims are explicit in tests/native/EditorChatChecks.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/pencilecho-native.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
python3 - "$check_dir/StreamingChatReply.swift" <<'PY'
from pathlib import Path
import sys
source = Path('application/App/AskAI/AgentChatController.swift').read_text()
marker = 'enum StreamingChatReply {'
assert source.count(marker) == 1, 'StreamingChatReply source moved; update the verification script.'
Path(sys.argv[1]).write_text('import Foundation\n' + source[source.index(marker):])
PY
# PencilKit's replica preferences require a non-nil bundle identity, even in a CLI.
cat > "$check_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.chrixcrusher.pencilecho.nativechecks</string>
<key>CFBundleName</key><string>Pencil Echo Native Checks</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
sdk_path=$(xcrun --sdk macosx --show-sdk-path)
swiftc -whole-module-optimization -Onone -parse-as-library -swift-version 6 -sdk "$sdk_path" \
    shared/Document/DocumentModel.swift shared/Document/DocumentMigrator.swift \
    service/Providers/*.swift service/AI/ModelContent.swift service/Persistence/DocumentStore.swift \
    application/App/Editor/EditorLayout.swift application/App/Editor/EditorSession.swift \
    "$check_dir/StreamingChatReply.swift" tests/native/EditorChatChecks.swift \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$check_dir/Info.plist" \
    -o "$check_dir/checks"
"$check_dir/checks"
