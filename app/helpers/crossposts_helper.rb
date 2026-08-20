module CrosspostsHelper
  def crosspost_preview_text(preview)
    if preview.failure?
      "[Error generating preview: #{preview.error.message}]\n\n#{preview.error.backtrace.join("\n")}"
    else
      preview.data || ComposesCrosspostPreview::SKIPPED
    end
  end
end
