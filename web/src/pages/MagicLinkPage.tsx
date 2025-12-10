import { useLocation } from 'react-router-dom'

function MagicLinkPage() {
  const location = useLocation()
  const searchParams = new URLSearchParams(location.search)
  const token = searchParams.get('token') ?? ''

  // Use the same universal link URL as the email, so tapping the button
  // can re-attempt to open the app on iOS when association is working.
  const appUrl = token
    ? `https://chatterboxtalk.com/auth/magic?token=${encodeURIComponent(token)}`
    : `https://chatterboxtalk.com/auth/magic`

  const handleOpenApp = () => {
    window.location.href = appUrl
  }

  return (
    <div className="p-8 max-w-2xl mx-auto text-center">
      <img
        src="https://storage.googleapis.com/chatterbox-public-assets/public-chatterbox-logo-color-bg.png"
        alt="Chatterbox app icon"
        className="w-20 h-20 mx-auto mb-6 rounded-2xl shadow-md"
      />
      <h1 className="text-3xl font-bold mb-4">Sign in to Chatterbox</h1>

      <button
        type="button"
        onClick={handleOpenApp}
        className="inline-flex items-center justify-center px-6 py-3 mb-6 text-white bg-black rounded-full hover:bg-gray-900 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-black"
      >
        Open in Chatterbox app
      </button>

      <p className="mb-4">
        This sign-in link is meant to open the Chatterbox app on your device.
        If the app didn&apos;t open automatically, you can tap the button above,
        or return to the app to continue.
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
