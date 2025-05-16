#!/bin/bash
# 1. Go to your branch
git checkout main

# 2. Fetch latest from remote
git fetch origin

# 3. Force local branch to match remote (discards local changes/commits on this branch for tracked files)
git reset --hard origin/main

# 4. (Optional, use with CAUTION if needed for other untracked files)
# git clean -fdn  # See what would be removed
# git clean -fd   # Remove untracked files and directories (leaves ignored files like .env)