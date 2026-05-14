#!/bin/bash
# C25 UNIFIED BUILD + DEPLOY
# One script deploys ALL repos via YesQuid Task Worker
# Usage: bash c25-unified-deploy.sh [plan_id]

set -euo pipefail

PLAN_ID="${1:-52f7b763}"
HOME_DIR="${HOME:=$(eval echo ~)}"
TASKS_ROOT="$HOME_DIR/tasks"
ACTIVE_DIR="$TASKS_ROOT/active/plan_${PLAN_ID}"
REPOS=(
  "VideoCourts"
  "SovereignGTP"
  "PaThosAi"
  "constellation25"
  "MyBuyo"
  "TotalRecall"
)

PASS=0
FAIL=0
SKIPPED=0

# Colors
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
NC='\033[0m'

log() { echo -e "${C}[C25]${NC} $*"; }
pass() { echo -e "${G}✓${NC} $*"; ((PASS++)); }
fail() { echo -e "${R}✗${NC} $*"; ((FAIL++)); }
skip() { echo -e "${Y}→${NC} $*"; ((SKIPPED++)); }

# ──────────────────────────────────────────────────
# TASK GENERATION: Create one task per repo
# ──────────────────────────────────────────────────
generate_tasks() {
  log "═══ GENERATING TASKS FOR ALL REPOS ═══"
  mkdir -p "$ACTIVE_DIR"
  
  for REPO in "${REPOS[@]}"; do
    TASK_FILE="$ACTIVE_DIR/${REPO}.json"
    if [ ! -f "$TASK_FILE" ]; then
      cat > "$TASK_FILE" << EOF
{
  "task_id": "build_${REPO}",
  "title": "Build and Deploy $REPO",
  "priority": "high",
  "step_id": "c25_deploy_${REPO}",
  "goal": "Clone, build, test, and deploy $REPO to production",
  "repo_url": "https://github.com/FacePrintPay/$REPO",
  "plan_id": "$PLAN_ID"
}
EOF
      pass "Task created: build_${REPO}"
    else
      skip "Task exists: build_${REPO}"
    fi
  done
}

# ──────────────────────────────────────────────────
# REPO CLONE: Ensure all repos are cloned
# ──────────────────────────────────────────────────
clone_repos() {
  log "═══ CLONING PRIORITY REPOS ═══"
  REPOS_DIR="$HOME_DIR/repos"
  mkdir -p "$REPOS_DIR"
  
  for REPO in "${REPOS[@]}"; do
    REPO_PATH="$REPOS_DIR/$REPO"
    if [ ! -d "$REPO_PATH" ]; then
      log "Cloning $REPO..."
      if git clone "https://github.com/FacePrintPay/$REPO.git" "$REPO_PATH" 2>/dev/null; then
        pass "Cloned: $REPO"
      else
        fail "Clone failed: $REPO"
      fi
    else
      skip "Already cloned: $REPO"
    fi
  done
}

# ──────────────────────────────────────────────────
# BUILD: Process each repo
# ──────────────────────────────────────────────────
build_repos() {
  log "═══ BUILDING ALL REPOS ═══"
  REPOS_DIR="$HOME_DIR/repos"
  
  for REPO in "${REPOS[@]}"; do
    REPO_PATH="$REPOS_DIR/$REPO"
    if [ ! -d "$REPO_PATH" ]; then
      fail "Repo not found: $REPO_PATH"
      continue
    fi
    
    log "Building $REPO..."
    cd "$REPO_PATH"
    
    # Detect and build
    if [ -f "package.json" ]; then
      npm install --silent 2>/dev/null && npm run build 2>/dev/null && pass "Built (NPM): $REPO" || fail "Build failed: $REPO"
    elif [ -f "requirements.txt" ]; then
      pip install -q -r requirements.txt 2>/dev/null && pass "Built (Python): $REPO" || fail "Build failed: $REPO"
    elif [ -f "Dockerfile" ]; then
      docker build -t "c25/${REPO,,}:latest" . 2>/dev/null && pass "Built (Docker): $REPO" || fail "Build failed: $REPO"
    else
      skip "No build config found: $REPO"
    fi
  done
}

# ──────────────────────────────────────────────────
# DEPLOY: Push to Vercel/Docker/GH Pages
# ──────────────────────────────────────────────────
deploy_repos() {
  log "═══ DEPLOYING ALL REPOS ═══"
  REPOS_DIR="$HOME_DIR/repos"
  
  for REPO in "${REPOS[@]}"; do
    REPO_PATH="$REPOS_DIR/$REPO"
    cd "$REPO_PATH"
    
    # Vercel deployment (React/Next apps)
    if [ -f "vercel.json" ] || [ -f "package.json" ]; then
      if vercel --prod -e NODE_ENV=production 2>/dev/null | grep -q "Deployed"; then
        pass "Deployed (Vercel): $REPO"
      else
        fail "Vercel deploy failed: $REPO"
      fi
    fi
    
    # Docker deployment (FastAPI/backends)
    if [ -f "Dockerfile" ]; then
      REGISTRY="docker.io/faceprintpay"
      if docker push "$REGISTRY/${REPO,,}:latest" 2>/dev/null; then
        pass "Pushed (Docker): $REPO"
      else
        skip "Docker push skipped (no auth): $REPO"
      fi
    fi
  done
}

# ──────────────────────────────────────────────────
# YESQUID PROCESSING: Mark tasks done
# ──────────────────────────────────────────────────
process_tasks() {
  log "═══ PROCESSING TASKS WITH YESQUID ═══"
  WORKER_SCRIPT="$HOME_DIR/c25-yesquid-task-worker/yesquid_task_worker.sh"
  
  if [ ! -f "$WORKER_SCRIPT" ]; then
    fail "YesQuid worker not found: $WORKER_SCRIPT"
    return 1
  fi
  
  for REPO in "${REPOS[@]}"; do
    if bash "$WORKER_SCRIPT" "$PLAN_ID" 2>/dev/null; then
      pass "Task processed: build_${REPO}"
    else
      fail "Task processing failed: build_${REPO}"
    fi
  done
}

# ──────────────────────────────────────────────────
# REPORT: Final status
# ──────────────────────────────────────────────────
report() {
  log "════════════════════════════════════"
  log "C25 UNIFIED DEPLOY COMPLETE"
  log "════════════════════════════════════"
  echo -e "${G}  ✓ PASSED:  $PASS${NC}"
  echo -e "${Y}  ⚡ SKIPPED: $SKIPPED${NC}"
  echo -e "${R}  ✗ FAILED:  $FAIL${NC}"
  echo ""
  echo "📍 Task Queue:  $ACTIVE_DIR"
  echo "📊 Vercel:      https://vercel.com/dashboard"
  echo "🐙 GitHub:      https://github.com/orgs/FacePrintPay"
  echo "🚀 Status:      $([ $FAIL -eq 0 ] && echo 'ALL GREEN' || echo 'REVIEW FAILURES')"
}

# ──────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────
main() {
  clear
  log "╔════════════════════════════════════════════╗"
  log "║     C25 UNIFIED BUILD + DEPLOY            ║"
  log "║     All Repos → One Build → Production    ║"
  log "╚════════════════════════════════════════════╝"
  echo ""
  
  generate_tasks
  echo ""
  
  clone_repos
  echo ""
  
  build_repos
  echo ""
  
  deploy_repos
  echo ""
  
  process_tasks
  echo ""
  
  report
}

main "$@"
