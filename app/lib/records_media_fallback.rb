class RecordsMediaFallback
  KEY = "media_fallback"

  def record(crosspost, reason)
    crosspost.update!(metadata: crosspost.metadata.merge(
      KEY => {"reason" => reason, "at" => Now.time.iso8601}
    ))
    Rails.logger.warn("Crosspost #{crosspost.id} posted without media: #{reason}")
  end
end
