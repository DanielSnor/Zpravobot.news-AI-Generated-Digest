# frozen_string_literal: true
#
# Centrální logging modul s rotací souborů
# Adaptováno ze vzoru zbnw-ng
#

require 'fileutils'
require 'time'

module Logging
  LOG_LEVELS = { debug: 0, info: 1, success: 1, warn: 2, error: 3 }.freeze

  class << self
    def setup(name:, dir: 'logs', keep_days: 30, level: :info)
      @level = level
      @dir   = dir
      @name  = name
      FileUtils.mkdir_p(dir)

      date     = Time.now.strftime('%Y%m%d')
      log_path = File.join(dir, "#{name}_#{date}.log")
      @file    = File.open(log_path, 'a')
      @file.sync = true

      cleanup_old_logs(keep_days)
      info("=== #{name.upcase} START #{Time.now.strftime('%Y-%m-%d %H:%M:%S %Z')} ===")
    end

    def debug(msg);   write(:debug,   '🔍', msg); end
    def info(msg);    write(:info,    'ℹ️ ', msg); end
    def success(msg); write(:success, '✅', msg); end
    def warn(msg);    write(:warn,    '⚠️ ', msg); end
    def error(msg);   write(:error,   '❌', msg); end

    def close
      return unless @file
      info("=== #{@name&.upcase} END #{Time.now.strftime('%Y-%m-%d %H:%M:%S %Z')} ===")
      @file.close
      @file = nil
    end

    private

    def write(level, emoji, msg)
      return if LOG_LEVELS[level].to_i < LOG_LEVELS[@level || :info].to_i

      timestamp = Time.now.strftime('%H:%M:%S')
      line = "#{timestamp} #{emoji}  #{msg}"

      puts line
      @file&.puts(line)
    end

    def cleanup_old_logs(keep_days)
      return unless @dir && @name

      cutoff = Time.now - (keep_days * 86_400)
      Dir.glob(File.join(@dir, "#{@name}_*.log")).each do |f|
        File.delete(f) if File.mtime(f) < cutoff
      rescue StandardError
        # Ignore cleanup errors
      end
    end
  end
end

# Mixin pro automatické logování ve třídách
module Loggable
  def log_info(msg);    Logging.info("[#{self.class.name}] #{msg}"); end
  def log_success(msg); Logging.success("[#{self.class.name}] #{msg}"); end
  def log_warn(msg);    Logging.warn("[#{self.class.name}] #{msg}"); end
  def log_error(msg);   Logging.error("[#{self.class.name}] #{msg}"); end
  def log_debug(msg);   Logging.debug("[#{self.class.name}] #{msg}"); end
end
