# 📦 ZPRÁVOBOT AI DIGEST
## Verze 2.0.0 — březen 2026

---

## 📋 OBSAH PROJEKTU

```
.
├── bin/
│   ├── publish_digest.rb      # Hlavní orchestrátor digestu
│   ├── boost_digest.rb        # Boost postů mezi boty
│   └── sync_accounts.rb       # Sync kategorií účtů
├── lib/
│   ├── logging.rb             # Centrální logging
│   ├── config_loader.rb       # Načítání YAML konfigurace
│   ├── account_categorizer.rb # Mapování účtů na témata
│   ├── post_reader.rb         # Čtení CSV exportu
│   ├── topic_extractor.rb     # Extrakce témat z postů
│   ├── article_selector.rb    # Výběr článků dle stylu bota
│   ├── claude_client.rb       # Integrace Claude API
│   ├── toot_builder.rb        # Sestavení tootů
│   └── mastodon_publisher.rb  # Publikování na Mastodon
├── config/
│   ├── global.yml             # Globální konfigurace
│   └── bots.yml               # Bot-specifické overrides
├── docs/
│   ├── deployment.md          # Kompletní průvodce nasazením
│   ├── quick_reference.md     # Denní admin cheat sheet
│   ├── instalation_checklist.md # Checklist pro instalaci
│   └── package_readme.md      # Tento soubor
├── env.sh.example             # Šablona pro env.sh
├── Gemfile                    # Ruby závislosti
├── run-digest.sh              # Hlavní entry point
└── README.md                  # Přehled projektu
```

---

## 🎯 CO TENTO SYSTÉM DĚLÁ

Denní AI digest pro zpravobot.news:

1. Načte tisíce postů z předchozího dne (CSV export)
2. Kategorizuje je podle zdrojových účtů (510 účtů)
3. Vybere reprezentativní články pro každé téma
4. Analyzuje pomocí Claude AI
5. Sestaví thread a publikuje na Mastodon
6. @zpravobot boostuje posty @slunkobot a @hrubot

### Boti

| Bot | Čas | Styl |
|-----|-----|------|
| @zpravobot | 07:00 | Neutrální přehled |
| @slunkobot | 12:00 | Pozitivní výběr |
| @hrubot | 19:00 | Sarkastický komentář |

---

## 🚀 RYCHLÝ START

```bash
# 1. Závislosti
bundle install

# 2. Prostředí
cp env.sh.example env.sh && nano env.sh

# 3. Sync účtů
ruby bin/sync_accounts.rb

# 4. Test
./run-digest.sh zpravobot --dry-run

# 5. Produkce
./run-digest.sh zpravobot
```

**Podrobný postup:** viz `docs/instalation_checklist.md`

---

## 📚 DOKUMENTACE

| Soubor | Popis | Pro koho |
|--------|-------|----------|
| `README.md` | Přehled projektu, architektura | Všichni |
| `docs/deployment.md` | Kompletní průvodce nasazením | DevOps |
| `docs/quick_reference.md` | Denní příkazy, troubleshooting | Admin |
| `docs/instalation_checklist.md` | Checklist pro novou instalaci | Instalátor |

---

## ✨ NOVINKY VE VERZI 2.0

Oproti v1.0 (monolitický skript):

- ✅ Modulární architektura (9 lib tříd + 3 bin skripty)
- ✅ Kategorizace 510 účtů z mastodon_accounts.yml
- ✅ Limit 2500 znaků (zpravobot.news instance)
- ✅ Thread s více extension tooty (bohatší obsah)
- ✅ Excerpty (perex) místo pouhých titulků
- ✅ Automatický boost (@zpravobot boostuje ostatní)
- ✅ Všechna dostupná témata v summary tootu
- ✅ Per-bot log soubory s automatickou rotací
- ✅ Idempotence — přeskočí duplikátní publikování
- ✅ Filtrování postů bez excerptů

---

## 💰 PROVOZNÍ NÁKLADY

- **Claude API:** ~$3–5/měsíc (3 požadavky/den)
- **Infrastruktura:** $0 (běží na stávajícím Mastodon serveru)

---

## 🔒 BEZPEČNOST

- Tokeny v `env.sh` (nikdy v gitu)
- Přímé HTTP volání Mastodon API
- Žádný přímý přístup do databáze (pouze CSV)
- Minimální oprávnění (read/write Mastodon)

---

**Verze:** 2.0.0 | **Aktualizováno:** březen 2026 | **Status:** Produkčně nasazeno ✅
