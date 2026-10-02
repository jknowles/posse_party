class RecordsMediaFallback
  KEY = "media_fallback"

  def record(crosspost, reason)
    crosspost.update!(metadata: crosspost.metadata.merge(
      KEY => {"reason" => reason, "at" => Now.time.iso8601}
    ))
    # A drop posts some of the media, a fallback none of it; this line is true of both
    Rails.logger.warn("Crosspost #{crosspost.id} did not post all of its media: #{reason}")
  end
end
