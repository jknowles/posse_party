class ParsesMediaItems
  TYPES = %w[image video].freeze

  def parse(raw)
    Array(raw).filter_map { |item|
      next unless item.is_a?(Hash)
      item = item.stringify_keys
      next unless TYPES.include?(item["type"]) && http_url?(item["url"])

      MediaItem.new(
        type: item["type"],
        url: item["url"],
        poster_url: item["poster_url"].presence,
        alt: item["alt"].to_s,
        presentation: item["presentation"].presence,
        mime: item["mime"].presence,
        width: positive_integer(item["width"]),
        height: positive_integer(item["height"]),
        bytes: positive_integer(item["bytes"])
      )
    }
  end

  private

  def http_url?(url)
    url.is_a?(String) && url.match?(%r{\Ahttps?://}i)
  end

  def positive_integer(value)
    value if value.is_a?(Integer) && value.positive?
  end
end
