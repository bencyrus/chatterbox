function RequestAccountRestorePage() {
  return (
    <div className="p-8 max-w-2xl mx-auto">
      <h1 className="text-3xl font-bold mb-4">Request Account Restore</h1>
      <p className="mb-4">
        Your Chatterbox account was previously deleted. If you&apos;d like to request
        that it be restored, please contact our support team.
      </p>
      <p className="mb-4">
        Send an email to <a href="mailto:realbencyrus@gmail.com" className="text-blue-600 underline">realbencyrus@gmail.com</a>{' '}
        from the address associated with your account. Include a brief note confirming that you
        want your account reactivated.
      </p>
      <p className="text-sm text-gray-600">
        If you no longer have access to that email address, please mention this in your message so
        we can verify ownership another way.
      </p>
    </div>
  )
}

export default RequestAccountRestorePage

