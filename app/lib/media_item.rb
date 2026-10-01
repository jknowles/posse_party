MediaItem = Struct.new(:type, :url, :poster_url, :alt, :presentation, :mime, :width, :height, :bytes, keyword_init: true) do
  def image?
    type == "image"
  end

  def video?
    type == "video"
  end
end
