# frozen_string_literal: true
#
# MastodonPublisher - publikování tootů na Mastodon API
#
# Funkce:
#   publish_thread(bot_name, summary, extensions, options) → true/false
#   dry_run_thread(summary, extensions)                   → výpis bez publikace
#
# Idempotence: ukládá SHA256 hash posledního threadu do .state/
#

require 'net/http'
require 'uri'
require 'json'
require 'openssl'
require 'digest'
require 'fileutils'
require 'time'

class MastodonPublisher
  include Loggable

  STATE_DIR  = File.expand_path('../../.state', __FILE__)
  MAX_RETRIES = 3

  def initialize(config_loader)
    @instance    = config_loader.mastodon['instance']
    @http_config = config_loader.global.fetch('http', {})
    @sleep_time  = config_loader.formatting['sleep_between_toots'] || 1
    FileUtils.mkdir_p(STATE_DIR)
  end

  # Dry-run: vytiskne vlákno bez publikace
  def dry_run(bot_name, summary, extensions)
    log_info("=== DRY-RUN: #{bot_name} ===")
    log_info("Celkem tootů: #{1 + extensions.size}")
    log_info("Délka summary: #{summary.length} znaků")

    puts "\n" + "=" * 60
    puts "[SUMMARY TOOT]"
    puts "=" * 60
    puts summary
    puts "(#{summary.length} znaků)"

    extensions.each_with_index do |ext, i|
      puts "\n" + "=" * 60
      puts "[EXTENSION #{i + 1}/#{extensions.size}]"
      puts "=" * 60
      puts ext
      puts "(#{ext.length} znaků)"
    end

    puts "\n" + "=" * 60
    log_info("DRY-RUN dokončen")
  end

  # Publikuje vlákno na Mastodon
  # Vrátí true při úspěchu, false při chybě
  def publish_thread(bot_name, summary, extensions, visibility: 'public')
    token = resolve_token(bot_name)
    return false unless token

    # Idempotence check
    hash = compute_hash(summary, extensions)
    if already_published?(bot_name, hash)
      log_info("Thread byl již dnes publikován (stejný hash) — přeskakuji")
      return true  # summary_id je stále v state souboru
    end

    log_info("Publikuji vlákno #{bot_name}: #{1 + extensions.size} tootů")

    # Publikuj summary
    summary_status = post_status(summary, nil, token, visibility)
    unless summary_status
      log_error("Nepodařilo se publikovat summary toot")
      return false
    end
    log_success("Summary toot publikován: #{summary_status['url']}")

    # Publikuj extensions jako reply
    parent_id = summary_status['id']

    extensions.each_with_index do |ext, i|
      sleep(@sleep_time + rand * 0.5)

      status = post_status(ext, parent_id, token, visibility)
      if status
        log_success("Extension #{i + 1}/#{extensions.size} publikován")
        parent_id = status['id']
      else
        log_error("Nepodařilo se publikovat extension #{i + 1}")
        return false
      end
    end

    save_state(bot_name, hash, summary_status['id'])
    log_success("Vlákno #{bot_name} úspěšně publikováno")
    true
  end

  # Vrátí summary_id posledního publishovaného threadu (jen pro dnešní den)
  def last_summary_id(bot_name)
    path = state_file(bot_name)
    return nil unless File.exist?(path)

    data = JSON.parse(File.read(path))
    stored_date = data['date'].to_s
    return nil unless stored_date == Date.today.to_s

    id = data['summary_id'].to_s
    id.empty? ? nil : id
  rescue StandardError
    nil
  end

  # Boostne (rebloguje) poslední summary toot daného bota
  # from_bot: bot jehož summary boostujeme
  # with_bot: bot který boostuje (zpravobot)
  # Vrátí true při úspěchu, false při chybě
  def boost_last(from_bot, with_bot)
    status_id = last_summary_id(from_bot)
    unless status_id
      log_error("Nenalezeno summary_id pro #{from_bot} — pravděpodobně ještě nepublikoval")
      return false
    end

    token = resolve_token(with_bot)
    return false unless token

    log_info("Boostuji #{from_bot} summary (#{status_id}) jako #{with_bot}")
    result = reblog_status(status_id, token)

    if result
      log_success("Boost #{from_bot} → #{with_bot} úspěšný")
      true
    else
      log_error("Boost #{from_bot} → #{with_bot} selhal")
      false
    end
  end

  private

  def resolve_token(bot_name)
    # Zkus různé varianty jména: ZPRAVOBOT_TOKEN, SLUNKOBOT_TOKEN, ...
    key = "#{bot_name.upcase}_TOKEN"
    token = ENV[key].to_s.strip

    if token.empty?
      log_error("Chybí environment variable #{key}")
      return nil
    end

    token
  end

  def post_status(text, in_reply_to_id, token, visibility)
    uri  = URI.parse("#{@instance}/api/v1/statuses")
    http = build_http(uri)

    body = { status: text, visibility: visibility }
    body[:in_reply_to_id] = in_reply_to_id if in_reply_to_id

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type']  = 'application/json'
    request['Accept']        = 'application/json'
    request['Authorization'] = "Bearer #{token}"
    request.body = body.to_json

    with_retry do
      response = http.request(request)

      case response.code.to_i
      when 200, 201
        JSON.parse(response.body)
      when 401
        log_error("Neplatný token pro Mastodon API")
        nil
      when 422
        log_error("Mastodon odmítl status (422): #{response.body[0, 200]}")
        nil
      when 429
        retry_after = response['Retry-After'].to_i
        wait = retry_after > 0 ? retry_after : 30
        log_warn("Rate limit — čekám #{wait}s")
        sleep(wait)
        raise 'rate_limit'
      when 500..599
        raise "Server error #{response.code}"
      else
        log_error("Neočekávaný HTTP status: #{response.code}")
        nil
      end
    end
  rescue StandardError => e
    log_error("Chyba při publikování: #{e.message}")
    nil
  end

  def build_http(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.open_timeout  = (@http_config['open_timeout']  || 5).to_i
    http.read_timeout  = (@http_config['read_timeout']  || 20).to_i
    http.write_timeout = (@http_config['write_timeout'] || 10).to_i
    http
  end

  def with_retry
    retries = 0
    begin
      yield
    rescue StandardError => e
      retries += 1
      if retries <= MAX_RETRIES
        sleep(2**retries)
        retry
      end
      raise e
    end
  end

  # ===== IDEMPOTENCE =====

  def compute_hash(summary, extensions)
    content = summary + extensions.join
    Digest::SHA256.hexdigest(content)[0, 16]
  end

  def state_file(bot_name)
    File.join(STATE_DIR, "#{bot_name}_last.json")
  end

  def already_published?(bot_name, hash)
    path = state_file(bot_name)
    return false unless File.exist?(path)

    data = JSON.parse(File.read(path))
    stored_hash = data['hash'].to_s
    stored_date = data['date'].to_s

    stored_hash == hash && stored_date == Date.today.to_s
  rescue StandardError
    false
  end

  def save_state(bot_name, hash, summary_id)
    File.write(state_file(bot_name), JSON.generate({
      hash:        hash,
      summary_id:  summary_id.to_s,
      date:        Date.today.to_s,
      published_at: Time.now.iso8601
    }))
  rescue StandardError => e
    log_warn("Nelze uložit stav: #{e.message}")
  end

  def reblog_status(status_id, token)
    uri  = URI.parse("#{@instance}/api/v1/statuses/#{status_id}/reblog")
    http = build_http(uri)

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type']  = 'application/json'
    request['Accept']        = 'application/json'
    request['Authorization'] = "Bearer #{token}"
    request.body = '{}'

    with_retry do
      response = http.request(request)

      case response.code.to_i
      when 200, 201
        JSON.parse(response.body)
      when 401
        log_error("Neplatný token pro boost")
        nil
      when 422
        log_warn("Status již byl boostnut nebo nelze boostnout (422)")
        true  # Považujeme za úspěch — idempotence
      when 429
        retry_after = response['Retry-After'].to_i
        wait = retry_after > 0 ? retry_after : 30
        log_warn("Rate limit — čekám #{wait}s")
        sleep(wait)
        raise 'rate_limit'
      when 500..599
        raise "Server error #{response.code}"
      else
        log_error("Neočekávaný HTTP status při boostu: #{response.code}")
        nil
      end
    end
  rescue StandardError => e
    log_error("Chyba při boostu: #{e.message}")
    nil
  end
end
