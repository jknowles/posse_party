require "tempfile"

class Platforms::Pixelfed
  # Uploads a single image to a Pixelfed instance using the Mastodon-compatible
  # media endpoint and returns the resulting media id (to be attached to a
  # status). Raises on any failure so the caller can fail the whole crosspost.
  class UploadsMedia
    MEDIA_PATH = "/api/v1/media".freeze
    EXTENSIONS = {
      "image/jpeg" => ".jpg",
      "image/png" => ".png",
      "image/webp" => ".webp",
      "image/gif" => ".gif"
    }.freeze

    def upload(image_url, base_url:, access_token:)
      image_data, content_type = download_image(image_url)
      raise "Failed to download Pixelfed media: #{image_url}" unless image_data

      file = build_tempfile(image_data, content_type)
      response = HTTParty.post(
        "#{base_url}#{MEDIA_PATH}",
        headers: {"Authorization" => "Bearer #{access_token}"},
        body: {file: file}
      )

      unless response.success? && (media_id = response.dig("id")).present?
        raise "Failed to upload media to Pixelfed (HTTP #{response.code}). Response: #{response.body}"
      end

      media_id
    ensure
      if file
        file.close
        file.unlink
      end
    end

    private

    def download_image(image_url)
      response = HTTParty.get(image_url, follow_redirects: true)
      return unless response.success?

      content_type = response.headers["content-type"].presence ||
        Marcel::MimeType.for(Pathname.new(URI.parse(image_url).path))
      [response.body, content_type]
    end

    def build_tempfile(image_data, content_type)
      extension = EXTENSIONS.fetch(content_type, ".jpg")
      file = Tempfile.new(["pixelfed_media", extension], binmode: true)
      file.write(image_data)
      file.rewind
      file
    end
  end
end
