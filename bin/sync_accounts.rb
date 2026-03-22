#!/usr/bin/env ruby
# frozen_string_literal: true
#
# bin/sync_accounts.rb
# Denní synchronizace kategorií Mastodon účtů z zbnw-ng projektu.
#
# Čte: zbnw-ng/config/mastodon_accounts.yml (cesta z global.yml → accounts_source.path)
# Zapíše: cache/accounts_categories.yml (pouze account_id + categories, BEZ tokenů)
#
# Spouštět: cron 06:15 každý den (před ranním digestem)
# Použití:  ./bin/sync_accounts.rb [--dry-run] [--verbose]
#

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'yaml'
require 'fileutils'
require 'optparse'
require 'time'
require 'logging'

# ===== CLI =====

options = { dry_run: false, verbose: false }

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.on('--dry-run', 'Nevytvářet cache soubor, jen zobrazit co by se stalo') { options[:dry_run] = true }
  opts.on('--verbose', 'Podrobný výpis')                                         { options[:verbose] = true }
  opts.on('-h', '--help', 'Nápověda') { puts opts; exit }
end.parse!

# ===== SETUP =====

ROOT_DIR = File.expand_path('..', __dir__)

Logging.setup(name: 'sync_accounts', dir: File.join(ROOT_DIR, 'logs'), keep_days: 14)

# ===== NAČTENÍ KONFIGURACE =====

global_config_path = File.join(ROOT_DIR, 'config', 'global.yml')

unless File.exist?(global_config_path)
  Logging.error("Chybí config/global.yml: #{global_config_path}")
  exit 1
end

global_config = YAML.safe_load(File.read(global_config_path)) || {}

source_path = File.expand_path(global_config.dig('accounts_source', 'path') || '~/zbnw-ng/config/mastodon_accounts.yml')
cache_path  = File.expand_path(
  global_config.dig('accounts_cache', 'path') || 'cache/accounts_categories.yml',
  ROOT_DIR
)

Logging.info("Zdroj:  #{source_path}")
Logging.info("Cache:  #{cache_path}")

# ===== NAČTENÍ ZDROJOVÉHO SOUBORU =====

unless File.exist?(source_path)
  Logging.error("Zdrojový soubor nenalezen: #{source_path}")
  Logging.error("Zkontroluj accounts_source.path v config/global.yml")
  exit 1
end

raw = YAML.safe_load(File.read(source_path)) || {}

unless raw.is_a?(Hash)
  Logging.error("Zdrojový soubor má neočekávaný formát (očekávaný Hash)")
  exit 1
end

# ===== EXTRAKCE POUZE KATEGORIÍ (bez tokenů) =====

categories_map = {}
skipped_no_categories = 0
skipped_test = 0

raw.each do |account_id, account_data|
  next unless account_data.is_a?(Hash)

  cats = account_data['categories']

  # Přeskočit účty bez kategorií
  unless cats.is_a?(Array) && !cats.empty?
    skipped_no_categories += 1
    Logging.debug("Přeskočen (bez kategorií): #{account_id}") if options[:verbose]
    next
  end

  # Přeskočit testovací účty (kategorie [test])
  if cats == ['test']
    skipped_test += 1
    Logging.debug("Přeskočen (testovací): #{account_id}") if options[:verbose]
    next
  end

  categories_map[account_id.to_s] = cats
  Logging.debug("#{account_id}: #{cats.join(', ')}") if options[:verbose]
end

Logging.info("Načteno účtů celkem: #{raw.size}")
Logging.info("Účtů s kategoriemi:  #{categories_map.size}")
Logging.info("Bez kategorií:       #{skipped_no_categories}")
Logging.info("Testovacích:         #{skipped_test}")

# ===== ULOŽENÍ CACHE =====

if options[:dry_run]
  Logging.info("DRY-RUN: cache soubor by byl zapsán do #{cache_path}")
  Logging.info("DRY-RUN: první 5 záznamů:")
  categories_map.first(5).each { |id, cats| Logging.info("  #{id}: #{cats.join(', ')}") }
else
  FileUtils.mkdir_p(File.dirname(cache_path))

  # Záhlaví s metadaty
  header = <<~YAML
    # ============================================================
    # Zprávobot Digest - Cache kategorií účtů
    # ============================================================
    # TENTO SOUBOR JE GENEROVÁN AUTOMATICKY - neupravovat ručně!
    # Generováno: #{Time.now.strftime('%Y-%m-%d %H:%M:%S %Z')}
    # Zdroj: #{source_path}
    # Účtů: #{categories_map.size}
    # ============================================================

  YAML

  File.write(cache_path, header + YAML.dump(categories_map))
  Logging.success("Cache zapsána: #{cache_path} (#{categories_map.size} účtů)")
end

Logging.close
