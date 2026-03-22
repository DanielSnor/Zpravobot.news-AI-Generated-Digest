# ✅ INSTALAČNÍ CHECKLIST
## Zprávobot AI Digest v2.0 — Postup nasazení

**Odhadovaný čas:** 30–45 minut

---

## 📋 PŘED INSTALACÍ

- [ ] Mastodon instance běží (zpravobot.news) ✅
- [ ] CSV export nakonfigurován (běží v 06:00) ✅
- [ ] Bot účty existují:
  - [ ] @zpravobot
  - [ ] @slunkobot
  - [ ] @hrubot
- [ ] Anthropic API účet vytvořen (https://console.anthropic.com/)
- [ ] Přístup k zbnw-ng repozitáři (pro sync účtů)

---

## 📦 KROK 1: ZÁVISLOSTI

### 1.1 Nainstaluj gems
```bash
cd /app/data/zbnw-ai-digest
bundle install
```

### 1.2 Ověř Ruby verzi
```bash
ruby --version
# Potřeba 2.6+
```

- [ ] Bundle install proběhl úspěšně

---

## 📁 KROK 2: ADRESÁŘOVÁ STRUKTURA

### 2.1 Vytvoř potřebné adresáře
```bash
mkdir -p data logs cache .state
```

### 2.2 Ověř strukturu
```bash
ls -la
# Musí existovat: bin/ lib/ config/ data/ logs/ cache/ .state/
```

- [ ] Adresáře vytvořeny

---

## 🔑 KROK 3: MASTODON TOKENY

### 3.1 Vstup do Rails konzole
```bash
cd /home/mastodon/live
RAILS_ENV=production bundle exec rails console
```

### 3.2 Generuj token pro @zpravobot
```ruby
bot_username = 'zpravobot'
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

- [ ] @zpravobot token: `________________________________`

### 3.3 Opakuj pro @slunkobot
Změň `bot_username = 'slunkobot'`

- [ ] @slunkobot token: `________________________________`

### 3.4 Opakuj pro @hrubot
Změň `bot_username = 'hrubot'`

- [ ] @hrubot token: `________________________________`

### 3.5 Odejdi z konzole
```ruby
exit
```

---

## 🌐 KROK 4: PROSTŘEDÍ

### 4.1 Vytvoř env.sh
```bash
cp env.sh.example env.sh
nano env.sh
```

### 4.2 Vyplň proměnné
```bash
export ZPRAVOBOT_TOKEN="..."
export SLUNKOBOT_TOKEN="..."
export HRUBOT_TOKEN="..."
export ANTHROPIC_API_KEY="sk-ant-..."
export TZ="Europe/Prague"
```

### 4.3 Načti prostředí a ověř
```bash
source env.sh
echo $ZPRAVOBOT_TOKEN   # nesmí být prázdné
echo $SLUNKOBOT_TOKEN   # nesmí být prázdné
echo $HRUBOT_TOKEN      # nesmí být prázdné
echo $ANTHROPIC_API_KEY # nesmí být prázdné
```

- [ ] Všechny proměnné nastaveny

---

## 📊 KROK 5: CSV DATA

### 5.1 Propoj CSV export
```bash
ln -s /app/data/zbnw/posts-latest.csv data/posts-latest.csv
# nebo uprav cestu v env.sh: export CSV_PATH="..."
```

### 5.2 Ověř CSV
```bash
ls -lh data/posts-latest.csv
wc -l data/posts-latest.csv
# Mělo by být >2000 řádků
```

- [ ] CSV dostupné a neprázdné

---

## 🔄 KROK 6: SYNC ÚČTŮ

### 6.1 Spusť sync
```bash
ruby bin/sync_accounts.rb
```

### 6.2 Ověř cache
```bash
wc -l cache/accounts_categories.yml
# Očekáváno: ~510 účtů
```

- [ ] Sync proběhl úspěšně (~510 účtů)

---

## 🧪 KROK 7: TESTOVÁNÍ (DRY RUN)

### 7.1 Test zpravobot
```bash
./run-digest.sh zpravobot --dry-run
```

Očekávaný výstup: Summary toot + extension tooty, žádné chyby.

- [ ] @zpravobot dry run OK

### 7.2 Test slunkobot
```bash
./run-digest.sh slunkobot --dry-run
```

- [ ] @slunkobot dry run OK

### 7.3 Test hrubot
```bash
./run-digest.sh hrubot --dry-run
```

- [ ] @hrubot dry run OK

---

## 🚀 KROK 8: PRVNÍ LIVE TEST

**VAROVÁNÍ:** Toto publikuje na Mastodon!

### 8.1 Publikuj zpravobot
```bash
./run-digest.sh zpravobot
```

### 8.2 Ověř na Mastodonu
- Jdi na https://zpravobot.news/@zpravobot
- Zkontroluj, že thread vypadá správně
- Ověř, že odkazy fungují

- [ ] Live test úspěšný
- [ ] Thread vypadá správně

---

## ⏰ KROK 9: CRONTAB

### 9.1 Edituj crontab
```bash
crontab -e
```

### 9.2 Přidej úlohy
```bash
# Zprávobot AI Digest
30 5 * * * /app/data/zbnw-ai-digest/run-digest.sh sync >> /app/data/zbnw-ai-digest/logs/cron.log 2>&1
0 7 * * * /app/data/zbnw-ai-digest/run-digest.sh zpravobot >> /app/data/zbnw-ai-digest/logs/cron.log 2>&1
0 12 * * * /app/data/zbnw-ai-digest/run-digest.sh slunkobot >> /app/data/zbnw-ai-digest/logs/cron.log 2>&1
0 19 * * * /app/data/zbnw-ai-digest/run-digest.sh hrubot >> /app/data/zbnw-ai-digest/logs/cron.log 2>&1
```

### 9.3 Ověř crontab
```bash
crontab -l | grep digest
# Musí zobrazit 4 řádky
```

- [ ] Cron úlohy přidány
- [ ] Ověření úspěšné

---

## 📊 KROK 10: PRVNÍ DEN MONITORINGU

### Ráno (po 07:00)
```bash
ls -la logs/*$(date +%Y%m%d)*
tail -n 50 logs/zpravobot_$(date +%Y%m%d)*.log
```
- [ ] @zpravobot automaticky publikoval

### Poledne (po 12:00)
- [ ] @slunkobot automaticky publikoval
- [ ] @zpravobot boostoval @slunkobot

### Večer (po 19:00)
- [ ] @hrubot automaticky publikoval
- [ ] @zpravobot boostoval @hrubot

---

## ✅ POST-DEPLOYMENT CHECKLIST

- [ ] CSV export běží v 06:00 ✅
- [ ] Sync účtů běží v 05:30
- [ ] Všechny 3 tokeny nakonfigurovány
- [ ] Anthropic API klíč nakonfigurován
- [ ] Cron úlohy nastaveny (05:30, 07:00, 12:00, 19:00)
- [ ] Dry run úspěšný pro všechny boty
- [ ] První live publikování úspěšné
- [ ] Logy se zapisují správně
- [ ] Žádné chyby v lozích
- [ ] Všichni 3 boti publikují první den

---

**Datum instalace:** ______________________
**Poznámky:**

_______________________________________________

_______________________________________________
