class SelectsMedia
  Selection = Struct.new(:images, :video, :dropped, keyword_init: true) do
    def empty?
      images.empty? && video.nil?
    end
  end

  def select(items, max_images:)
    video = items.find(&:video?)
    if video
      Selection.new(images: [], video:, dropped: items.size - 1)
    else
      images = items.select(&:image?)
      Selection.new(images: images.take(max_images), video: nil, dropped: items.size - [images.size, max_images].min)
    end
  end
end
