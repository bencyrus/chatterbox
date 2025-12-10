function MagicLinkPage() {
  return (
    <div className="p-8 max-w-2xl mx-auto text-center">
      <img
        src="https://storage.googleapis.com/chatterbox-public-assets/public-chatterbox-logo-color-bg.png"
        alt="Chatterbox app icon"
        className="w-20 h-20 mx-auto mb-6 rounded-2xl shadow-md"
      />
      <h1 className="text-3xl font-bold mb-4">Sign in to Chatterbox</h1>
      <p className="mb-4">
        This sign-in link is meant to open the Chatterbox app on your device.
        If the app didn&apos;t open automatically, you can close this tab and
        return to the app to continue.
      </p>
      <p className="mb-4">
        If you&apos;re having trouble signing in, try requesting a new magic link
        from within the app. Links are single-use and expire after a short
        period for your security.
      </p>
      <p className="text-sm text-gray-600">
        Still stuck? You can reply to the email or SMS that contained this
        link, or contact support using the details in the app.
      </p>
    </div>
  )
}

export default MagicLinkPage
