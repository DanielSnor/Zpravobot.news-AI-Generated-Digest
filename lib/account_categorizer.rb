# frozen_string_literal: true
#
# AccountCategorizer - mapuje account_id na digest témata
# pomocí cache vygenerované bin/sync_accounts.rb
#

require 'yaml'

class AccountCategorizer
  include Loggable

  def initialize(config_loader)
    @category_map = config_loader.category_map  # raw category → téma
    @cache = load_cache(config_loader.accounts_cache_path)

    log_info("Načteno #{@cache.size} účtů z cache")
  end

  # Vrátí pole digest témat pro daný account_id
  # Příklad: "antosovabritva" → ["Sport"]
  #          "aktualnecz"    → ["Zprávy", "Politika"]
  def topics_for(account_id)
    raw_cats = @cache[account_id.to_s]
    return [] unless raw_cats.is_a?(Array)

    raw_cats.map { |cat| @category_map[cat.to_s] }.compact.uniq
  end

  # Vrátí primární téma (první mapované) nebo nil
  def primary_topic_for(account_id)
    topics_for(account_id).first
  end

  # Vrátí true pokud má účet v kategoriích danou raw kategorii
  def has_category?(account_id, category)
    raw_cats = @cache[account_id.to_s]
    return false unless raw_cats.is_a?(Array)

    raw_cats.include?(category.to_s)
  end

  # Vrátí raw kategorie účtu (pro debug/logging)
  def raw_categories_for(account_id)
    @cache[account_id.to_s] || []
  end

  # Je účet agregátor? (nemá specifické kategorie, nebo jen obecné)
  # Pozn.: tato informace není v cache (záměrně) — vrací vždy false
  def aggregator?(_account_id)
    false
  end

  private

  def load_cache(cache_path)
    unless File.exist?(cache_path)
      log_warn("Cache soubor nenalezen: #{cache_path}")
      log_warn("Spusť bin/sync_accounts.rb pro vytvoření cache")
      return {}
    end

    data = YAML.safe_load(File.read(cache_path)) || {}
    unless data.is_a?(Hash)
      log_warn("Cache má neočekávaný formát, ignoruji")
      return {}
    end

    data
  rescue StandardError => e
    log_warn("Chyba načítání cache: #{e.message}")
    {}
  end
end
