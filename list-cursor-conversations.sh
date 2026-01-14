#!/bin/bash
# Lists the title and working directory of every Cursor conversation across all workspaces.

CURSOR_WORKSPACE_DIR="$HOME/.config/Cursor/User/workspaceStorage"

if [[ ! -d "$CURSOR_WORKSPACE_DIR" ]]; then
    echo "Cursor workspace storage directory not found: $CURSOR_WORKSPACE_DIR" >&2
    exit 1
fi

for workspace_dir in "$CURSOR_WORKSPACE_DIR"/*/; do
    workspace_json="$workspace_dir/workspace.json"
    state_db="$workspace_dir/state.vscdb"

    if [[ ! -f "$workspace_json" ]] || [[ ! -f "$state_db" ]]; then
        continue
    fi

    folder_path=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('folder','').replace('file://',''))" < "$workspace_json" 2>/dev/null)
    if [[ -z "$folder_path" ]]; then
        continue
    fi

    composer_data=$(sqlite3 "$state_db" "SELECT value FROM ItemTable WHERE key='composer.composerData'" 2>/dev/null)
    if [[ -z "$composer_data" ]]; then
        continue
    fi

    titles=$(echo "$composer_data" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for composer in data.get('allComposers', []):
        name = composer.get('name', '')
        if name:
            print(name)
except:
    pass
" 2>/dev/null)

    if [[ -n "$titles" ]]; then
        while IFS= read -r title; do
            printf '%s\t%s\n' "$title" "$folder_path"
        done <<< "$titles"
    fi
done
