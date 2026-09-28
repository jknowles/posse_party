class CredentialRenewalMailer < ApplicationMailer
  def renew_linkedin
    send_renewal(
      account: params[:account],
      subject: "Renew your LinkedIn connection for POSSE Party"
    )
  end

  def renew_youtube
    send_renewal(
      account: params[:account],
      subject: "Renew your YouTube connection for POSSE Party"
    )
  end

  private

  # Links to the app rather than to the platform's OAuth URL: the app mints the
  # OAuth state when the link is clicked, so a link can never carry a stale one.
  def send_renewal(account:, subject:)
    @account = account
    @renewal_url = renew_credentials_account_url(@account)

    mail(to: @account.user.email, subject:)
  end
end
