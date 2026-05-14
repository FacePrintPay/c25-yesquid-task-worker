#!/bin/bash
# C25 Real Source Puller - Pull from REAL Termux home & Obsidian vaults
# Cygel White / FacePrintPay Inc
# Constellation25 - Sovereign AI Build System
# 
# Usage: bash c25-real-source-puller.sh
# 
# This script:
# 1. Scans /data/data/com.termux/files/home for ALL C25 projects
# 2. Pulls from Obsidian vaults for markdown/config
# 3. Aggregates into ONE unified C25 codebase
# 4. Generates unified build manifest
# 5. Creates deployment artifacts

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# CONFIG
# ═══════════════════════════════════════════════════════════════

TERMUX_HOME="/data/data/com.termux/files/home"
OBSIDIAN_VAULTS=(
  "$TERMUX_HOME/C25-Vault"
  "$TERMUX_HOME/Obsidian"
  "$HOME/Obsidian/Termux_Sync"
  "$HOME/Documents/Obsidian"
)

BUILD_OUTPUT="$TERMUX_HOME/c25-unified-source"
MANIFEST="$BUILD_OUTPUT/C25_BUILD_MANIFEST.json"
LOG_FILE="$BUILD_OUTPUT/pull.log"

# Colors
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
C='\033[0;36m'
NC='\033[0m'

# ═══════════════════════════════════════════════════════════════
# FUNCTIONS
# ═══════════════════════════════════════════════════════════════

log() { echo -e "${C}[C25-PULL]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${G}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${Y}[!]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${R}[✗]${NC} $1" | tee -a "$LOG_FILE"; }

# Find all C25 projects in Termux home
find_c25_projects() {
  log "Scanning for C25 projects in $TERMUX_HOME..."
  
  local projects=()
  
  # Look for constellation25* directories
  if [ -d "$TERMUX_HOME/Constellation25" ]; then
    projects+=("$TERMUX_HOME/Constellation25")
  fi
  
  if [ -d "$TERMUX_HOME/constellation25" ]; then
    projects+=("$TERMUX_HOME/constellation25")
  fi
  
  if [ -d "$TERMUX_HOME/constellation25-mono" ]; then
    projects+=("$TERMUX_HOME/constellation25-mono")
  fi
  
  # Look for github-repos/Constellation25 tree
  if [ -d "$TERMUX_HOME/github-repos/Constellation25" ]; then
    projects+=("$TERMUX_HOME/github-repos/Constellation25")
  fi
  
  # Look for other main projects
  local main_projects=(
    "VideoCourts"
    "videocourts"
    "MyBuyo"
    "mybuyo"
    "SovereignGTP"
    "sovereign_gtp"
    "PaThosAi"
    "pathos-ai"
    "TotalRecall"
    "total-recall"
    "agentik"
    "aikre8tive"
  )
  
  for proj in "${main_projects[@]}"; do
    [ -d "$TERMUX_HOME/$proj" ] && projects+=("$TERMUX_HOME/$proj")
    [ -d "$TERMUX_HOME/repos/$proj" ] && projects+=("$TERMUX_HOME/repos/$proj")
    [ -d "$TERMUX_HOME/github-repos/$proj" ] && projects+=("$TERMUX_HOME/github-repos/$proj")
  done
  
  # Also check CONSTELLATION25_CODEBASE
  if [ -d "$TERMUX_HOME/CONSTELLATION25_CODEBASE" ]; then
    find "$TERMUX_HOME/CONSTELLATION25_CODEBASE" -maxdepth 3 -type d -name "*constellation*" -o -name "*VideoCourts*" -o -name "*MyBuyo*" | head -20 | while read -r dir; do
      [ -d "$dir" ] && projects+=("$dir")
    done
  fi
  
  printf '%s\n' "${projects[@]}" | sort -u
}

# Find all Obsidian vaults
find_obsidian_vaults() {
  log "Scanning for Obsidian vaults..."
  
  local vaults=()
  
  for vault_path in "${OBSIDIAN_VAULTS[@]}"; do
    if [ -d "$vault_path" ]; then
      vaults+=("$vault_path")
      success "Found vault: $vault_path"
    fi
  done
  
  # Also search for .obsidian directories
  if [ -d "$TERMUX_HOME" ]; then
    while IFS= read -r vault; do
      vaults+=("$vault")
    done < <(find "$TERMUX_HOME" -maxdepth 4 -type d -name ".obsidian" 2>/dev/null | head -10 | sed 's|/.obsidian||')
  fi
  
  printf '%s\n' "${vaults[@]}" | sort -u
}

