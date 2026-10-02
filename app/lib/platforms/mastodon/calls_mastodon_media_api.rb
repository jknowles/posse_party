class Platforms::Mastodon
  class CallsMastodonMediaApi
    Uploaded = Struct.new(:id, :ready?, keyword_init: true)

    # 200 means Mastodon processed the file at once; 202 means it is still processing
    def upload(account, bytes:, extension:, description:)
      Tempfile.create(["media", extension], binmode: true) do |file|
        file.write(bytes)
        file.rewind
        response = HTTParty.post("#{account.credentials["base_url"]}/api/v2/media",
          headers: authorization(account),
          body: {file:, description: description.presence}.compact)

        if [200, 202].include?(response.code)
          Result.success(Uploaded.new(id: response["id"], ready?: response.code == 200))
        else
          Result.failure("Mastodon refused the upload (HTTP #{response.code}): #{response.body}")
        end
      end
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

    def authorization(account)
      {"Authorization" => "Bearer #{account.credentials["access_token"]}"}
    end
  end
end
