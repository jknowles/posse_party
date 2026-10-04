class DownloadsMedia
  Downloaded = Struct.new(:bytes, :content_type, keyword_init: true)
  DownloadedFile = Struct.new(:path, :size, :content_type, keyword_init: true)
  TooLarge = Class.new(StandardError)
  TooSlow = Class.new(StandardError)
  DEADLINE = 60.seconds
  # A video is up to 100 MB, so it gets longer than an image before the download gives up
  VIDEO_DEADLINE = 180.seconds
  GENERIC_TYPES = %w[application/octet-stream binary/octet-stream].freeze
  # The video types any of the platforms take, named as Mastodon expects them
  VIDEO_EXTENSIONS = {"video/mp4" => ".mp4", "video/quicktime" => ".mov", "video/webm" => ".webm"}.freeze

  def download(item, max_bytes:)
    body = +"".b
    fetched = fetch(item, max_bytes:, deadline: DEADLINE) { |fragment| body << fragment }
    return fetched if fetched.failure?

    Result.success(Downloaded.new(bytes: body, content_type: content_type(item, fetched.data, StringIO.new(body))))
  end

  # Streams the file to disk, so a video is never held in memory, and names it with its type's
  # extension, so a multipart upload names the file correctly. The caller deletes the file.
  def download_to_tempfile(item, max_bytes:)
    file = Tempfile.create("media", binmode: true)
    path = file.path
    fetched = fetch(item, max_bytes:, deadline: VIDEO_DEADLINE) { |fragment| file.write(fragment) }
    file.close
    return fetched.tap { File.delete(path) } if fetched.failure?

    content_type = content_type(item, fetched.data, Pathname.new(path))
    named_path = "#{path}#{VIDEO_EXTENSIONS[content_type]}"
    File.rename(path, named_path)
    path = named_path
    Result.success(DownloadedFile.new(path:, size: File.size(path), content_type:))
  rescue Exception # standard:disable Lint/RescueException
    # Includes Timeout::ExitException, which is not a StandardError, so no file outlives its job
    file&.close unless file&.closed?
    FileUtils.rm_f(path) if path
    raise
  end

  private

  def fetch(item, max_bytes:, deadline:)
    return Result.failure(too_large(item, max_bytes)) if item.bytes.to_i > max_bytes

    started_at = Now.time
    received = 0
    response = HTTParty.get(item.url, stream_body: true, follow_redirects: true) do |fragment|
      raise TooSlow if Now.time - started_at > deadline
      next unless fragment.code == 200
      raise TooLarge if fragment.http_response.content_length.to_i > max_bytes

      received += fragment.bytesize
      raise TooLarge if received > max_bytes
      yield fragment
    end
    return Result.failure("Could not download #{item.url}: HTTP #{response.code}") unless response.code == 200

    Result.success(response)
  rescue TooLarge
    Result.failure(too_large(item, max_bytes))
  rescue TooSlow
    Result.failure("#{item.url} took longer than #{deadline.inspect} to download")
  rescue => e
    Result.failure("Could not download #{item.url}: #{e.message}")
  end

  def too_large(item, max_bytes)
    "#{item.url} is over the #{max_bytes}-byte limit"
  end

  def content_type(item, response, content)
    item.mime.presence || named_type(response.headers["content-type"]) || Marcel::MimeType.for(content)
  end

  def named_type(header)
    type = header.to_s.split(";").first.to_s.strip.downcase
    type unless type.blank? || GENERIC_TYPES.include?(type)
  end
end
