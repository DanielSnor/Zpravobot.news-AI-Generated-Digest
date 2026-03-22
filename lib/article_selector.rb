# frozen_string_literal: true
#
# ArticleSelector - výběr článků z témat dle stylu bota
#
# Styly:
#   neutral    - diverzifikovaný výběr, jazyková rovnováha CZ:SK
#   positive   - filtruje negativní obsah, preferuje pozitivní klíčová slova
#   sarcastic  - preferuje kontroverzní obsah, bodové skórování
#
# Vrátí pole vybraných postů (max total_articles)
#

require 'yaml'
require 'uri'

class ArticleSelector
  include Loggable

  def initialize(config_loader)
    @url_config   = config_loader.url_config
    @lang_ratio   = config_loader.language_config.dig('preferred_ratio') || { 'cs' => 3, 'sk' => 1 }
    @domain_whitelist = load_domain_whitelist(config_loader)
    @negative_keywords = load_negative_keywords(config_loader)
  end

  # Vybere články z témat dle konfigurace bota
  # topics: { "Sport" => [posts], ... }  (seřazeno dle priority)
  # bot_config: merged konfigurace bota
  # Vrátí pole { topic:, post: } hashů
  def select(topics, bot_config)
    style         = bot_config['style']
    total         = bot_config.dig('threads', 'total_articles') || 12
    max_per_source = bot_config.dig('articles', 'max_per_source') || 2
    excluded       = bot_config.dig('topics', 'excluded') || []

    # Filtruj vyloučená témata
    available = topics.reject { |topic, _| excluded.include?(topic) }

    # Aplikuj styl-specifické filtry
    available = apply_style_filter(available, style, bot_config)

    # Vyber články ze zbývajících témat
    selected = pick_articles(available, total, max_per_source, style, bot_config)

    log_info("Vybráno #{selected.size} článků ze #{available.size} témat (styl: #{style})")
    selected
  end

  private

  # Filtruje unsafe URL (bez whitelistu), vrátí pouze validní posty
  def filter_unsafe(posts)
    posts.select { |p| safe_url?(p[:url]) }
  end

  def apply_style_filter(topics, style, bot_config)
    case style
    when 'positive'
      filter_positive(topics, bot_config)
    when 'sarcastic'
      reorder_sarcastic(topics, bot_config)
    else
      topics
    end
  end

  def filter_positive(topics, bot_config)
    pos_keywords = bot_config.dig('selection', 'positive_keywords') || []
    neg_keywords = bot_config.dig('selection', 'negative_keywords') || @negative_keywords

    result = {}
    topics.each do |topic, posts|
      filtered = posts.select do |p|
        text = p[:text].downcase
        # Musí mít alespoň jeden pozitivní signál, nebo nesmí mít negativní
        has_positive = pos_keywords.any? { |kw| text.include?(kw) }
        has_negative = neg_keywords.any? { |kw| text.include?(kw) }
        has_positive && !has_negative
      end
      result[topic] = filtered unless filtered.empty?
    end
    result
  end

  def reorder_sarcastic(topics, bot_config)
    preferred    = bot_config.dig('topics', 'preferred') || []
    contro_kws   = bot_config.dig('selection', 'controversial_keywords') || []

    # Bodové skórování: preferovaná témata + kontroverzní klíčová slova v textu
    topics.sort_by do |topic, posts|
      score = preferred.include?(topic) ? 100 : 0
      # Průměrný počet kontroverzních slov ve vzorku postů
      sample = posts.first(10)
      contro_score = sample.sum do |p|
        contro_kws.count { |kw| p[:text].downcase.include?(kw) }
      end
      -(score + contro_score)
    end.to_h
  end

  # Hlavní výběr článků — z každého tématu bere diverzifikovaný vzorek
  # s vyvážením CZ:SK jazyků
  def pick_articles(topics, total, max_per_source, style, bot_config)
    selected = []
    source_counts = Hash.new(0)

    topics.each do |topic, posts|
      break if selected.size >= total

      # Filtruj unsafe URL
      safe_posts = filter_unsafe(posts)
      next if safe_posts.empty?

      # Vyvažuj jazyky UVNITŘ tématu
      topic_posts = balance_languages(safe_posts)

      # Ber max 3 z každého tématu (nedominantní jedno téma)
      topic_posts = topic_posts.first(3)

      topic_posts.each do |post|
        break if selected.size >= total

        # Přeskoč posty bez excerptů (uživatel neví proč klikat)
        next if post[:excerpt].to_s.strip.length < 30

        # Limit na zdroj
        source = extract_source(post[:url])
        next if source_counts[source] >= max_per_source

        selected << { topic: topic, post: post }
        source_counts[source] += 1
      end
    end

    selected
  end

  # Vybere diverzifikovaný vzorek s CZ:SK poměrem
  def balance_languages(posts)
    cs_posts = posts.select { |p| p[:language] == 'cs' }
    sk_posts = posts.select { |p| p[:language] == 'sk' }

    cs_ratio = @lang_ratio['cs'] || 3
    sk_ratio = @lang_ratio['sk'] || 1
    total_ratio = cs_ratio + sk_ratio

    result = []

    # Vezmi diverzifikovaný vzorek z každého jazyka
    [first_middle_last(cs_posts), first_middle_last(sk_posts)].each do |lang_posts|
      result.concat(lang_posts)
    end

    # Pokud nemáme SK, doplň dalšími CZ
    result.concat(cs_posts) if result.empty? && !cs_posts.empty?

    result.uniq { |p| p[:id] }
  end

  # Vezme první, prostřední a poslední prvek — diverzita časového rozložení
  def first_middle_last(arr)
    return [] if arr.empty?
    return [arr.first] if arr.size == 1
    return [arr.first, arr.last] if arr.size == 2

    [arr.first, arr[arr.size / 2], arr.last]
  end

  def extract_source(url)
    return 'unknown' if url.to_s.empty?

    URI.parse(url).host.to_s.downcase.sub(/^www\./, '')
  rescue URI::InvalidURIError
    'unknown'
  end

  # ===== URL WHITELIST =====

  def safe_url?(url)
    return false if url.to_s.empty?

    begin
      uri = URI.parse(url)
    rescue URI::InvalidURIError
      return false
    end

    scheme = uri.scheme.to_s.downcase
    host   = uri.host.to_s.downcase

    return false unless @domain_whitelist[:schemes].include?(scheme)
    return true  if @domain_whitelist[:twitter].any?  { |d| host == d || host.end_with?(".#{d}") }
    return true  if @domain_whitelist[:social].any?   { |d| host == d || host.end_with?(".#{d}") }
    return true  if @domain_whitelist[:special].any?  { |d| host == d || host.end_with?(".#{d}") }
    return true  if @domain_whitelist[:shorteners].any? { |d| host == d || host.end_with?(".#{d}") }

    # Povolené TLD
    @domain_whitelist[:tlds].any? { |tld| host.end_with?(".#{tld}") }
  end

  def load_domain_whitelist(config_loader)
    url = config_loader.url_config
    {
      schemes:    url['allowed_schemes']  || %w[https http],
      tlds:       url['allowed_tlds']     || %w[cz sk eu app],
      twitter:    url['twitter_domains']  || [],
      social:     url['social_domains']   || [],
      special:    url['special_domains']  || [],
      shorteners: url['url_shorteners']   || []
    }
  end

  def load_negative_keywords(config_loader)
    path = File.expand_path('../../config/negative_keywords.txt',
      File.dirname(config_loader.accounts_cache_path))

    return [] unless File.exist?(path)

    File.readlines(path, encoding: 'UTF-8')
        .map(&:strip)
        .reject { |l| l.empty? || l.start_with?('#') }
  rescue StandardError
    []
  end
end