# Pull source from single project
pull_project_source() {
  local project_path="$1"
  local project_name=$(basename "$project_path")
  
  log "Pulling: $project_name"
  
  local target_dir="$BUILD_OUTPUT/projects/$project_name"
  mkdir -p "$target_dir"
  
  # Copy all source files
  if [ -d "$project_path" ]; then
    # Copy code files
    find "$project_path" \( \
      -name "*.py" -o \
      -name "*.js" -o \
      -name "*.ts" -o \
      -name "*.tsx" -o \
      -name "*.java" -o \
      -name "*.go" -o \
      -name "*.rs" -o \
      -name "*.sh" -o \
      -name "*.json" -o \
      -name "*.yaml" -o \
      -name "*.yml" -o \
      -name "*.md" -o \
      -name "package.json" -o \
      -name "requirements.txt" -o \
      -name "Dockerfile" -o \
      -name "docker-compose.yml" \
    \) -type f 2>/dev/null | while read -r file; do
      local rel_path="${file#$project_path/}"
      local target_file="$target_dir/$rel_path"
      mkdir -p "$(dirname "$target_file")"
      cp "$file" "$target_file" 2>/dev/null || true
    done
    
    success "Pulled $project_name"
    echo "$project_name"
  else
    warn "Project path not found: $project_path"
  fi
}

# Pull markdown from Obsidian vault
pull_obsidian_markdown() {
  local vault_path="$1"
  local vault_name=$(basename "$vault_path")
  
  log "Pulling markdown from: $vault_name"
  
  local target_dir="$BUILD_OUTPUT/obsidian/$vault_name"
  mkdir -p "$target_dir"
  
  # Copy all markdown files
  find "$vault_path" -name "*.md" -type f 2>/dev/null | while read -r file; do
    local rel_path="${file#$vault_path/}"
    local target_file="$target_dir/$rel_path"
    mkdir -p "$(dirname "$target_file")"
    cp "$file" "$target_file" 2>/dev/null || true
  done
  
  # Copy config files
  find "$vault_path" \( -name "*.json" -o -name "*.yaml" \) -maxdepth 2 -type f 2>/dev/null | while read -r file; do
    local rel_path="${file#$vault_path/}"
    local target_file="$target_dir/$rel_path"
    mkdir -p "$(dirname "$target_file")"
    cp "$file" "$target_file" 2>/dev/null || true
  done
  
  success "Pulled markdown from $vault_name"
}

# Generate unified build manifest
generate_manifest() {
  log "Generating unified build manifest..."
  
  local projects_count=$(find "$BUILD_OUTPUT/projects" -maxdepth 1 -type d | wc -l)
  local files_count=$(find "$BUILD_OUTPUT" -type f | wc -l)
  
  cat > "$MANIFEST" << MANIFEST
{
  "c25_unified_source": {
    "version": "1.0.0",
    "timestamp": "$(date -Iseconds)",
    "source_system": "Termux + Obsidian",
    "pull_date": "$(date)",
    "repository": "https://github.com/FacePrintPay/c25-yesquid-task-worker",
    "creator": "Cygel White / FacePrintPay Inc",
    
    "statistics": {
      "total_projects": $((projects_count - 1)),
      "total_files": $files_count,
      "build_output": "$BUILD_OUTPUT"
    },
    
    "projects": [
MANIFEST

  # Add each project
  find "$BUILD_OUTPUT/projects" -maxdepth 1 -type d | tail -n +2 | sort | while read -r proj_dir; do
    local proj_name=$(basename "$proj_dir")
    local file_count=$(find "$proj_dir" -type f | wc -l)
    
    cat >> "$MANIFEST" << PROJECT
      {
        "name": "$proj_name",
        "path": "projects/$proj_name",
        "files": $file_count
      },
PROJECT
  done
  
  # Remove trailing comma
  sed -i '$ s/,$//' "$MANIFEST"
  
  cat >> "$MANIFEST" << MANIFEST
    ],
    
    "obsidian_vaults": [
MANIFEST

  # Add each vault
  if [ -d "$BUILD_OUTPUT/obsidian" ]; then
    find "$BUILD_OUTPUT/obsidian" -maxdepth 1 -type d | tail -n +2 | sort | while read -r vault_dir; do
      local vault_name=$(basename "$vault_dir")
      local file_count=$(find "$vault_dir" -type f | wc -l)
      
      cat >> "$MANIFEST" << VAULT
      {
        "name": "$vault_name",
        "path": "obsidian/$vault_name",
        "files": $file_count
      },
VAULT
    done
    
    # Remove trailing comma
    sed -i '$ s/,$//' "$MANIFEST"
  fi
  
  cat >> "$MANIFEST" << MANIFEST
    ],
    
    "build_instructions": {
      "step_1": "Review manifested source: ls -la $BUILD_OUTPUT",
      "step_2": "Generate YesQuid tasks: bash c25-unified-deploy.sh",
      "step_3": "Deploy all projects: vercel --prod",
      "step_4": "Monitor: tail -f $LOG_FILE"
    },
    
    "next_steps": [
      "Consolidate code across projects",
      "Generate unified Docker image",
      "Deploy to AWS/GovCloud",
      "Update GitHub repositories",
      "Create deployment audit log"
    ]
  }
}
MANIFEST

  success "Manifest generated: $MANIFEST"
}

