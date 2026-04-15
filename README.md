# 🤖 Zprávobot.news - AI Daily Digest

Automatizovaný systém denního digestu pro Mastodon boty zpravobot.news — využívá Claude AI pro analýzu a generování obsahu.

## 🎯 Přehled

Každý den systém zpracuje tisíce postů z předchozího dne, kategorizuje je podle zdrojů a témat a sestaví přehledný thread na Mastodonu.

### Boti

| Bot | Čas | Styl | Popis |
|-----|-----|------|-------|
| @zpravobot | 07:00 | Neutrální | Ranní přehled zpráv |
| @slunkobot | 12:00 | Pozitivní | Polední pozitivní výběr |
| @hrubot | 19:00 | Sarkastický | Večerní komentář reality |

@zpravobot automaticky boostuje posty @slunkobot a @hrubot.

### Denní timeline

```
05:30 - sync_accounts.rb (kategorie účtů z mastodon_accounts.yml)
06:00 - CSV export (posty z předchozího dne)
07:00 - @zpravobot publikuje
12:00 - @slunkobot publikuje, @zpravobot boostuje
19:00 - @hrubot publikuje, @zpravobot boostuje
```

## 📁 Struktura projektu

```
.
├── bin/
│   ├── publish_digest.rb      # Hlavní orchestrátor
│   ├── boost_digest.rb        # Boost cizích postů
│   └── sync_accounts.rb       # Denní sync kategorií účtů
├── lib/
│   ├── logging.rb             # Centrální logging s rotací
│   ├── config_loader.rb       # Načítání YAML konfigurace
│   ├── account_categorizer.rb # Username → témata digestu
│   ├── post_reader.rb         # Čtení a filtrování CSV
│   ├── topic_extractor.rb     # Extrakce témat z postů
│   ├── article_selector.rb    # Výběr článků dle stylu bota
│   ├── claude_client.rb       # Claude API integrace
│   ├── toot_builder.rb        # Sestavení tootů (summary + extension)
│   └── mastodon_publisher.rb  # Publikování + idempotence
├── config/
│   ├── global.yml             # Globální konfigurace
│   └── bots.yml               # Bot-specifické overrides
├── cache/
│   └── accounts_categories.yml # Lokální cache kategorií (510 účtů)
├── data/
│   └── posts-latest.csv       # CSV export z předchozího dne
├── logs/                      # Per-bot logy (rotace 7 dní)
├── .state/                    # Idempotence (ID posledního threadu)
├── env.sh                     # Environment proměnné (v .gitignore)
├── env.sh.example             # Šablona pro env.sh
├── Gemfile                    # Ruby závislosti
└── run-digest.sh              # Entry point
```

## 🚀 Rychlý start

### 1. Nainstaluj závislosti

```bash
bundle install
```

### 2. Nastavení prostředí

```bash
cp env.sh.example env.sh
# Vyplň tokeny v env.sh
source env.sh
```

### 3. Sync účtů

```bash
ruby bin/sync_accounts.rb
```

### 4. Test (dry-run)

```bash
./run-digest.sh zpravobot --dry-run
./run-digest.sh slunkobot --dry-run
./run-digest.sh hrubot --dry-run
```

### 5. Produkce

```bash
./run-digest.sh zpravobot
```

## 🔧 Použití

```bash
# Dry run (bez publikování)
./run-digest.sh zpravobot --dry-run

# Publikovat
./run-digest.sh zpravobot

# Sync kategorií účtů
ruby bin/sync_accounts.rb

# Boost (volá run-digest.sh automaticky)
ruby bin/boost_digest.rb --from=slunkobot --with=zpravobot
```

## ⚙️ Konfigurace

Konfigurace je hierarchická — `config/global.yml` definuje výchozí hodnoty, `config/bots.yml` je přepisuje per-bot.

Klíčové parametry v `config/global.yml`:
- `mastodon.max_chars` — limit znaků (2500 pro zpravobot.news)
- `digest.articles_per_toot` — počet článků na extension toot
- `digest.min_excerpt_length` — minimální délka excerptů
- `category_map` — mapování kategorií na témata digestu

## 📊 Monitoring

```bash
# Živý log
tail -f logs/zpravobot_$(date +%Y%m%d)*.log

# Dnešní běhy
ls -la logs/*$(date +%Y%m%d)*.log

# Chyby
grep "ERROR\|❌" logs/zpravobot_$(date +%Y%m%d)*.log
```

## 🔒 Bezpečnost

- Tokeny v `env.sh` (v `.gitignore`, nikdy do gitu)
- CSV přístup read-only
- Přímé HTTP volání Mastodon API (bez třetích stran)
- Stav idempotence v `.state/` (přeskočí duplikáty)

## 🛠 Tech stack

- **Ruby 2.6** (systémový Ruby Mastodonu)
- **Claude API** (claude-sonnet-4-6)
- **Mastodon API** (přímé HTTP, net/http)
- **YAML** konfigurace, **CSV** vstup

## 📝 Licence

Open source — vytvořeno pro komunitu Zprávobot.news.

---

**Verze:** 2.0.0
**Aktualizováno:** březen 2026
