require "test_helper"

class DownloadsMediaTest < ActiveSupport::TestCase
  PNG = "\x89PNG\r\n\x1A\n".b + ("\x00".b * 24)

  def setup
    @subject = DownloadsMedia.new
  end

  def test_downloads_the_bytes_and_prefers_the_items_mime
    stub_request(:get, "https://example.com/a.gif").to_return(status: 200, body: "GIF89a", headers: {"Content-Type" => "application/octet-stream"})

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/a.gif", mime: "image/gif"), max_bytes: 100)

    assert result.success?
    assert_equal "GIF89a".b, result.data.bytes
    assert_equal "image/gif", result.data.content_type
  end

  def test_takes_the_content_type_header_without_its_parameters
    stub_request(:get, "https://example.com/a.png").to_return(status: 200, body: PNG, headers: {"Content-Type" => "image/png; charset=binary"})

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/a.png"), max_bytes: 100)

    assert_equal "image/png", result.data.content_type
  end

  def test_sniffs_the_bytes_when_nothing_names_a_type
    stub_request(:get, "https://example.com/a").to_return(status: 200, body: PNG)

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/a"), max_bytes: 100)

    assert_equal "image/png", result.data.content_type
  end

  def test_sniffs_the_bytes_behind_a_generic_content_type
    stub_request(:get, "https://example.com/a.png").to_return(status: 200, body: PNG, headers: {"Content-Type" => "application/octet-stream"})

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/a.png"), max_bytes: 100)

    assert_equal "image/png", result.data.content_type
  end

  def test_follows_redirects
    stub_request(:get, "https://example.com/old.png").to_return(status: 301, headers: {"Location" => "https://cdn.example.com/a.png"})
    stub_request(:get, "https://cdn.example.com/a.png").to_return(status: 200, body: PNG, headers: {"Content-Type" => "image/png"})

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/old.png"), max_bytes: 100)

    assert_equal PNG, result.data.bytes
  end

  def test_refuses_an_item_that_declares_too_many_bytes_without_fetching_it
    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/big.png", bytes: 101), max_bytes: 100)

    assert result.failure?
    assert_equal "https://example.com/big.png is over the 100-byte limit", result.error
    assert_not_requested :get, "https://example.com/big.png"
  end

  def test_refuses_a_response_whose_length_is_over_the_limit
    stub_request(:get, "https://example.com/big.png").to_return(status: 200, body: "x" * 101, headers: {"Content-Length" => "101"})

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/big.png"), max_bytes: 100)

    assert_equal "https://example.com/big.png is over the 100-byte limit", result.error
  end

  def test_refuses_a_body_that_runs_past_the_limit
    stub_request(:get, "https://example.com/big.png").to_return(status: 200, body: "x" * 101)

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/big.png"), max_bytes: 100)

    assert_equal "https://example.com/big.png is over the 100-byte limit", result.error
  end

  def test_gives_up_on_a_download_that_runs_past_its_deadline
    Now.override!(Time.zone.parse("2026-10-06 10:00:00 UTC"))
    stub_request(:get, "https://example.com/slow.png").to_return {
      Now.override!(Time.zone.parse("2026-10-06 10:01:01 UTC"))
      {status: 200, body: PNG}
    }

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/slow.png"), max_bytes: 100)

    assert_equal "https://example.com/slow.png took longer than 60 seconds to download", result.error
  end

  def test_reports_an_http_error
    stub_request(:get, "https://example.com/gone.png").to_return(status: 404, body: "Not Found")

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/gone.png"), max_bytes: 100)

    assert_equal "Could not download https://example.com/gone.png: HTTP 404", result.error
  end

  def test_reports_a_connection_error
    stub_request(:get, "https://example.com/a.png").to_timeout

    result = @subject.download(MediaItem.new(type: "image", url: "https://example.com/a.png"), max_bytes: 100)

    assert_match %r{\ACould not download https://example.com/a.png: }, result.error
  end
end
