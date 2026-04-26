# frozen_string_literal: true
#
# ConfigLoader - načítání a mergování konfigurací
# Hierarchie: global.yml ← bots.yml (bot-specific override)
#

require 'yaml'

class ConfigLoader
  include Loggable

  GLOBAL_CONFIG_PATH = File.expand_path('../../config/global.yml', __FILE__)
  BOTS_CONFIG_PATH   = File.expand_path('../../config/bots.yml', __FILE__)

  def initialize
    @global = load_yaml(GLOBAL_CONFIG_PATH, required: true)
    @bots   = load_yaml(BOTS_CONFIG_PATH,   required: true)
    validate!
  end

  # Vrátí kompletní konfiguraci pro daného bota (global + bot override)
  def bot_config(bot_name)
    bot = @bots[bot_name.to_s]
    raise ArgumentError, "Neznámý bot: #{bot_name}. Dostupné: #{available_bots.join(', ')}" unless bot

    deep_merge(@global, bot)
  end

  def available_bots
    @bots.keys
  end

  def global
    @global
  end

  # Zkratky pro časté přístupy
  def mastodon
    @global.fetch('mastodon')
  end

  def claude
    @global.fetch('claude')
  end

  def category_map
    @global.fetch('category_map', {})
  end

  def topic_priority
    @global.fetch('topic_priority', {})
  end

  def url_config
    @global.fetch('url', {})
  end

  def language_config
    @global.fetch('language', {})
  end

  def formatting
    @global.fetch('formatting', {})
  end

  def bluesky
    @global.fetch('bluesky', {})
  end

  def bluesky_enabled?
    bluesky.fetch('enabled', false)
  end

  def accounts_source_path
    raw = @global.dig('accounts_source', 'path') || '~/zbnw-ng/config/mastodon_accounts.yml'
    File.expand_path(raw)
  end

  def accounts_cache_path
    raw = @global.dig('accounts_cache', 'path') || 'cache/accounts_categories.yml'
    File.expand_path(raw, File.dirname(GLOBAL_CONFIG_PATH) + '/..')
  end

  private

  def load_yaml(path, required: false)
    unless File.exist?(path)
      raise "Chybí povinný config soubor: #{path}" if required

      return {}
    end

    YAML.safe_load(File.read(path)) || {}
  rescue Psych::SyntaxError => e
    raise "Chyba parsování YAML #{path}: #{e.message}"
  end

  def validate!
    %w[mastodon claude category_map].each do |key|
      raise "Chybí povinný klíč '#{key}' v global.yml" unless @global.key?(key)
    end

    raise 'Žádní boti nenalezeni v bots.yml' if @bots.empty?

    instance = @global.dig('mastodon', 'instance').to_s
    raise 'mastodon.instance je prázdné v global.yml' if instance.empty?
  end

  # Hluboké mergování dvou hashů — hodnoty z `override` přepisují `base`
  # Hash hodnoty se rekurzivně mergují, ostatní typy se přepisují.
  def deep_merge(base, override)
    result = base.dup

    override.each do |key, val|
      if result[key].is_a?(Hash) && val.is_a?(Hash)
        result[key] = deep_merge(result[key], val)
      else
        result[key] = val
      end
    end

    result
  end
end
