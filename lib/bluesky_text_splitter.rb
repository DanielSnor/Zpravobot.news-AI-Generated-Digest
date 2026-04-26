# frozen_string_literal: true
#
# BlueskyTextSplitter - rozdělí text na kusy ≤ 300 grafémů pro Bluesky
#
# Přeneseno z zbnw-ng/lib/publishers/bluesky_text_splitter.rb
#

class BlueskyTextSplitter
  CHAR_LIMIT = 300

  def split(text)
    cleaned = strip_hashtags(text.to_s)
    return [] if cleaned.empty?

    chunks  = []
    current = ''

    cleaned.split(/\n{2,}/).each do |para|
      candidate = current.empty? ? para : "#{current}\n\n#{para}"

      if grapheme_length(candidate) <= CHAR_LIMIT
        current = candidate
      elsif !current.empty?
        chunks << current
        current = split_paragraph_by_lines(para, chunks)
      else
        current = split_paragraph_by_lines(para, chunks)
      end
    end

    chunks << current unless current.empty?
    chunks
  end

  private

  def strip_hashtags(text)
    lines = text.rstrip.split("\n")
    lines.pop while lines.last&.match?(/\A\s*(#\w+\s*)*\s*\z/)
    lines.join("\n").rstrip
  end

  def split_paragraph_by_lines(para, chunks)
    lines       = para.split("\n")
    header_line = lines.first
    cont_header = "#{header_line.chomp(':')} - pokračování:"
    current     = ''

    lines.each do |line|
      candidate = current.empty? ? line : "#{current}\n#{line}"

      if grapheme_length(candidate) <= CHAR_LIMIT
        current = candidate
      else
        chunks << current unless current.empty?

        next_base = (line == header_line) ? line : "#{cont_header}\n#{line}"

        if grapheme_length(next_base) <= CHAR_LIMIT
          current = next_base
        else
          current = split_line_by_words(next_base, chunks)
        end
      end
    end

    current
  end

  def split_line_by_words(line, chunks)
    current = ''
    line.split(' ').each do |word|
      candidate = current.empty? ? word : "#{current} #{word}"
      if grapheme_length(candidate) <= CHAR_LIMIT
        current = candidate
      else
        chunks << current unless current.empty?
        current = word
      end
    end
    current
  end

  def grapheme_length(str)
    str.scan(/\X/).length
  end
end
