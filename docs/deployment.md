# 🚀 DEPLOYMENT GUIDE
## Zprávobot AI Digest — Kompletní průvodce nasazením

**Verze:** 2.0.0
**Datum:** březen 2026

---

## 📋 OBSAH

1. [Přehled systému](#přehled-systému)
2. [Požadavky](#požadavky)
3. [Instalace](#instalace)
4. [Konfigurace](#konfigurace)
5. [Testování](#testování)
6. [Produkční nasazení](#produkční-nasazení)
7. [Monitoring](#monitoring)
8. [Troubleshooting](#troubleshooting)

---

## 🎯 PŘEHLED SYSTÉMU

### Co systém dělá

Denní AI-powered digest pro Mastodon boty zpravobot.news:
- Načte CSV export postů z předchozího dne (generován v 06:00)
- Kategorizuje posty podle zdrojových účtů (510 účtů z mastodon_accounts.yml)
- Vybere reprezentativní články pro každé téma
- Analyzuje obsah pomocí Claude AI
- Sestaví thread (summary toot + extension tooty) a publikuje ho
- @zpravobot automaticky boostuje posty @slunkobot a @hrubot

### Tři boti

| Bot | Čas | Styl | Účel |
|-----|-----|------|------|
| @zpravobot | 07:00 | Neutrální | Ranní přehled dne |
| @slunkobot | 12:00 | Pozitivní | Polední pozitivní výběr |
| @hrubot | 19:00 | Sarkastický | Večerní komentář reality |

### Denní timeline

```
05:30 - sync_accounts.rb (kategorie účtů)
06:00 - CSV export (postgres → posts-latest.csv) ✅ nakonfigurováno
07:00 - @zpravobot publikuje
12:00 - @slunkobot publikuje + @zpravobot boostuje
19:00 - @hrubot publikuje + @zpravobot boostuje
```

### Architektura

```
bin/publish_digest.rb     ← orchestrátor
  ├── lib/config_loader.rb       (config/global.yml + bots.yml)
  ├── lib/account_categorizer.rb (cache/accounts_categories.yml)
  ├── lib/post_reader.rb         (data/posts-latest.csv)
  ├── lib/topic_extractor.rb     (kategorizace postů)
  ├── lib/article_selector.rb    (výběr článků)
  ├── lib/claude_client.rb       (Claude API)
  ├── lib/toot_builder.rb        (sestavení tootů)
  └── lib/mastodon_publisher.rb  (publikování + idempotence)

bin/sync_accounts.rb      ← denní sync z mastodon_accounts.yml
bin/boost_digest.rb       ← boost cizích postů
```

---

## ✅ POŽADAVKY

### Systémové

- **OS:** Linux (Ubuntu 20.04+)
- **Ruby:** 2.6+ (systémový Ruby Mastodonu)
- **Disk:** ~50MB pro projekt + logy
- **Síť:** HTTPS přístup na api.anthropic.com

### Hotové na serveru

- ✅ CSV export skript (běží v 06:00)
- ✅ Mastodon instance (zpravobot.news)
- ✅ Bot účty (@zpravobot, @slunkobot, @hrubot)
- ✅ Zdrojový kód zbnw-ng (pro sync účtů)

### Potřebné klíče

1. **Anthropic API key** — https://console.anthropic.com/
2. **Mastodon tokeny** — jeden pro každého bota (instrukce níže)

---

## 📦 INSTALACE

### Krok 1: Klonování repozitáře

```bash
cd /app/data
git clone <repo-url> zbnw-ai-digest
cd zbnw-ai-digest
```

### Krok 2: Instalace Ruby závislostí

```bash
bundle install
```

Gemfile obsahuje pouze standardní knihovny Ruby (net/http, json, yaml, csv) — žádné externí mastodon gem.

### Krok 3: Adresářová struktura

```bash
mkdir -p data logs cache .state
```

### Krok 4: Generování Mastodon tokenů

Pro každého bota (@zpravobot, @slunkobot, @hrubot):

```bash
cd /home/mastodon/live
RAILS_ENV=production bundle exec rails console
```

```ruby
bot_username = 'zpravobot'  # opakuj pro slunkobot, hrubot

app = Doorkeeper::Application.create!(
  name: "Digest Bot - #{bot_username}",
  redirect_uri: 'urn:ietf:wg:oauth:2.0:oob',
  scopes: 'read write'
)

bot_account = Account.find_by(username: bot_username)
token = Doorkeeper::AccessToken.create!(
  application_id: app.id,
  resource_owner_id: bot_account.user.id,
  scopes: 'read write'
)

puts "#{bot_username}: #{token.token}"
```

Ulož tokeny! Budou potřeba v dalším kroku.

### Krok 5: Konfigurace prostředí

```bash
cp env.sh.example env.sh
nano env.sh
```

Vyplň:
```bash
export ZPRAVOBOT_TOKEN="token_z_rails_console"
export SLUNKOBOT_TOKEN="token_z_rails_console"
export HRUBOT_TOKEN="token_z_rails_console"
export ANTHROPIC_API_KEY="sk-ant-..."
export TZ="Europe/Prague"
```

### Krok 6: Symlink pro CSV

```bash
ln -s /app/data/zbnw/posts-latest.csv data/posts-latest.csv
# nebo nastav cestu v env.sh:
# export CSV_PATH="/app/data/zbnw/posts-latest.csv"
```

---

## ⚙️ KONFIGURACE

### config/global.yml

Hlavní konfigurace systému. Klíčové sekce:

```yaml
mastodon:
  instance: "https://zpravobot.news"
  max_chars: 2500          # limit pro zpravobot.news instanci

digest:
  articles_per_toot: 5    # počet článků na extension toot
  min_excerpt_length: 30  # min. délka excerptů (kratší = přeskočit)

claude:
  model: "claude-sonnet-4-6"
```

### config/bots.yml

Bot-specifické overrides. Příklad pro hrubot:

```yaml
hrubot:
  style: sarcastic
  name: "😏 DNEŠNÍ REALITA"
  hashtags: "#realita #zpravobot"
```

### Hierarchie konfigurace

`global.yml` → `bots.yml` (override) → výsledek

---

## 🧪 TESTOVÁNÍ

### Test 1: Sync účtů

```bash
source env.sh
ruby bin/sync_accounts.rb
```

Očekávaný výstup:
```
[SyncAccounts] Načteno N účtů z mastodon_accounts.yml
[SyncAccounts] Uloženo cache/accounts_categories.yml
```

### Test 2: Dry run pro každého bota

```bash
source env.sh
./run-digest.sh zpravobot --dry-run
./run-digest.sh slunkobot --dry-run
./run-digest.sh hrubot --dry-run
```

Očekávaný výstup:
```
[PostReader] Načteno 2700+ postů pro YYYY-MM-DD
[TopicExtractor] Nalezena témata: Sport(471), Zprávy(1486), ...
[ArticleSelector] Vybráno N článků ze M témat
[MastodonPublisher] === DRY-RUN: zpravobot ===
[SUMMARY TOOT] ...
[EXTENSION 1/N] ...
```

Pokud dry run projde bez chyb, systém je připraven.

### Test 3: Live test (publikuje na Mastodon!)

```bash
./run-digest.sh zpravobot
```

Ověř na https://zpravobot.news/@zpravobot

---

## 🚀 PRODUKČNÍ NASAZENÍ

### Crontab

```bash
crontab -e
```

Přidej:
```bash
# Zprávobot AI Digest
# Sync kategorií účtů
30 5 * * * /app/data/zbnw-ai-digest/run-digest.sh sync >> /app/data/zbnw-ai-digest/logs/sync.log 2>&1

# Ranní digest — zpravobot (neutrální)
0 7 * * * /app/data/zbnw-ai-digest/run-digest.sh zpravobot >> /app/data/zbnw-ai-digest/logs/cron.log 2>&1

# Polední digest — slunkobot (pozitivní)
0 12 * * * /app/data/zbnw-ai-digest/run-digest.sh slunkobot >> /app/data/zbnw-ai-digest/logs/cron.log 2>&1

# Večerní digest — hrubot (sarkastický)
0 19 * * * /app/data/zbnw-ai-digest/run-digest.sh hrubot >> /app/data/zbnw-ai-digest/logs/cron.log 2>&1
```

> Boost @slunkobot a @hrubot spouští `run-digest.sh` automaticky po úspěšném publikování.

### Ověření crontabu

```bash
crontab -l | grep digest
```

### Logování

Každý běh vytvoří vlastní log soubor:
```
logs/zpravobot_20260322_070002.log
logs/slunkobot_20260322_120006.log
logs/hrubot_20260322_190017.log
```

Rotace logů: `lib/logging.rb` automaticky maže logy starší 7 dní.

---

## 📊 MONITORING

### Denní kontrola

```bash
# Dnešní log soubory
ls -la logs/*$(date +%Y%m%d)*.log

# Živý log
tail -f logs/zpravobot_$(date +%Y%m%d)*.log

# Chyby
grep "ERROR\|❌" logs/*$(date +%Y%m%d)*.log

# CSV aktuálnost
ls -lh data/posts-latest.csv
```

### Profily botů

- https://zpravobot.news/@zpravobot
- https://zpravobot.news/@slunkobot
- https://zpravobot.news/@hrubot

---

## 🔧 TROUBLESHOOTING

### Problém: CSV nenalezeno

```
[PostReader] CSV file not found: data/posts-latest.csv
```

```bash
ls -la data/posts-latest.csv
# Pokud chybí symlink:
ln -s /app/data/zbnw/posts-latest.csv data/posts-latest.csv
```

### Problém: Málo postů (< 500)

Systém zpracovává **včerejší** datum. Pokud CSV nebylo aktualizováno v 06:00, bude obsahovat stará data.

```bash
# Ověř datum v CSV
awk -F',' 'NR==2 {print $2}' data/posts-latest.csv
```

### Problém: Claude API 401

```bash
echo $ANTHROPIC_API_KEY  # nesmí být prázdné
# Ověř klíč na https://console.anthropic.com/
```

### Problém: Mastodon 401/403

```bash
echo $ZPRAVOBOT_TOKEN  # nesmí být prázdné
# Ověř token přes Rails console nebo Mastodon API
```

### Problém: Všechny posty v tématu "Zprávy"

Kategorizace selhala. Ověř sync účtů:

```bash
wc -l cache/accounts_categories.yml
# Mělo by být ~510 účtů

ruby bin/sync_accounts.rb  # znovu sync
```

### Problém: Duplikátní publikování

Idempotence je zajištěna přes `.state/`. Pokud stav existuje pro dnešní datum, systém přeskočí publikování.

```bash
ls .state/
cat .state/last_thread.json

# Smazat state (pro manuální re-run)
rm .state/zpravobot_*.json
```

### Problém: Krátké tooty (málo obsahu)

Ověř `min_excerpt_length` v `config/global.yml` a `articles_per_toot` v `config/bots.yml`.

---

## 🔐 BEZPEČNOST

- `env.sh` je v `.gitignore` — nikdy ho necommituj
- Tokeny pouze v environment proměnných
- Přímé HTTP volání (net/http) — žádná třetí strana
- CSV read-only přístup
- Žádný přímý přístup do databáze

---

## 📝 CHANGELOG

**v2.0.0** (březen 2026)
- Kompletní refaktoring na modulární architekturu (9 lib tříd)
- Kategorizace účtů z mastodon_accounts.yml (510 účtů)
- Nový limit 2500 znaků (zpravobot.news instance)
- Thread s více extension tooty (1 summary + N extension)
- Automatický boost (@zpravobot boostuje slunkobot + hrubot)
- Excerpty místo titulků v extension tootech
- Všechna dostupná témata v summary tootu
- Per-bot log soubory s rotací
- Idempotence přes .state/

**v1.0.0** (leden 2026)
- Monolitický skript publish_digest.rb
- Tři boti (zpravobot, pozitivni, sarkasticky)
- 2-toot thread (summary + links)
