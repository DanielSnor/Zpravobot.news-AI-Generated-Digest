# 🚀 QUICK REFERENCE
## Zprávobot AI Digest — Admin Cheat Sheet

---

## ⏰ DENNÍ TIMELINE

```
05:30 - sync_accounts.rb
06:00 - CSV export (posts-latest.csv)
07:00 - @zpravobot publikuje
12:00 - @slunkobot publikuje + @zpravobot boostuje
19:00 - @hrubot publikuje + @zpravobot boostuje
```

---

## 🧪 TESTOVACÍ PŘÍKAZY

```bash
# Dry run (bez publikování)
./run-digest.sh zpravobot --dry-run
./run-digest.sh slunkobot --dry-run
./run-digest.sh hrubot --dry-run

# Sync kategorií účtů
ruby bin/sync_accounts.rb

# Boost manuálně
ruby bin/boost_digest.rb --from=slunkobot --with=zpravobot
ruby bin/boost_digest.rb --from=hrubot --with=zpravobot
```

---

## 🚀 PRODUKČNÍ PŘÍKAZY

```bash
# Spustit bota
./run-digest.sh zpravobot
./run-digest.sh slunkobot
./run-digest.sh hrubot
```

---

## 📋 MONITORING

```bash
# Živý log dnešního běhu
tail -f logs/zpravobot_$(date +%Y%m%d)*.log

# Dnešní log soubory
ls -la logs/*$(date +%Y%m%d)*.log

# Chyby
grep "ERROR\|❌" logs/zpravobot_$(date +%Y%m%d)*.log

# Ověření CSV (počet postů)
wc -l data/posts-latest.csv

# Datum prvního a posledního záznamu v CSV
awk -F',' 'NR>1 {print $2}' data/posts-latest.csv | sort | head -1
awk -F',' 'NR>1 {print $2}' data/posts-latest.csv | sort | tail -1
```

---

## 🔍 DEBUGGING

```bash
# Ověření env proměnných
echo $ZPRAVOBOT_TOKEN
echo $SLUNKOBOT_TOKEN
echo $HRUBOT_TOKEN
echo $ANTHROPIC_API_KEY

# Cache účtů
wc -l cache/accounts_categories.yml
# Očekáváno: ~510 účtů

# Stav idempotence
cat .state/last_thread.json

# Crontab
crontab -l | grep digest
crontab -l | grep sync
```

---

## 🔧 TROUBLESHOOTING

### Žádné posty / málo postů
```bash
# Ověř CSV
wc -l data/posts-latest.csv
# Mělo by být >2000 řádků

# Ověř datum v CSV (mělo by být yesterday)
awk -F',' 'NR==2 {print $2}' data/posts-latest.csv
```

### Token error
```bash
source env.sh
echo $ZPRAVOBOT_TOKEN  # nesmí být prázdné
```

### Claude API error
```bash
# 401 = špatný klíč
echo $ANTHROPIC_API_KEY

# 429 = rate limit — počkej a znovu spusť
```

### Duplikátní publikování
```bash
# Idempotence — systém kontroluje .state/
cat .state/last_thread.json
# Pokud je tam dnešní datum, přeskočí publikování
```

### Sync účtů selhal
```bash
# Ověř cestu k mastodon_accounts.yml
ls -la ../zbnw-ng/config/mastodon_accounts.yml

# Manuální sync
ruby bin/sync_accounts.rb
```

---

## 🚨 NOUZOVÉ PROCEDURY

### Zastavit všechny běhy okamžitě
```bash
crontab -e
# Zakomentuj digest řádky (#)

# Kill running processes
pkill -f publish_digest
pkill -f run-digest
```

### Znovu spustit zmeškané publikování
```bash
# Smaž state (aby to nebylo považováno za duplikát)
rm .state/zpravobot_*.json 2>/dev/null

# Spusť manuálně
./run-digest.sh zpravobot
```

### Reset cache účtů
```bash
ruby bin/sync_accounts.rb
```

---

## 📂 DŮLEŽITÉ CESTY (produkce)

```
Projekt:    /app/data/zbnw-ai-digest-test/
Skript:     ./run-digest.sh
Logy:       logs/{bot}_{YYYYMMDD_HHMMSS}.log
CSV:        data/posts-latest.csv
Cache:      cache/accounts_categories.yml
Config:     config/global.yml + config/bots.yml
State:      .state/
Env:        env.sh
```

---

## ✅ INDIKÁTORY ZDRAVÍ

Denní check (vše by mělo být ✅):

- [ ] CSV aktualizováno dnes (`ls -lh data/posts-latest.csv`)
- [ ] Více než 2000 postů v CSV (`wc -l data/posts-latest.csv`)
- [ ] 3 log soubory dnes (`ls logs/*$(date +%Y%m%d)*`)
- [ ] Žádné chyby v lozích (`grep "ERROR" logs/*$(date +%Y%m%d)*`)
- [ ] Mastodon profily aktualizovány:
  - https://zpravobot.news/@zpravobot
  - https://zpravobot.news/@slunkobot
  - https://zpravobot.news/@hrubot

---

**Verze:** 2.0.0 | **Aktualizováno:** březen 2026
