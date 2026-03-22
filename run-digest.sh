#!/bin/bash
#
# Zprávobot Digest Runner
# Wrapper pro bin/publish_digest.rb
#
# Použití:
#   ./run-digest.sh <bot_name> [options]
#
# Příklady:
#   ./run-digest.sh zpravobot --dry-run
#   ./run-digest.sh slunkobot --visibility=unlisted
#   ./run-digest.sh hrubot
#
#   # Aliasy (zpětná kompatibilita):
#   ./run-digest.sh pozitivni   → spustí slunkobot
#   ./run-digest.sh sarkasticky → spustí hrubot
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Načtení prostředí ---
if [ -f "$SCRIPT_DIR/env.sh" ]; then
  source "$SCRIPT_DIR/env.sh"
elif [ -f "$SCRIPT_DIR/config/config.env" ]; then
  # Zpětná kompatibilita
  source "$SCRIPT_DIR/config/config.env"
fi

# --- CSV cesta ---
if [ -z "$CSV_PATH" ]; then
  if [ -f "$SCRIPT_DIR/data/posts-latest.csv" ]; then
    export CSV_PATH="$SCRIPT_DIR/data/posts-latest.csv"
  else
    export CSV_PATH="/app/data/posts-latest.csv"
  fi
fi

export TZ="${TZ:-Europe/Prague}"

# --- Kontrola argumentu ---
if [ -z "$1" ]; then
  echo "❌ Chybí jméno bota"
  echo "Použití: $0 <bot_name> [options]"
  echo ""
  echo "Dostupní boti:"
  echo "  zpravobot  - Neutrální ranní přehled (7:30)"
  echo "  slunkobot  - Pozitivní polední přehled (12:00)"
  echo "  hrubot     - Sarkastický večerní přehled (19:00)"
  echo ""
  echo "Aliasy: pozitivni → slunkobot, sarkasticky → hrubot"
  exit 1
fi

# --- Alias přeložení (pro bin/publish_digest.rb jsou aliasy zpracovány interně) ---
BOT_NAME="$1"

# --- Logging setup ---
mkdir -p "$SCRIPT_DIR/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$SCRIPT_DIR/logs/${BOT_NAME}_${TIMESTAMP}.log"

DRY_RUN=false
for arg in "${@:2}"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=true && break
done

echo "============================================================" | tee -a "$LOG_FILE"
echo "🚀 Spouštím $BOT_NAME ($(date))" | tee -a "$LOG_FILE"
echo "📝 Log: $LOG_FILE" | tee -a "$LOG_FILE"
[ "$DRY_RUN" = true ] && echo "🧪 DRY RUN" | tee -a "$LOG_FILE"
echo "============================================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# --- Spuštění ---
ruby bin/publish_digest.rb --bot="$BOT_NAME" "${@:2}" 2>&1 | tee -a "$LOG_FILE"
EXIT_CODE=${PIPESTATUS[0]}

echo "" | tee -a "$LOG_FILE"
echo "============================================================" | tee -a "$LOG_FILE"
if [ $EXIT_CODE -eq 0 ]; then
  echo "✅ $BOT_NAME dokončen $(date)" | tee -a "$LOG_FILE"
else
  echo "❌ $BOT_NAME selhal (exit $EXIT_CODE) $(date)" | tee -a "$LOG_FILE"
fi
echo "📝 Log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "============================================================" | tee -a "$LOG_FILE"

# Smaž logy starší 7 dní
find "$SCRIPT_DIR/logs" -name "${BOT_NAME}_*.log" -mtime +7 -delete 2>/dev/null || true

# Po úspěšném publishování slunkobota nebo hrubota: zpravobot automaticky boostne
if [ $EXIT_CODE -eq 0 ] && [ "$DRY_RUN" = false ]; then
  RESOLVED_BOT=$(ruby -e "
    b = '$BOT_NAME'
    b = 'slunkobot' if b == 'pozitivni'
    b = 'hrubot'    if b == 'sarkasticky'
    puts b
  " 2>/dev/null)

  if [ "$RESOLVED_BOT" = "slunkobot" ] || [ "$RESOLVED_BOT" = "hrubot" ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "🔁 Boosting ${RESOLVED_BOT} → zpravobot..." | tee -a "$LOG_FILE"
    ruby bin/boost_digest.rb --from="$RESOLVED_BOT" --with=zpravobot 2>&1 | tee -a "$LOG_FILE"
    BOOST_EXIT=${PIPESTATUS[0]}
    if [ $BOOST_EXIT -eq 0 ]; then
      echo "✅ Boost úspěšný" | tee -a "$LOG_FILE"
    else
      echo "⚠️  Boost selhal (exit $BOOST_EXIT) — digest byl publikován" | tee -a "$LOG_FILE"
    fi
  fi
fi

exit $EXIT_CODE
