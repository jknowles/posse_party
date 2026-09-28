class MarksCrosspostPublished
  def mark(crosspost, url)
    if url.blank?
      Outcome.failure("A URL is required to mark a crosspost as published")
    elsif !/\Ahttps?:\/\/\S+\z/.match?(url)
      Outcome.failure("\"#{url}\" is not a valid http(s) URL")
    else
      crosspost.update!(status: "published", url: url, published_at: Now.time)
      Outcome.success("Crosspost marked as published")
    end
  end
end