# Generate aggregated source index
generate_source_index() {
  log "Generating source index..."
  
  local index_file="$BUILD_OUTPUT/SOURCE_INDEX.txt"
  
  cat > "$index_file" << INDEX
═══════════════════════════════════════════════════════════════
C25 UNIFIED SOURCE INDEX
Generated: $(date)
═══════════════════════════════════════════════════════════════

PROJECTS PULLED:
───────────────────────────────────────────────────────────────
INDEX

  find "$BUILD_OUTPUT/projects" -maxdepth 1 -type d | tail -n +2 | sort | while read -r proj_dir; do
    local proj_name=$(basename "$proj_dir")
    local file_count=$(find "$proj_dir" -type f | wc -l)
    local line_count=$(find "$proj_dir" -type f | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
    
    printf "%-40s Files: %4d  Lines: %8s\n" "$proj_name" "$file_count" "$line_count" >> "$index_file"
  done
  
  cat >> "$index_file" << INDEX

OBSIDIAN VAULTS PULLED:
───────────────────────────────────────────────────────────────
INDEX

  if [ -d "$BUILD_OUTPUT/obsidian" ]; then
    find "$BUILD_OUTPUT/obsidian" -maxdepth 1 -type d | tail -n +2 | sort | while read -r vault_dir; do
      local vault_name=$(basename "$vault_dir")
      local file_count=$(find "$vault_dir" -type f | wc -l)
      printf "%-40s Files: %4d\n" "$vault_name" "$file_count" >> "$index_file"
    done
  fi
  
  cat >> "$index_file" << INDEX

DIRECTORY STRUCTURE:
───────────────────────────────────────────────────────────────
INDEX

  tree -L 2 "$BUILD_OUTPUT" 2>/dev/null | head -30 >> "$index_file" || find "$BUILD_OUTPUT" -maxdepth 2 -type d >> "$index_file"
  
  success "Source index: $index_file"
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

main() {
  mkdir -p "$BUILD_OUTPUT"
  
  {
    echo "════════════════════════════════════════════════════════════════"
    echo "C25 REAL SOURCE PULLER - $(date)"
    echo "════════════════════════════════════════════════════════════════"
  } | tee "$LOG_FILE"
  
  # Find and pull all projects
  log "Phase 1: Finding & pulling C25 projects from Termux..."
  echo ""
  
  local project_count=0
  find_c25_projects | while read -r proj_path; do
    [ -n "$proj_path" ] && pull_project_source "$proj_path"
    ((project_count++))
  done
  
  echo ""
  
  # Find and pull Obsidian vaults
  log "Phase 2: Finding & pulling Obsidian vaults..."
  echo ""
  
  find_obsidian_vaults | while read -r vault_path; do
    [ -n "$vault_path" ] && pull_obsidian_markdown "$vault_path"
  done
  
  echo ""
  
  # Generate manifests
  log "Phase 3: Generating unified manifests..."
  generate_manifest
  generate_source_index
  
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  success "PULL COMPLETE"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "Build output: $BUILD_OUTPUT"
  echo "Manifest: $MANIFEST"
  echo "Log: $LOG_FILE"
  echo ""
  echo "Next: bash c25-unified-deploy.sh"
  echo ""
}

main "$@"
