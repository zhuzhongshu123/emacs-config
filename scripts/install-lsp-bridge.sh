#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
upstream_commit=fa2addb4dd9fe81770ca6afa097830ab250093d7
source_dir="$repo_root/lsp-bridge"
tools_dir="$repo_root/.cache/python-tools"
mkdir -p "$repo_root/.cache"

if [[ ! -f "$source_dir/lsp-bridge.el" ]]; then
    if [[ -e "$source_dir" ]]; then
        echo "Existing lsp-bridge directory is incomplete; inspect it before retrying." >&2
        exit 1
    fi
    stage=$(mktemp -d "$repo_root/.cache/lsp-bridge-install.XXXXXX")
    trap 'rm -rf "$stage"' EXIT
    if timeout 45 git clone --depth 1 https://github.com/manateelazycat/lsp-bridge.git "$stage/source"; then
        if [[ $(git -C "$stage/source" rev-parse HEAD) != "$upstream_commit" ]]; then
            git -C "$stage/source" fetch --depth 1 origin "$upstream_commit"
            git -C "$stage/source" checkout --detach "$upstream_commit"
        fi
        mv "$stage/source" "$source_dir"
    else
        echo "Git transport unavailable; downloading the official pinned source archive."
        curl --fail --location --connect-timeout 15 --max-time 120 \
            "https://codeload.github.com/manateelazycat/lsp-bridge/tar.gz/$upstream_commit" \
            --output "$stage/source.tar.gz"
        mkdir "$stage/archive"
        tar -xzf "$stage/source.tar.gz" -C "$stage/archive" --strip-components=1
        mv "$stage/archive" "$source_dir"
        printf '%s\n' "$upstream_commit" > "$source_dir/SOURCE_COMMIT"
    fi
else
    echo "Keeping the existing lsp-bridge source."
fi

if [[ ! -x "$tools_dir/bin/python" ]]; then
    python3 -m venv "$tools_dir"
fi
"$tools_dir/bin/python" -m pip install \
    epc orjson sexpdata six setuptools paramiko rapidfuzz watchdog packaging ty ruff
echo "LSP Bridge dependencies are ready. Restart Emacs to activate the terminal config."
