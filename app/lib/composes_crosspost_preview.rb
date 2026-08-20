class ComposesCrosspostPreview
  SKIPPED = "[Would be skipped - syndication disabled]".freeze

  def initialize
    @matches_platform_api = PublishesCrosspost::MatchesPlatformApi.new
    @munges_config = PublishesCrosspost::MungesConfig.new
    @composes_crosspost_content = PublishesCrosspost::ComposesCrosspostContent.new
  end

  # Returns Result whose data is the exact content that would be posted, or nil
  # when the crosspost wouldn't be syndicated at all. Failures carry the error so
  # callers can show it without mistaking it for postable content.
  def compose(crosspost)
    api = @matches_platform_api.match(crosspost.account)
    crosspost_config = @munges_config.munge(crosspost, api.default_crosspost_options)

    Result.success(
      (@composes_crosspost_content.compose(crosspost_config, api.post_constraints).string if crosspost_config.syndicate)
    )
  rescue => e
    Result.failure(e)
  end
end
