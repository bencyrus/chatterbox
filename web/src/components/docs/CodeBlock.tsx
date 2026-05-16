import { useCallback, useState } from 'react';
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter';
import { oneDark } from 'react-syntax-highlighter/dist/esm/styles/prism';
import { HiOutlineCheck, HiOutlineClipboard } from 'react-icons/hi2';
import { copyTextToClipboard } from '../../lib/clipboard';
import { cn } from '../../lib/cn';

const LANGUAGE_ALIASES: Record<string, string> = {
  sh: 'bash',
  shell: 'bash',
  yml: 'yaml',
  ts: 'typescript',
  js: 'javascript',
};

interface CodeBlockProps {
  language?: string;
  children: string;
}

export function CodeBlock({ language, children }: CodeBlockProps) {
  const [copied, setCopied] = useState(false);
  const lang = language ? (LANGUAGE_ALIASES[language] ?? language) : undefined;
  const code = children.replace(/\n$/, '');

  const handleCopy = useCallback(async () => {
    const ok = await copyTextToClipboard(code);
    if (ok) {
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1500);
    }
  }, [code]);

  return (
    <div className="group relative my-6 overflow-hidden rounded-lg border border-slate-800 bg-[#282c34]">
      <div className="flex items-center justify-between border-b border-slate-700/80 bg-[#21252b] px-4 py-2">
        <span className="font-mono text-caption uppercase tracking-wide text-slate-400">
          {lang ?? 'text'}
        </span>
        <button
          type="button"
          onClick={() => void handleCopy()}
          className={cn(
            'inline-flex items-center gap-1.5 rounded px-2 py-1 text-caption text-slate-300',
            'hover:bg-slate-700/60 transition-colors'
          )}
          aria-label="Copy code"
        >
          {copied ? (
            <HiOutlineCheck className="h-3.5 w-3.5" />
          ) : (
            <HiOutlineClipboard className="h-3.5 w-3.5" />
          )}
          {copied ? 'Copied' : 'Copy'}
        </button>
      </div>
      <SyntaxHighlighter
        language={lang ?? 'text'}
        style={oneDark}
        customStyle={{
          margin: 0,
          padding: '1rem 1.25rem',
          background: 'transparent',
          fontSize: '0.8125rem',
          lineHeight: 1.6,
        }}
        codeTagProps={{
          className: 'font-mono',
        }}
      >
        {code}
      </SyntaxHighlighter>
    </div>
  );
}
