# frozen_string_literal: true
#
# TootBuilder - sestavuje tooty pro 2500 znakový limit
#
# Generuje:
#   summary_toot  - první toot ve vlákně (přehled všech témat)
#   extension_toots - reply tooty s vybranými články a excerpty
#

require 'date'

class TootBuilder
  include Loggable

  # Emoji pro každé téma
  TOPIC_EMOJI = {
    'Konflikty'           => '⚔️',
    'Zahraniční politika' => '🌍',
    'Politika'            => '🏛️',
    'Zprávy'              => '📰',
    'Ekonomika'           => '📈',
    'Investigativa'       => '🔍',
    'Komentáře'           => '💬',
    'Kultura'             => '🎭',
    'Věda & Příroda'      => '🔬',
    'Technologie'         => '💻',
    'Počasí'              => '🌤️',
    'Sport'               => '⚽',
    'Automobily'          => '🚗',
    'Zábava'              => '😄',
    'Foto & Video'        => '📸',
    'Životní styl'        => '☕',
    'Společnost'          => '🤝',
    'Médiá'               => '📡'
  }.freeze

  ROTATING_FOOTERS = {
    'positive' => [
      "\n\nSvět není jen špatný. Tady je důkaz ☀️",
      "\n\nDnes se stalo i něco dobrého. Věř tomu 🌱",
      "\n\nPozitivní zprávy existují. Hledali jsme za tebe 💚"
    ],
    'sarcastic' => [
      "\n\n...a přitom se říká, že jsme se poučili z dějin 🤡",
      "\n\nZítra bude hůř. Nebo ne. Ale asi jo 😑",
      "\n\nA toto je jen dnešní výběr z nekonečné zásoby 🎪"
    ]
  }.freeze

  def initialize(config_loader)
    @max_length    = config_loader.mastodon['max_toot_length']    || 2500
    @url_length    = config_loader.mastodon['url_counted_length'] || 23
    @formatting    = config_loader.formatting
    @safety_buffer = (@formatting['title_safety_buffer'] || 30).to_i
  end

  # Sestaví první toot (přehled témat)
  def summary_toot(topics, posts_count, analysis, bot_config, date: nil)
    style    = bot_config['style']
    hashtags = bot_config['hashtags'].to_s
    date_str = (date || Date.today).strftime('%d.%m.%Y')

    header = summary_header(style, date_str, posts_count)
    ai_summary = format_ai_summary(analysis[:summary], style)
    topics_list = format_topics_list(topics, style)
    footer = "\n\n#{hashtags}\n\n👇 Vybrané články v threadu"

    assemble(header, ai_summary, topics_list, footer)
  end

  # Sestaví pole extension tootů z vybraných článků
  # selected: pole { topic:, post: } hashů
  # Vrátí pole stringů
  def extension_toots(selected, bot_config, commentaries: [])
    style          = bot_config['style']
    ext_count      = bot_config.dig('threads', 'extension_toots') || 3
    per_toot       = bot_config.dig('threads', 'articles_per_toot') || 4
    include_excerpt = bot_config.dig('articles', 'include_excerpt') != false
    add_commentary  = bot_config.dig('articles', 'add_commentary') == true
    hashtags       = bot_config['hashtags'].to_s

    # Rozděl články do skupin
    chunks = selected.each_slice(per_toot).first(ext_count)
    total  = chunks.size

    chunks.each_with_index.map do |chunk, idx|
      is_last = (idx == total - 1)
      build_extension(chunk, commentaries, idx, is_last, style, hashtags, include_excerpt, add_commentary)
    end
  end

  private

  # ===== SUMMARY TOOT =====

  def summary_header(style, date_str, posts_count)
    case style
    when 'positive'
      "☀️ DOBRÉ ZPRÁVY DNE (#{date_str})\n\nZ #{posts_count} zpráv to pozitivní:"
    when 'sarcastic'
      "😏 DNEŠNÍ REALITA (#{date_str})\n\n#{posts_count} postů = co se vlastně stalo?"
    else
      "📊 TRENDY DNE (#{date_str})\n\nZpracováno #{posts_count} postů:"
    end
  end

  def format_ai_summary(summary, _style)
    return '' if summary.to_s.strip.empty?

    "\n\n#{summary.strip}"
  end

  def format_topics_list(topics, style)
    return '' if topics.empty?

    lines = topics.map do |topic, posts|
      emoji = TOPIC_EMOJI[topic] || '📌'
      count = posts.size
      case style
      when 'positive'
        "#{emoji} #{topic} (#{count}×)"
      when 'sarcastic'
        "#{emoji} #{topic} (#{count}×)"
      else
        "#{emoji} #{topic} (#{count} postů)"
      end
    end

    "\n\n" + lines.join("\n")
  end

  # ===== EXTENSION TOOT =====

  def build_extension(chunk, commentaries, idx, is_last, style, hashtags, include_excerpt, add_commentary)
    header = extension_header(style, idx)
    body   = format_articles(chunk, commentaries, idx, include_excerpt, add_commentary, style)
    footer = extension_footer(style, hashtags, is_last, idx)

    toot = assemble(header, body, footer)

    # Pokud je toot příliš dlouhý, zkraťuj titulky iterativně
    if counted_length(toot) > @max_length
      toot = shorten_toot(chunk, commentaries, idx, is_last, style, hashtags, include_excerpt, add_commentary)
    end

    toot
  end

  def extension_header(style, idx)
    case style
    when 'positive'
      "💚 POZITIVNÍ PŘÍBĚHY #{idx + 1}:"
    when 'sarcastic'
      "🤡 \"BREAKING NEWS\" #{idx + 1}:"
    else
      "📌 VYBRANÉ ČLÁNKY #{idx + 1}:"
    end
  end

  def format_articles(chunk, commentaries, chunk_idx, include_excerpt, add_commentary, style)
    lines = []
    comment_offset = chunk_idx * chunk.size  # Index do pole komentářů

    chunk.each_with_index do |item, i|
      post    = item[:post]
      topic   = item[:topic]
      emoji   = TOPIC_EMOJI[topic] || '📌'
      url     = post[:url].to_s
      comment = add_commentary ? commentaries[comment_offset + i].to_s : ''
      # Hlavní text = excerpt (1-2 věty), fallback na první větu z textu
      excerpt = include_excerpt ? post[:excerpt].to_s : extract_title(post[:text], 120)

      lines << format_article(emoji, nil, url, excerpt, comment, style)
    end

    "\n\n" + lines.join("\n\n")
  end

  def format_article(emoji, title, url, excerpt, comment, _style)
    # Zobraz excerpt jako hlavní text (je delší než titulek).
    # Pokud excerpt chybí, použij titulek jako fallback.
    body = excerpt.strip.empty? ? title : excerpt.strip
    parts = ["#{emoji} #{body}"]
    parts << "💬 \"#{comment}\"" unless comment.strip.empty?
    parts << "🔗 #{url}" unless url.empty?
    parts.join("\n")
  end

  def extension_footer(style, hashtags, is_last, idx)
    base = "\n\n#{hashtags}"

    if is_last
      rotating = ROTATING_FOOTERS[style] || []
      base + (rotating.empty? ? '' : rotating[idx % rotating.size])
    else
      base + "\n\n▶️ pokračování →"
    end
  end

  # ===== ZKRACOVÁNÍ =====

  # Zkrátí titulky pokud toot překračuje limit (až 3 iterace)
  def shorten_toot(chunk, commentaries, idx, is_last, style, hashtags, include_excerpt, add_commentary)
    max_title = (@formatting['title_max_length'] || 80).to_i
    min_title = (@formatting['title_min_length'] || 30).to_i

    3.times do
      header = extension_header(style, idx)
      body   = format_articles_with_max(chunk, commentaries, idx, include_excerpt, add_commentary, style, max_title)
      footer = extension_footer(style, hashtags, is_last, idx)
      toot   = assemble(header, body, footer)

      return toot if counted_length(toot) <= @max_length

      # Vypočítej o kolik je moc a přiměřeně zkraťuj
      excess = counted_length(toot) - @max_length
      chars_per_article = [excess / [chunk.size, 1].max, 10].max
      max_title = [max_title - chars_per_article, min_title].max
    end

    # Fallback — vrátíme i když je mírně delší
    header = extension_header(style, idx)
    body   = format_articles_with_max(chunk, commentaries, idx, include_excerpt, add_commentary, style, min_title)
    footer = extension_footer(style, hashtags, is_last, idx)
    assemble(header, body, footer)
  end

  def format_articles_with_max(chunk, commentaries, chunk_idx, include_excerpt, add_commentary, style, max_title)
    lines = []
    comment_offset = chunk_idx * chunk.size

    chunk.each_with_index do |item, i|
      post    = item[:post]
      topic   = item[:topic]
      emoji   = TOPIC_EMOJI[topic] || '📌'
      url     = post[:url].to_s
      comment = add_commentary ? commentaries[comment_offset + i].to_s : ''
      # Zkrácení se aplikuje na excerpt (hlavní text), ne na titulek
      raw_excerpt = include_excerpt ? post[:excerpt].to_s : ''
      excerpt = raw_excerpt.empty? ? extract_title(post[:text], max_title) : smart_truncate(raw_excerpt, max_title)

      lines << format_article(emoji, nil, url, excerpt, comment, style)
    end

    "\n\n" + lines.join("\n\n")
  end

  # ===== UTILITY =====

  # Extrahuje titulek z textu postu (první věta nebo první max_len znaků)
  def extract_title(text, max_len)
    # Odstraň URLs a hashtags pro titulek
    clean = text.to_s
                .gsub(%r{https?://\S+}, '')
                .gsub(/#\S+/, '')
                .gsub(/@\S+/, '')
                .gsub(/\s{2,}/, ' ')
                .strip

    # Vezmi první větu
    title = clean.split(/(?<=[.!?])\s+/).first.to_s.strip
    title = clean if title.length < 20  # Příliš krátká věta — vezmi celý text

    smart_truncate(title, max_len)
  end

  def smart_truncate(text, max_len)
    return text if text.length <= max_len

    truncated = text[0, max_len - 1]
    # Nekončit uprostřed slova
    truncated = truncated.sub(/\s+\S+$/, '') if truncated.length > max_len * 0.7
    truncated.rstrip + '…'
  end

  def assemble(*parts)
    parts.reject { |p| p.to_s.strip.empty? }.join
  end

  # Mastodon počítá URL jako url_counted_length znaků bez ohledu na skutečnou délku
  def counted_length(text)
    len = text.to_s.length
    # Nahraď každou URL jejím "counted" ekvivalentem
    urls = text.to_s.scan(%r{https?://\S+})
    urls.each do |url|
      len -= url.length
      len += @url_length
    end
    len
  end
end
