class Platforms::Bsky
  class UploadsBskyBlob
    # Dropping down to do this ourselves b/c the bsky gem assumes you're reading the image from a file
    # https://github.com/ShreyanJain9/bskyrb/blob/main/lib/bskyrb/records.rb#L36
    def upload(bytes, content_type, record_manager)
      response = HTTParty.post(
        record_manager.upload_blob_uri(record_manager.session.pds),
        body: bytes,
        headers: record_manager.default_authenticated_headers(record_manager.session).merge("Content-Type" => content_type)
      )

      if response.success?
        Result.success(response["blob"])
      else
        Result.failure("Bluesky refused the upload (HTTP #{response.code}): #{response.body}")
      end
    rescue => e
      Result.failure("Could not upload to Bluesky: #{e.message}")
    end
  end
end
