#!/bin/bash
# One-shot publish to GitHub.
#
# Preferred (GitHub CLI already installed):
#   ./publish_to_github.sh                 # creates a private repo named invisible-watermark
#   ./publish_to_github.sh --public        # public repo
#
# Without gh, pass a repository URL that includes a token:
#   ./publish_to_github.sh https://<token>@github.com/<user>/invisible-watermark.git
#
# After the push the "Build IPA" workflow runs on GitHub's macOS runner and
# produces both unsigned IPAs as a downloadable artifact.
set -euo pipefail
cd "$(dirname "$0")"

REPO_NAME="invisible-watermark"
VISIBILITY="--private"

if [ "${1:-}" = "--public" ]; then
  VISIBILITY="--public"
  shift || true
fi

REMOTE="${1:-}"

echo "== 提交本地改动 =="
if [ ! -d .git ]; then
  git init -q
  git symbolic-ref HEAD refs/heads/main
fi
git add -A
if ! git rev-parse HEAD >/dev/null 2>&1; then
  git -c user.name="${GIT_AUTHOR_NAME:-watermark}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-watermark@local}" \
      commit -qm "Invisible watermark iOS port"
elif ! git diff --cached --quiet; then
  git -c user.name="${GIT_AUTHOR_NAME:-watermark}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-watermark@local}" \
      commit -qm "Update iOS port"
fi

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "== 使用 GitHub CLI 创建仓库 =="
  if ! git remote get-url origin >/dev/null 2>&1; then
    gh repo create "$REPO_NAME" "$VISIBILITY" --source=. --remote=origin --push
  else
    git push -u origin main
  fi
  URL=$(gh repo view --json url -q .url)
  echo ""
  echo "仓库：$URL"
  echo "Actions: $URL/actions"
  echo ""
  echo "下一步：打开上面的 Actions 页面 → Build IPA → Run workflow"
  echo "完成后在底部 Artifacts 下载 unsigned-ipas（含两个未签名 IPA）。"
  exit 0
fi

if [ -z "$REMOTE" ]; then
  cat >&2 <<'EOF'
这台机器没有可用的 GitHub 凭据（gh 未登录、无 SSH key、无 token）。

任选一种方式：

A. 安装并登录 GitHub CLI（推荐）
   https://cli.github.com
   gh auth login
   ./publish_to_github.sh

B. 在网页上手动建仓库，然后用带 token 的地址推送
   https://github.com/new   （仓库名 invisible-watermark，不要勾选 README）
   ./publish_to_github.sh https://<你的PAT>@github.com/<用户名>/invisible-watermark.git

   PAT 需要 repo 与 workflow 权限：
   https://github.com/settings/tokens

推送完成后，在仓库的 Actions 页面手动运行 Build IPA，
下载 artifact unsigned-ipas，里面就是两个未签名 IPA。
EOF
  exit 1
fi

echo "== 推送到 $REMOTE =="
git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE"
git push -u origin main

echo ""
echo "推送完成。打开仓库的 Actions 页面运行 Build IPA："
echo "  ${REMOTE#*@github.com/}" | sed 's#^#  https://github.com/#'
echo "完成后下载 artifact unsigned-ipas。"
