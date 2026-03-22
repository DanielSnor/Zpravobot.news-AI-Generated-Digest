# frozen_string_literal: true
#
# PostReader - čtení CSV postů, filtrování podle data, detekce jazyka
# Vstup:  CSV soubor (sloupce: id, created_at, text, uri, url, account_id)
# Výstup: pole hashů s klíči: id, created_at, text, uri, url, account_id, language, excerpt
#

require 'csv'
require 'time'
require 'uri'

class PostReader
  include Loggable

  # Minimální délka textu pro zpracování
  MIN_TEXT_LENGTH = 20

  def initialize(config_loader)
    @lang_config  = config_loader.language_config
    @url_config   = config_loader.url_config
    @formatting   = config_loader.formatting
    @csv_path     = resolve_csv_path(config_loader)
  end

  # Načte posty z CSV pro daný den (nebo pro dnešek pokud date=nil)
  # Vrátí pole post hashů s detekovaným jazykem a excerptomem
  def load(date: nil)
    target_date = parse_date(date)
    log_info("Načítám posty pro #{target_date.strftime('%Y-%m-%d')} z #{@csv_path}")

    unless File.exist?(@csv_path)
      log_error("CSV soubor nenalezen: #{@csv_path}")
      return []
    end

    posts = []

    CSV.foreach(@csv_path, headers: true, encoding: 'UTF-8') do |row|
      post = parse_row(row)
      next unless post
      next unless matches_date?(post[:created_at], target_date)

      posts << post
    end

    log_info("Načteno #{posts.size} postů pro #{target_date.strftime('%Y-%m-%d')}")
    posts
  rescue CSV::MalformedCSVError => e
    log_error("Chyba parsování CSV: #{e.message}")
    []
  end

  private

  def resolve_csv_path(config_loader)
    ENV['CSV_PATH'] ||
      config_loader.global.dig('defaults', 'csv_path') ||
      File.expand_path('../../data/posts-latest.csv', __FILE__)
  end

  def parse_date(date_str)
    return Time.now - 86_400 if date_str.nil?  # výchozí = včera

    Time.parse(date_str.to_s)
  rescue ArgumentError
    log_warn("Neplatné datum '#{date_str}', použiji včerejší datum")
    Time.now - 86_400
  end

  def matches_date?(created_at, target_date)
    return false unless created_at

    created_at.to_date == target_date.to_date
  rescue StandardError
    false
  end

  def parse_row(row)
    text       = row['text'].to_s.strip
    account_id = row['account_id'].to_s.strip
    uri        = row['uri'].to_s.strip
    username   = extract_username(uri)
    url        = extract_article_url(text)  # article URL z textu, ne Mastodon URL
    created_at = parse_time(row['created_at'])

    return nil if text.length < MIN_TEXT_LENGTH
    return nil if account_id.empty?

    {
      id:         row['id'].to_s.strip,
      created_at: created_at,
      text:       text,
      uri:        uri,
      url:        url,
      account_id: username.empty? ? account_id : username,  # preferuj username
      language:   detect_language(text, url),
      excerpt:    extract_excerpt(text)
    }
  rescue StandardError
    nil
  end

  def parse_time(str)
    Time.parse(str.to_s)
  rescue ArgumentError
    nil
  end

  # Extrahuje username z Mastodon ActivityPub URI
  # Formát: https://instance/users/{username}/statuses/{id}
  def extract_username(uri)
    match = uri.match(%r{/users/([^/]+)/statuses/})
    match ? match[1].downcase : ''
  end

  # Extrahuje article URL z textu postu (ne Mastodon URL)
  # Mastodon: URLs jsou přímo v textu postu jako hyperlinky
  def extract_article_url(text)
    urls = text.scan(%r{https?://[^\s"'<>\]]+})
    urls.each do |url|
      next if url.include?('zpravobot.news')  # přeskoč vlastní instanci
      return url.chomp('.,;)')
    end
    ''
  end

  # Detekuje jazyk postu (cs/sk/en) na základě textu a URL
  def detect_language(text, url)
    # Priorita 1: URL doména
    lang = language_from_url(url)
    return lang if lang

    # Priorita 2: Analýza textu
    language_from_text(text)
  end

  def language_from_url(url)
    return nil if url.to_s.empty?

    uri = URI.parse(url)
    host = uri.host.to_s.downcase
    return 'cs' if host.end_with?('.cz')
    return 'sk' if host.end_with?('.sk')

    nil
  rescue URI::InvalidURIError
    nil
  end

  def language_from_text(text)
    words = text.downcase.split(/\s+/)
    return 'cs' if words.empty?

    czech_words   = @lang_config['czech_words']   || []
    slovak_words  = @lang_config['slovak_words']  || []
    english_words = @lang_config['english_words'] || []

    czech_score   = (words & czech_words).size
    slovak_score  = (words & slovak_words).size
    english_score = (words & english_words).size

    # SK identifikátory — slova única pro slovenštinu
    sk_unique = %w[sa nie ktorý ktorá ktoré alebo keď len ďalší]
    sk_unique_score = (words & sk_unique).size

    return 'en' if english_score >= 3 && english_score > czech_score && english_score > slovak_score
    return 'sk' if sk_unique_score >= 2 || (slovak_score > czech_score + 1)

    @lang_config['fallback'] || 'cs'
  end

  # Extrahuje excerpt: první 1-2 věty z textu, bez hashtags a URL
  def extract_excerpt(text)
    # Odstraň URLs
    clean = text.gsub(%r{https?://[^\s]+}, '').strip
    # Odstraň hashtags
    clean = clean.gsub(/#\S+/, '').strip
    # Odstraň @mentions
    clean = clean.gsub(/@\S+/, '').strip
    # Odstraň emoji a zbytečné mezery
    clean = clean.gsub(/\s{2,}/, ' ').strip

    return '' if clean.length < 20

    max_chars  = @formatting['excerpt_max_chars'] || 280
    sentences  = @formatting['excerpt_sentences'] || 2

    # Rozděl na věty (tečka/vykřičník/otazník + mezera nebo konec)
    parts = clean.split(/(?<=[.!?])\s+/)

    if parts.size >= sentences
      excerpt = parts.first(sentences).join(' ')
    else
      excerpt = clean
    end

    # Zkrátit na max_chars
    if excerpt.length > max_chars
      excerpt = excerpt[0, max_chars - 1].rstrip
      # Nekončit uprostřed slova
      excerpt = excerpt.sub(/\s+\S+$/, '') if excerpt.length > max_chars * 0.8
      excerpt += '…'
    end

    excerpt
  end
end
