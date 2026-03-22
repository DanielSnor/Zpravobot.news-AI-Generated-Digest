#!/usr/bin/env ruby
# frozen_string_literal: true
#
# bin/boost_digest.rb
# Zprávobot.news - Boost digest summary toot
#
# Boostne (rebloguje) poslední summary toot jednoho bota jiným botem.
# Používá summary_id uložené v .state/ po publishování.
#
# Použití:
#   ./bin/boost_digest.rb --from=slunkobot --with=zpravobot
#   ./bin/boost_digest.rb --from=hrubot --with=zpravobot [--dry-run]
#

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'optparse'
require 'logging'
require 'config_loader'
require 'mastodon_publisher'

options = {
  from:    nil,
  with:    nil,
  dry_run: false
}

OptionParser.new do |opts|
  opts.banner = "Použití: #{$PROGRAM_NAME} --from=BOT --with=BOT [--dry-run]"

  opts.on('--from BOT', String, 'Bot jehož summary boostujeme') do |b|
    options[:from] = b
  end

  opts.on('--with BOT', String, 'Bot který boostuje') do |b|
    options[:with] = b
  end

  opts.on('--dry-run', 'Testovací run — neposílat') do
    options[:dry_run] = true
  end

  opts.on('-h', '--help', 'Nápověda') do
    puts opts
    exit
  end
end.parse!

ROOT_DIR = File.expand_path('..', __dir__)
ENV['TZ'] ||= 'Europe/Prague'

Logging.setup(
  name:      "boost_#{options[:from]}_#{options[:with]}",
  dir:       File.join(ROOT_DIR, 'logs'),
  keep_days: 14
)

unless options[:from] && options[:with]
  Logging.error("Chybí --from nebo --with argument")
  exit 1
end

begin
  config    = ConfigLoader.new
  publisher = MastodonPublisher.new(config)

  if options[:dry_run]
    summary_id = publisher.last_summary_id(options[:from])
    if summary_id
      Logging.info("[DRY-RUN] Boostnul bych #{options[:from]} summary (#{summary_id}) jako #{options[:with]}")
    else
      Logging.warn("[DRY-RUN] summary_id pro #{options[:from]} nenalezeno v state — bot ještě nepublikoval dnes?")
    end
    exit 0
  end

  success = publisher.boost_last(options[:from], options[:with])
  exit(success ? 0 : 1)

rescue Interrupt
  Logging.warn('Přerušeno uživatelem')
  exit 130
rescue StandardError => e
  Logging.error("Kritická chyba: #{e.message}")
  Logging.error(e.backtrace.first(3).join("\n")) if e.backtrace
  exit 1
ensure
  Logging.close
end
