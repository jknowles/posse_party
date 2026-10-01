class DownloadsMedia
  Downloaded = Struct.new(:bytes, :content_type, keyword_init: true)
  TooLarge = Class.new(StandardError)
  TooSlow = Class.new(StandardError)
  DEADLINE = 60.seconds
  GENERIC_TYPES = %w[application/octet-stream binary/octet-stream].freeze

  def download(item, max_bytes:)
    return Result.failure(too_large(item, max_bytes)) if item.bytes.to_i > max_bytes

    started_at = Now.time
    body = +"".b
    response = HTTParty.get(item.url, stream_body: true, follow_redirects: true) do |fragment|
      raise TooSlow if Now.time - started_at > DEADLINE
      next unless fragment.code == 200
      raise TooLarge if fragment.http_response.content_length.to_i > max_bytes

      body << fragment
      raise TooLarge if body.bytesize > max_bytes
    end
    return Result.failure("Could not download #{item.url}: HTTP #{response.code}") unless response.code == 200

    Result.success(Downloaded.new(bytes: body, content_type: content_type(item, response, body)))
  rescue TooLarge
    Result.failure(too_large(item, max_bytes))
  rescue TooSlow
    Result.failure("#{item.url} took longer than #{DEADLINE.inspect} to download")
  rescue => e
    Result.failure("Could not download #{item.url}: #{e.message}")
  end

  private

  def too_large(item, max_bytes)
    "#{item.url} is over the #{max_bytes}-byte limit"
  end

  def content_type(item, response, body)
    item.mime.presence || named_type(response.headers["content-type"]) || Marcel::MimeType.for(StringIO.new(body))
  end

  def named_type(header)
    type = header.to_s.split(";").first.to_s.strip.downcase
    type unless type.blank? || GENERIC_TYPES.include?(type)
  end
end
