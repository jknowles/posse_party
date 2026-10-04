class Platforms::Mastodon
  class CallsMastodonMediaApi
    Uploaded = Struct.new(:id, :ready?, keyword_init: true)
    # HTTParty names a part's type from its extension unless the file names its own, and it calls
    # an .mp4 application/mp4, which Mastodon refuses
    TypedFile = Struct.new(:file, :content_type) do
      delegate :path, :read, :size, :rewind, to: :file
    end

    # 200 means Mastodon processed the file at once; 202 means it is still processing
    def upload(account, bytes:, extension:, description:)
      Tempfile.create(["media", extension], binmode: true) do |file|
        file.write(bytes)
        file.rewind
        post_media(account, file, description)
      end
    end

    # Streams a file from disk, so a video is never held in memory
    def upload_file(account, path:, content_type:, description:)
      File.open(path, "rb") { |file| post_media(account, TypedFile.new(file, content_type), description) }
    end

    # 206 means still processing; 200 means the file has its URL
    def check(account, id)
      response = HTTParty.get("#{account.credentials["base_url"]}/api/v1/media/#{id}", headers: authorization(account))

      if [200, 206].include?(response.code)
        Result.success(response.code == 200)
      else
        Result.failure("Mastodon could not process media #{id} (HTTP #{response.code}): #{response.body}")
      end
    end

    private

    def post_media(account, file, description)
      response = HTTParty.post("#{account.credentials["base_url"]}/api/v2/media",
        headers: authorization(account),
        body: {file:, description: description.presence}.compact,
        stream_body: true)

      if [200, 202].include?(response.code)
        Result.success(Uploaded.new(id: response["id"], ready?: response.code == 200))
      else
        Result.failure("Mastodon refused the upload (HTTP #{response.code}): #{response.body}")
      end
    end

    def authorization(account)
      {"Authorization" => "Bearer #{account.credentials["access_token"]}"}
    end
  end
end
