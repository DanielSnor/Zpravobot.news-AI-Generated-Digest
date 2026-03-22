# frozen_string_literal: true
#
# TopicExtractor - kategorizuje posty do digest témat
#
# Priority pro určení tématu:
#   1. Kategorie zdrojového účtu (z AccountCategorizer) - nejspolehlivější
#   2. URL doména/path (heuristika)
#   3. Text keywords (fallback)
#
# Vrátí hash: { "Sport" => [post, post, ...], "Politika" => [...], ... }
# seřazený dle topic_priority z global.yml
#

require 'uri'

class TopicExtractor
  include Loggable

  SPORT_URL_PATTERNS = %r{
    /sport[/\-]|sport\.cz|isport\.cz|hokej\.cz|fotbal\.cz|
    livesport|flashsco\.re|cycling|formula|speedway|f1\.cz|
    /hokej|/fotbal|/tenis|/atletika|/cyklo
  }xi.freeze

  URL_PATH_TOPICS = {
    'Politika'            => %r{/politi[ck]|/volby|/vlada|/parlament|/ministr|/premier|/senat},
    'Zprávy'              => %r{/zpravy|/aktualne|/domaci|/cesko|/slovensko},
    'Ekonomika'           => %r{/ekonomi[ck]|/finance|/byznys|/trhy|/burza|/inflace|/cnb},
    'Věda & Příroda'      => %r{/veda|/priroda|/ekologie|/klima|/environment},
    'Technologie'         => %r{/techno|/it-news|/digital|/internet|/pocitace},
    'Kultura'             => %r{/kultura|/film|/hudba|/divadlo|/literatura|/knihy|/umeni},
    'Počasí'              => %r{/pocasi|/weather},
    'Konflikty'           => %r{/valka|/konflikt|/ukraji|/militar|/zbrane|/armad},
    'Zahraniční politika' => %r{/zahranici|/svet|/eu|/nato|/trump|/putini},
    'Investigativa'       => %r{/investigativ|/watchdog|/korupce|/kauza},
    'Automobily'          => %r{/auto|/moto[^rs]|/ridici|/motorsport(?!.*f1)},
    'Sport'               => %r{/sport}
  }.freeze

  DOMAIN_TOPICS = {
    'Sport'               => %w[isport.cz sport.cz hokej.cz fotbal.cz livesport.cz],
    'Automobily'          => %w[auto.cz autorevue.cz auto7.cz],
    'Ekonomika'           => %w[ekonom.cz e15.cz penize.cz finmag.cz],
    'Věda & Příroda'      => %w[veda.cz osel.cz meteorologie.cz],
    'Zahraniční politika' => %w[zahranicni.cz]
  }.freeze

  TEXT_KEYWORD_TOPICS = {
    'Zahraniční politika' => %w[trump biden putin zelenskyj nato eu usa kanada venezuela izrael hamas válka sanctions],
    'Politika'            => %w[vláda parlament ministr premiér fiala babiš koalice opozice volby senát],
    'Ekonomika'           => %w[inflace mzdy cnb akcie burza ekonomika hdp dluh deficit rozpočet],
    'Věda & Příroda'      => %w[vědci výzkum klimatická změna planeta příroda ekologie biologie chemie fyzika],
    'Technologie'         => %w[ai umělá inteligence chatgpt robot tesla spacex technologie software hardware],
    'Kultura'             => %w[film premiéra hudba album výstava galerie divadlo muzeum kniha literatura],
    'Počasí'              => %w[počasí teplota mrazy sníh bouře déšť sucho vlna veder předpověď],
    'Konflikty'           => %w[válka vojenský armáda útok bomba střelba ozbrojený konflikt raketa],
    'Investigativa'       => %w[korupce kauza obvinění skandál trestní soud rozsudek přijal úplatky]
  }.freeze

  def initialize(config_loader, account_categorizer)
    @topic_priority    = config_loader.topic_priority
    @category_map      = config_loader.category_map
    @lang_config       = config_loader.language_config
    @account_cat       = account_categorizer
  end

  # Kategorizuje posty a vrátí hash { téma => [posty] } seřazený dle priority
  # Filtruje témata s méně než min_posts posty
  def extract(posts, min_posts: 8)
    topics = Hash.new { |h, k| h[k] = [] }

    posts.each do |post|
      topic = determine_topic(post)
      topics[topic] << post if topic
    end

    # Odfiltruj témata s malým počtem postů
    topics.reject! { |_, posts_arr| posts_arr.size < min_posts }

    log_info("Nalezena témata: #{topics.map { |t, p| "#{t}(#{p.size})" }.join(', ')}")

    # Seřaď dle priority (vyšší číslo = větší priorita = dříve)
    topics.sort_by { |topic, _| -(@topic_priority[topic] || 0) }.to_h
  end

  # Vrátí název tématu pro jeden post nebo nil
  def determine_topic(post)
    account_id = post[:account_id]
    url        = post[:url].to_s
    text       = post[:text].to_s.downcase

    # PRIORITY 1: Sport URL — musí být PRVNÍ (přeskočí vše ostatní)
    return 'Sport' if url.match?(SPORT_URL_PATTERNS)

    # PRIORITY 2: Kategorie zdrojového účtu (nejspolehlivější)
    account_topic = @account_cat.primary_topic_for(account_id)
    return account_topic if account_topic

    # PRIORITY 3: URL doména
    domain_topic = topic_from_domain(url)
    return domain_topic if domain_topic

    # PRIORITY 4: URL path
    path_topic = topic_from_url_path(url)
    return path_topic if path_topic

    # PRIORITY 5: Text keywords
    text_topic = topic_from_text(text)
    return text_topic if text_topic

    # Fallback: Zprávy (obecné zpravodajství)
    'Zprávy'
  end

  private

  def topic_from_domain(url)
    return nil if url.empty?

    begin
      host = URI.parse(url).host.to_s.downcase.sub(/^www\./, '')
    rescue URI::InvalidURIError
      return nil
    end

    DOMAIN_TOPICS.each do |topic, domains|
      return topic if domains.any? { |d| host == d || host.end_with?(".#{d}") }
    end

    nil
  end

  def topic_from_url_path(url)
    return nil if url.empty?

    begin
      path = URI.parse(url).path.to_s.downcase
    rescue URI::InvalidURIError
      return nil
    end

    URL_PATH_TOPICS.each do |topic, pattern|
      return topic if path.match?(pattern)
    end

    nil
  end

  def topic_from_text(text)
    best_topic = nil
    best_score = 0

    TEXT_KEYWORD_TOPICS.each do |topic, keywords|
      score = keywords.count { |kw| text.include?(kw) }
      if score > best_score
        best_score = score
        best_topic = topic
      end
    end

    best_score >= 2 ? best_topic : nil
  end
end
