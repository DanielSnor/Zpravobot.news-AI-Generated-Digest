# frozen_string_literal: true
#
# BlueskyPublisher - publikování digestu na Bluesky via AT Protocol
#
# Funkce:
#   publish_thread(bot_name, chunks)     → true/false
#   dry_run(bot_name, chunks)            → výpis bez publikace
#
# Idempotence: ukládá SHA256 hash posledního threadu do .state/{bot}_bluesky_last.json
#
# Přihlašovací údaje: config/bluesky_accounts.yml (viz bluesky_accounts.yml.example)
# ENV proměnné: ZPRAVOBOT_BLUESKY_APP_PASSWORD, SLUNKOBOT_BLUESKY_APP_PASSWORD, ...
#

require 'net/http'
require 'uri'
require 'json'
require 'digest'
require 'fileutils'
require 'time'
require 'openssl'

class BlueskyPublisher
  include Loggable

  STATE_DIR       = File.expand_path('../../.state', __FILE__)
  THROTTLE_SECONDS = 1
  MAX_RETRIES      = 3
  CHAR_LIMIT       = 300
  OPEN_TIMEOUT     = 5
  READ_TIMEOUT     = 20

  URL_PATTERN = %r{https?://[^\s]+}

  class BlueskyAuthError    < StandardError; end
  class BlueskyPublishError < StandardError; end
  class BlueskyRateLimitError < StandardError; end

  def initialize(config_loader)
    @bluesky_config = config_loader.bluesky
    FileUtils.mkdir_p(STATE_DIR)
  end

  # Dry-run: vytiskne chunky bez publikace
  def dry_run(bot_name, chunks)
    log_info("=== DRY-RUN Bluesky: #{bot_name} ===")
    log_info("Celkem postů: #{chunks.size}")

    chunks.each_with_index do |chunk, i|
      puts "\n" + "=" * 60
      puts "[BLUESKY #{i + 1}/#{chunks.size}]"
      puts "=" * 60
      puts chunk
      puts "(#{chunk.scan(/\X/).length} grafémů)"
    end

    puts "\n" + "=" * 60
    log_info("DRY-RUN Bluesky dokončen")
  end

  # Publikuje pole chunků jako Bluesky thread
  # Vrátí true při úspěchu, false při chybě
  def publish_thread(bot_name, chunks)
    return false if chunks.empty?

    hash = compute_hash(chunks)
    if already_published?(bot_name, hash)
      log_info("Bluesky thread byl již dnes publikován (stejný hash) — přeskakuji")
      return true
    end

    begin
      creds = load_credentials
    rescue => e
      log_error("Nelze načíst Bluesky přihlašovací údaje: #{e.message}")
      return false
    end

    begin
      session = create_session(creds[:pds_url], creds[:identifier], creds[:password])
    rescue BlueskyAuthError => e
      log_error("Bluesky autentizace selhala: #{e.message}")
      return false
    end

    access_jwt = session['accessJwt']
    did        = session['did']
    handle     = session['handle']
    log_info("Bluesky: přihlášen jako #{handle}, publikuji #{chunks.size} postů")

    results    = []
    root_ref   = nil
    parent_ref = nil

    chunks.each_with_index do |text, idx|
      sleep(THROTTLE_SECONDS) if idx > 0

      record = build_record(text)

      unless idx.zero?
        record['reply'] = {
          'root'   => { 'uri' => root_ref[:uri],   'cid' => root_ref[:cid] },
          'parent' => { 'uri' => parent_ref[:uri], 'cid' => parent_ref[:cid] }
        }
      end

      begin
        result = create_record(creds[:pds_url], did, access_jwt, record)
      rescue => e
        log_error("Bluesky publikování selhalo na postu #{idx + 1}: #{e.message}")
        return false
      end

      ref = { uri: result['uri'], cid: result['cid'] }
      log_info("Bluesky #{idx + 1}/#{chunks.size}: #{ref[:uri]}")

      root_ref   ||= ref
      parent_ref   = ref
      results << ref
    end

    save_state(bot_name, hash, root_ref[:uri])
    log_success("Bluesky thread #{bot_name} úspěšně publikován (#{chunks.size} postů)")
    true
  end

  private

  # ----------------------------------------------------------------
  # Credentials
  # ----------------------------------------------------------------

  def load_credentials
    identifier = @bluesky_config['identifier'].to_s
    env_name   = @bluesky_config['app_password_env'].to_s
    password   = ENV[env_name].to_s.strip
    pds_url    = (@bluesky_config['pds_url'] || 'https://bsky.social').chomp('/')

    raise "bluesky.identifier není nastaven v config/global.yml" if identifier.empty?
    raise "ENV proměnná #{env_name} není nastavena (Bluesky app password)" if password.empty?

    { identifier: identifier, password: password, pds_url: pds_url }
  end

  # ----------------------------------------------------------------
  # Session
  # ----------------------------------------------------------------

  def create_session(pds_url, identifier, password)
    xrpc_post(pds_url, 'com.atproto.server.createSession',
              { identifier: identifier, password: password })
  rescue BlueskyPublishError => e
    raise BlueskyAuthError, "Autentizace selhala: #{e.message}"
  end

  # ----------------------------------------------------------------
  # Record building
  # ----------------------------------------------------------------

  def build_record(text)
    record = {
      '$type'     => 'app.bsky.feed.post',
      'text'      => text,
      'createdAt' => Time.now.utc.iso8601(3),
      'langs'     => ['cs']
    }
    facets = build_facets(text)
    record['facets'] = facets unless facets.empty?
    record
  end

  def build_facets(text)
    facets = []
    text.scan(URL_PATTERN) do |url|
      match      = Regexp.last_match
      byte_start = text[0...match.begin(0)].bytesize
      byte_end   = byte_start + url.bytesize
      facets << {
        'index'    => { 'byteStart' => byte_start, 'byteEnd' => byte_end },
        'features' => [{ '$type' => 'app.bsky.richtext.facet#link', 'uri' => url }]
      }
    end
    facets
  end

  # ----------------------------------------------------------------
  # XRPC
  # ----------------------------------------------------------------

  def create_record(pds_url, did, access_jwt, record)
    with_retry do
      xrpc_post(pds_url, 'com.atproto.repo.createRecord',
                { repo: did, collection: 'app.bsky.feed.post', record: record },
                jwt: access_jwt)
    end
  end

  def xrpc_post(pds_url, endpoint, body, jwt: nil)
    uri  = URI("#{pds_url}/xrpc/#{endpoint}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = (uri.scheme == 'https')
    http.verify_mode  = OpenSSL::SSL::VERIFY_PEER
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    req = Net::HTTP::Post.new(uri.path)
    req['Content-Type']  = 'application/json'
    req['Authorization'] = "Bearer #{jwt}" if jwt
    req.body = JSON.generate(body)

    resp = http.request(req)
    handle_response(resp, endpoint)
  end

  def handle_response(resp, endpoint)
    code = resp.code.to_i

    if code == 429
      retry_after = [resp['Retry-After'].to_i, 60].min
      retry_after = 5 if retry_after < 1
      log_warn("Bluesky rate limit — čekám #{retry_after}s")
      sleep(retry_after)
      raise BlueskyRateLimitError, "Rate limit na #{endpoint}"
    end

    if code == 401 || code == 403
      data = safe_parse_json(resp.body)
      msg  = data&.dig('message') || data&.dig('error') || resp.body[0, 200]
      raise BlueskyAuthError, "HTTP #{code} z #{endpoint}: #{msg}"
    end

    unless resp.is_a?(Net::HTTPSuccess)
      data = safe_parse_json(resp.body)
      msg  = data&.dig('message') || data&.dig('error') || resp.body[0, 200]
      raise BlueskyPublishError, "HTTP #{code} z #{endpoint}: #{msg}"
    end

    JSON.parse(resp.body)
  end

  def with_retry
    attempts = 0
    begin
      attempts += 1
      yield
    rescue BlueskyRateLimitError
      raise if attempts >= MAX_RETRIES
      retry
    rescue BlueskyPublishError => e
      raise if attempts >= MAX_RETRIES
      backoff = 2**attempts
      log_warn("Bluesky přechodná chyba (pokus #{attempts}/#{MAX_RETRIES}), retry za #{backoff}s: #{e.message}")
      sleep(backoff)
      retry
    end
  end

  def safe_parse_json(body)
    JSON.parse(body)
  rescue JSON::ParserError
    nil
  end

  # ----------------------------------------------------------------
  # Idempotence
  # ----------------------------------------------------------------

  def compute_hash(chunks)
    Digest::SHA256.hexdigest(chunks.join)[0, 16]
  end

  def state_file(bot_name)
    File.join(STATE_DIR, "#{bot_name}_bluesky_last.json")
  end

  def already_published?(bot_name, hash)
    path = state_file(bot_name)
    return false unless File.exist?(path)

    data = JSON.parse(File.read(path))
    data['hash'].to_s == hash && data['date'].to_s == Date.today.to_s
  rescue StandardError
    false
  end

  def save_state(bot_name, hash, root_uri)
    File.write(state_file(bot_name), JSON.generate({
      hash:         hash,
      root_uri:     root_uri.to_s,
      date:         Date.today.to_s,
      published_at: Time.now.iso8601
    }))
  rescue StandardError => e
    log_warn("Nelze uložit Bluesky stav: #{e.message}")
  end
end
