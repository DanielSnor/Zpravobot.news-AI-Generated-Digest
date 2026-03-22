#!/bin/bash
# ============================================================
# AI Digest: Sync Test → Production
# ============================================================
# Synchronizuje kód z test prostředí do produkce.
# Vynechává soubory specifické pro prostředí a runtime data.
#
# Umístění: /app/data/zbnw-ai-digest-test/scripts/sync_test_to_prod.sh
# Použití:  ./scripts/sync_test_to_prod.sh [--dry-run]
# ============================================================

set -e

TEST_DIR="/app/data/zbnw-ai-digest-test"
PROD_DIR="/app/data/zbnw-ai-digest"

# Barvy
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Dry run mode
DRY_RUN=false
if [ "$1" == "--dry-run" ]; then
    DRY_RUN=true
    echo -e "${YELLOW}=== DRY RUN MODE ===${NC}"
    echo ""
fi

copy_file() {
    local src="$1"
    local dest="$2"
    local label="$3"

    if [ "$DRY_RUN" == true ]; then
        echo -e "  ${YELLOW}[DRY]${NC} $label"
    else
        cp "$src" "$dest"
        echo -e "  ${GREEN}✔${NC} $label"
    fi
}

echo "============================================================"
echo -e "  ${CYAN}Sync: $TEST_DIR → $PROD_DIR${NC}"
echo "============================================================"
echo ""

# ============================================================
# 1. bin/*.rb
# ============================================================
echo -e "${CYAN}=== bin/*.rb ===${NC}"
mkdir -p "$PROD_DIR/bin"
for f in "$TEST_DIR"/bin/*.rb; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    copy_file "$f" "$PROD_DIR/bin/" "bin/$fname"
done
echo ""

# ============================================================
# 2. lib/*.rb
# ============================================================
echo -e "${CYAN}=== lib/*.rb ===${NC}"
mkdir -p "$PROD_DIR/lib"
if [ "$DRY_RUN" == true ]; then
    echo -e "  ${YELLOW}[DRY]${NC} rsync lib/ ($(find "$TEST_DIR/lib" -name "*.rb" | wc -l) souborů)"
else
    rsync -av --include='*.rb' --exclude='*' \
        "$TEST_DIR/lib/" "$PROD_DIR/lib/" | grep -E "\.rb$" | while read line; do
        echo -e "  ${GREEN}✔${NC} lib/$line"
    done || true
    echo -e "  ${GREEN}✔${NC} lib/ synced"
fi
echo ""

# ============================================================
# 3. *.sh v rootu (kromě env.sh)
# ============================================================
echo -e "${CYAN}=== *.sh (root) ===${NC}"
for f in "$TEST_DIR"/*.sh; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    if [ "$fname" != "env.sh" ]; then
        copy_file "$f" "$PROD_DIR/" "$fname"
    else
        echo -e "  ${YELLOW}⭐${NC} $fname (excluded)"
    fi
done
echo ""

# ============================================================
# 4. scripts/*.sh
# ============================================================
echo -e "${CYAN}=== scripts/*.sh ===${NC}"
mkdir -p "$PROD_DIR/scripts"
for f in "$TEST_DIR"/scripts/*.sh; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    copy_file "$f" "$PROD_DIR/scripts/" "scripts/$fname"
done
echo ""

# ============================================================
# 5. config/*.yml
# ============================================================
echo -e "${CYAN}=== config/*.yml ===${NC}"
mkdir -p "$PROD_DIR/config"
for f in "$TEST_DIR"/config/*.yml; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    copy_file "$f" "$PROD_DIR/config/" "config/$fname"
done
echo ""

# ============================================================
# 6. config/negative_keywords.txt
# ============================================================
echo -e "${CYAN}=== config/negative_keywords.txt ===${NC}"
if [ -f "$TEST_DIR/config/negative_keywords.txt" ]; then
    copy_file "$TEST_DIR/config/negative_keywords.txt" "$PROD_DIR/config/" "config/negative_keywords.txt"
fi
echo ""

# ============================================================
# 7. cache/
# ============================================================
echo -e "${CYAN}=== cache/ ===${NC}"
mkdir -p "$PROD_DIR/cache"
if [ "$DRY_RUN" == true ]; then
    echo -e "  ${YELLOW}[DRY]${NC} rsync cache/ ($(find "$TEST_DIR/cache" -type f 2>/dev/null | wc -l) souborů)"
else
    rsync -av "$TEST_DIR/cache/" "$PROD_DIR/cache/" | grep -v '/$' | grep -v '^$' | while read line; do
        echo -e "  ${GREEN}✔${NC} cache/$line"
    done || true
    echo -e "  ${GREEN}✔${NC} cache/ synced"
fi
echo ""

# ============================================================
# 8. docs/
# ============================================================
echo -e "${CYAN}=== docs/ ===${NC}"
if [ -d "$TEST_DIR/docs" ]; then
    if [ "$DRY_RUN" == true ]; then
        echo -e "  ${YELLOW}[DRY]${NC} rsync docs/ ($(find "$TEST_DIR/docs" -type f 2>/dev/null | wc -l) souborů)"
    else
        rsync -av --delete "$TEST_DIR/docs/" "$PROD_DIR/docs/" | grep -v '/$' | grep -v '^$' | while read line; do
            echo -e "  ${GREEN}✔${NC} docs/$line"
        done || true
        echo -e "  ${GREEN}✔${NC} docs/ synced"
    fi
fi
echo ""

# ============================================================
# 9. Gemfile
# ============================================================
echo -e "${CYAN}=== Gemfile ===${NC}"
if [ -f "$TEST_DIR/Gemfile" ]; then
    copy_file "$TEST_DIR/Gemfile" "$PROD_DIR/" "Gemfile"
fi
echo ""

# ============================================================
# OVĚŘENÍ
# ============================================================
echo "============================================================"
echo -e "  ${CYAN}Ověření${NC}"
echo "============================================================"
echo ""
echo "bin/*.rb:  $(ls -1 "$PROD_DIR"/bin/*.rb 2>/dev/null | wc -l) souborů"
echo "lib/*.rb:  $(find "$PROD_DIR/lib" -name "*.rb" 2>/dev/null | wc -l) souborů"
echo "*.sh:      $(ls -1 "$PROD_DIR"/*.sh 2>/dev/null | wc -l) souborů"
echo "config/:   $(ls -1 "$PROD_DIR"/config/*.yml 2>/dev/null | wc -l) yml souborů"
echo ""

if [ "$DRY_RUN" == true ]; then
    echo -e "${YELLOW}=== DRY RUN — žádné změny provedeny ===${NC}"
else
    echo -e "${GREEN}=== Synchronizace dokončena ===${NC}"
fi
