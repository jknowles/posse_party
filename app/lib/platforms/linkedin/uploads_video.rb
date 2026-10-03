class Platforms::Linkedin
  class UploadsVideo
    def initialize
      @calls_linkedin_api = CallsLinkedinApi.new
      @redacts_bearer_token = RedactsBearerToken.new
    end

    # LinkedIn's Videos API: initialize, PUT each part LinkedIn asks for and keep its ETag, PUT the
    # thumbnail if there is one, then finalize with the ETags in order. Returns the video's URN.
    def upload(path, thumbnail:, access_token:, person_urn:)
      started = @calls_linkedin_api.call(method: :post, path: "rest/videos?action=initializeUpload", access_token:, body: {
        initializeUploadRequest: {owner: person_urn, fileSizeBytes: File.size(path), uploadCaptions: false, uploadThumbnail: thumbnail.present?}
      })
      return Result.failure("LinkedIn would not start the video upload. #{started.message}") unless started.success?

      upload = started.data["value"]
      part_ids = upload["uploadInstructions"].map { |part| put_part(path, part, access_token:) }
      put_thumbnail(thumbnail, upload["thumbnailUploadUrl"], access_token:) if thumbnail.present?
      finished = @calls_linkedin_api.call(method: :post, path: "rest/videos?action=finalizeUpload", access_token:, body: {
        finalizeUploadRequest: {video: upload["video"], uploadToken: upload["uploadToken"].to_s, uploadedPartIds: part_ids}
      })
      return Result.failure("LinkedIn would not finish the video upload. #{finished.message}") unless finished.success?

      Result.success(upload["video"])
    rescue MediaUnavailable => e
      Result.failure(e.message)
    end

    # PROCESSING, WAITING_UPLOAD, AVAILABLE or PROCESSING_FAILED
    def status(urn, access_token:)
      checked = @calls_linkedin_api.call(method: :get, path: "rest/videos/#{CGI.escape(urn)}", access_token:)
      return Result.failure("LinkedIn could not report on video #{urn}. #{checked.message}") unless checked.success?

      Result.success(checked.data["status"])
    end

    private

    def put_part(path, part, access_token:)
      bytes = File.open(path, "rb") { |file| file.pread(part["lastByte"] - part["firstByte"] + 1, part["firstByte"]) }
      response = put(part["uploadUrl"], bytes, {"Content-Type" => "application/octet-stream"}, access_token:)
      response.headers["etag"].to_s.delete('"').presence or raise MediaUnavailable, "LinkedIn returned no ETag for a video part"
    end

    def put_thumbnail(thumbnail, upload_url, access_token:)
      raise MediaUnavailable, "LinkedIn gave no thumbnail upload URL" if upload_url.blank?

      put(upload_url, thumbnail, {"Content-Type" => "application/octet-stream", "media-type-family" => "STILLIMAGE"}, access_token:)
    end

    def put(url, bytes, headers, access_token:)
      response = HTTParty.put(url, headers: {"Authorization" => "Bearer #{access_token}"}.merge(headers), body: bytes)
      raise MediaUnavailable, "LinkedIn refused a video upload (HTTP #{response.code}): #{response.body}" unless response.success?

      response
    rescue MediaUnavailable
      raise
    rescue => e
      raise MediaUnavailable, "Could not upload video to LinkedIn: #{@redacts_bearer_token.redact(e.message)}"
    end
  end
end
