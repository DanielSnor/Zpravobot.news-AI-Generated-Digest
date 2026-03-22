#!/bin/bash
# ============================================================
# AI Digest: Sync Local → Test
# ============================================================
# Synchronizuje lokální kód (Mac) do test prostředí na serveru.
# Vynechává soubory specifické pro prostředí a runtime data.
#
# Použití: ./scripts/sync_local_to_test.sh [--dry-run]
# ============================================================

set -e

LOCAL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

REMOTE="dan@116.203.134.0"
REMOTE_PORT="202"
TEST_DIR="/home/yellowtent/appsdata/b8ee5072-a44f-4209-8681-56b882968922/data/zbnw-ai-digest-test"

SSH_CTRL="/tmp/zbnw-ai-digest-sync-$$"
SSH_OPTS="-p $REMOTE_PORT -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o ControlPath=$SSH_CTRL -o ControlPersist=120"

# Otevři master SSH spojení
ssh $SSH_OPTS $REMOTE true 2>/dev/null || true
trap "ssh -O exit -o ControlPath=$SSH_CTRL $REMOTE 2>/dev/null; true" EXIT

# Barvy
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Dry run mode
DRY_RUN=false
RSYNC_DRY=""
if [ "$1" == "--dry-run" ]; then
    DRY_RUN=true
    RSYNC_DRY="--dry-run"
    echo -e "${YELLOW}=== DRY RUN MODE ===${NC}"
    echo ""
fi

do_rsync() {
    rsync -avz $RSYNC_DRY --exclude='.DS_Store' --rsync-path="sudo rsync" -e "ssh $SSH_OPTS" "$@"
}

echo "============================================================"
echo -e "  ${CYAN}Sync: $LOCAL_DIR → $REMOTE:$TEST_DIR${NC}"
echo "============================================================"
echo ""

# ============================================================
# 1. bin/*.rb
# ============================================================
echo -e "${CYAN}=== bin/*.rb ===${NC}"
do_rsync \
    --include='*.rb' \
    --exclude='*' \
    "$LOCAL_DIR/bin/" "$REMOTE:$TEST_DIR/bin/"
echo ""

# ============================================================
# 2. lib/*.rb
# ============================================================
echo -e "${CYAN}=== lib/*.rb ===${NC}"
do_rsync \
    --include='*.rb' \
    --exclude='*' \
    "$LOCAL_DIR/lib/" "$REMOTE:$TEST_DIR/lib/"
echo ""

# ============================================================
# 3. *.sh v rootu (kromě env.sh)
# ============================================================
echo -e "${CYAN}=== *.sh (root) ===${NC}"
do_rsync \
    --exclude='env.sh' \
    --include='*.sh' \
    --exclude='*' \
    "$LOCAL_DIR/" "$REMOTE:$TEST_DIR/"
echo ""

# ============================================================
# 4. scripts/*.sh
# ============================================================
echo -e "${CYAN}=== scripts/*.sh ===${NC}"
do_rsync \
    --include='*.sh' \
    --exclude='*' \
    "$LOCAL_DIR/scripts/" "$REMOTE:$TEST_DIR/scripts/"
echo ""

# ============================================================
# 5. config/*.yml
# ============================================================
echo -e "${CYAN}=== config/*.yml ===${NC}"
do_rsync \
    --include='*.yml' \
    --exclude='*' \
    "$LOCAL_DIR/config/" "$REMOTE:$TEST_DIR/config/"
echo ""

# ============================================================
# 6. config/negative_keywords.txt + domain_whitelist.yml
# ============================================================
echo -e "${CYAN}=== config/negative_keywords.txt ===${NC}"
if [ -f "$LOCAL_DIR/config/negative_keywords.txt" ]; then
    do_rsync "$LOCAL_DIR/config/negative_keywords.txt" "$REMOTE:$TEST_DIR/config/"
fi
echo ""

# ============================================================
# 7. cache/
# ============================================================
echo -e "${CYAN}=== cache/ ===${NC}"
do_rsync \
    "$LOCAL_DIR/cache/" "$REMOTE:$TEST_DIR/cache/"
echo ""

# ============================================================
# 8. docs/
# ============================================================
echo -e "${CYAN}=== docs/ ===${NC}"
if [ -d "$LOCAL_DIR/docs" ]; then
    do_rsync "$LOCAL_DIR/docs/" "$REMOTE:$TEST_DIR/docs/"
fi
echo ""

# ============================================================
# 9. Gemfile
# ============================================================
echo -e "${CYAN}=== Gemfile ===${NC}"
if [ -f "$LOCAL_DIR/Gemfile" ]; then
    do_rsync "$LOCAL_DIR/Gemfile" "$REMOTE:$TEST_DIR/Gemfile"
fi
echo ""

# ============================================================
# HOTOVO
# ============================================================
echo "============================================================"
if [ "$DRY_RUN" == true ]; then
    echo -e "${YELLOW}=== DRY RUN — žádné změny provedeny ===${NC}"
else
    echo -e "${GREEN}=== Synchronizace dokončena ===${NC}"
fi
