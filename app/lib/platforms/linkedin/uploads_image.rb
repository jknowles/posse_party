class Platforms::Linkedin
  class UploadsImage
    def initialize
      @redacts_bearer_token = RedactsBearerToken.new
    end

    def upload(image_url, upload_url, access_token:)
      return Outcome.failure("Image URL is required") if image_url.blank?
      return Outcome.failure("Upload URL is required") if upload_url.blank?

      if (image_data = download_image(image_url)).present?
        upload_bytes(image_data, content_type: "image/jpeg", upload_url:, access_token:)
      else
        Outcome.failure("Failed to download image from #{image_url}")
      end
    end

    def upload_bytes(bytes, content_type:, upload_url:, access_token:)
      response = HTTParty.put(
        upload_url,
        headers: {
          "Authorization" => "Bearer #{access_token}",
          "Content-Type" => content_type
        },
        body: bytes
      )

      if response.success?
        Outcome.success
      else
        Outcome.failure("Failed to upload image to LinkedIn. Response: #{response.parsed_response || response.body}")
      end
    rescue => e
      Outcome.failure("Failed to upload image to LinkedIn: #{@redacts_bearer_token.redact(e.message)}")
    end

    private

    def download_image(image_url)
      response = HTTParty.get(image_url)
      response.body if response.success?
    end
  end
end
