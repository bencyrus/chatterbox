import { useEffect, useState } from 'react'
import Markdown from 'react-markdown'

function PrivacyPage() {
  const [content, setContent] = useState<string>('')

  useEffect(() => {
    fetch('/src/content/privacy-policy.md')
      .then((response) => response.text())
      .then((text) => setContent(text))
      .catch((error) => console.error('Error loading privacy policy:', error))
  }, [])

  return (
    <div className="max-w-4xl mx-auto p-8">
      <article className="prose prose-slate lg:prose-lg">
        <Markdown>{content}</Markdown>
      </article>
    </div>
  )
}

export default PrivacyPage

