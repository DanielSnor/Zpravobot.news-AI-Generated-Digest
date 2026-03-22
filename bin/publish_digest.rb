#!/usr/bin/env ruby
# frozen_string_literal: true
#
# bin/publish_digest.rb
# Zprávobot.news - AI Daily Digest Publisher
# Version: 3.0.0
#
# Generuje a publikuje denní digest tootů pro Mastodon boty.
# Využívá kategorizace účtů z mastodon_accounts.yml (zbnw-ng).
#
# Použití:
#   ./bin/publish_digest.rb --bot=zpravobot [--dry-run] [--date=YYYY-MM-DD] [--visibility=public]
#   ./bin/publish_digest.rb --help
#

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'optparse'
require 'date'

require 'logging'
require 'config_loader'
require 'account_categorizer'
require 'post_reader'
require 'topic_extractor'
require 'article_selector'
require 'claude_client'
require 'toot_builder'
require 'mastodon_publisher'

# ===== LOCKFILE =====

LOCKFILE = File.expand_path('../tmp/publish_digest.lock', __dir__)

def acquire_lock
  require 'fileutils'
  FileUtils.mkdir_p(File.dirname(LOCKFILE))
  lock = File.open(LOCKFILE, File::RDWR | File::CREAT)
  lock.flock(File::LOCK_NB | File::LOCK_EX)
rescue Errno::EWOULDBLOCK, Errno::EACCES
  false
end

# ===== CLI =====

options = {
  bot:        nil,
  dry_run:    false,
  date:       nil,
  visibility: 'public'
}

OptionParser.new do |opts|
  opts.banner = "Použití: #{$PROGRAM_NAME} [options]"

  opts.on('--bot BOT', String, 'Jméno bota (zpravobot, slunkobot, hrubot)') do |b|
    # Backward compatibility aliasy
    options[:bot] = case b
                    when 'pozitivni'   then 'slunkobot'
                    when 'sarkasticky' then 'hrubot'
                    else b
                    end
  end

  opts.on('--dry-run', 'Testovací run — nepublikovat') do
    options[:dry_run] = true
  end

  opts.on('--date DATE', String, 'Datum pro zpracování (YYYY-MM-DD)') do |d|
    options[:date] = d
  end

  opts.on('--visibility VIS', String, 'Viditelnost tootu (public, unlisted, private)') do |v|
    options[:visibility] = v if %w[public unlisted private].include?(v)
  end

  opts.on('-h', '--help', 'Nápověda') do
    puts opts
    exit
  end
end.parse!

# ===== SETUP =====

ROOT_DIR = File.expand_path('..', __dir__)
ENV['TZ'] ||= 'Europe/Prague'

Logging.setup(
  name:      "digest_#{options[:bot] || 'unknown'}",
  dir:       File.join(ROOT_DIR, 'logs'),
  keep_days: 30
)

unless acquire_lock
  Logging.warn('Jiný digest proces právě běží (lockfile) — ukončuji')
  exit 0
end

# ===== MAIN =====

begin
  # 1. Načti konfiguraci
  config = ConfigLoader.new
  Logging.info("Model: #{config.claude['model']}, limit: #{config.mastodon['max_toot_length']} znaků")

  # 2. Ověř bota
  bot_name = options[:bot]
  unless bot_name && config.available_bots.include?(bot_name)
    Logging.error("Neplatný bot: #{bot_name.inspect}. Dostupné: #{config.available_bots.join(', ')}")
    exit 1
  end

  bot_config = config.bot_config(bot_name)
  Logging.info("Bot: #{bot_name} (#{bot_config['style']})")

  # 3. Načti kategorie účtů
  account_cat = AccountCategorizer.new(config)

  # 4. Načti posty z CSV
  reader = PostReader.new(config)
  all_posts = reader.load(date: options[:date])

  if all_posts.empty?
    Logging.warn("Žádné posty pro #{options[:date] || 'dnešní den'} — ukončuji")
    Logging.close
    exit 0
  end

  # 5. Filtruj podle jazyka
  lang_cfg  = config.language_config
  blocked   = lang_cfg['blocked'] || ['en']
  posts     = all_posts.reject { |p| blocked.include?(p[:language]) }
  Logging.info("Po filtraci jazyka: #{posts.size} postů (původně #{all_posts.size})")

  # 6. Extrahuj témata (s využitím kategorií účtů)
  extractor = TopicExtractor.new(config, account_cat)
  min_posts = bot_config.dig('topics', 'min_posts') || 8
  topics    = extractor.extract(posts, min_posts: min_posts)

  if topics.empty?
    Logging.warn("Žádná témata s dostatkem postů — ukončuji")
    Logging.close
    exit 0
  end

  # 7. Vyber články
  selector = ArticleSelector.new(config)
  selected = selector.select(topics, bot_config)

  if selected.empty?
    Logging.warn("ArticleSelector nevybral žádné články — ukončuji")
    Logging.close
    exit 0
  end

  # 8. Analyzuj s Claude (obohaceno o kategorie účtů)
  claude   = ClaudeClient.new(config)
  analysis = claude.analyze(posts, topics, bot_config['style'], account_cat)
  Logging.info("Claude analýza: sentiment=#{analysis[:sentiment]}, témata=#{analysis[:main_topics].join(', ')}")

  # 9. Generuj komentáře (pro sarkastický bot)
  commentaries = []
  if bot_config.dig('articles', 'add_commentary')
    Logging.info("Generuji sarkastické komentáře pro #{selected.size} článků...")
    commentaries = claude.commentary(selected)
  end

  # 10. Sestav tooty
  builder    = TootBuilder.new(config)
  target_date = options[:date] ? Date.parse(options[:date]) : Date.today - 1

  summary    = builder.summary_toot(topics, posts.size, analysis, bot_config, date: target_date)
  extensions = builder.extension_toots(selected, bot_config, commentaries: commentaries)

  Logging.info("Sestaveno: 1 summary + #{extensions.size} extension tootů")

  # 11. Publikuj nebo dry-run
  publisher = MastodonPublisher.new(config)

  if options[:dry_run]
    publisher.dry_run(bot_name, summary, extensions)
  else
    success = publisher.publish_thread(
      bot_name, summary, extensions,
      visibility: options[:visibility]
    )
    exit(success ? 0 : 1)
  end

rescue Interrupt
  Logging.warn('Přerušeno uživatelem')
  exit 130
rescue StandardError => e
  Logging.error("Kritická chyba: #{e.message}")
  Logging.error(e.backtrace.first(5).join("\n")) if e.backtrace
  exit 1
ensure
  Logging.close
  File.delete(LOCKFILE) if File.exist?(LOCKFILE)
end
