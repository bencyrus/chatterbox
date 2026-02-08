import { useCallback, useState } from 'react';
import { HiOutlineClipboard, HiOutlineCheck } from 'react-icons/hi2';
import { cn } from '../../lib/cn';
import { copyTextToClipboard } from '../../lib/clipboard';
import { useToast } from '../../contexts/ToastContext';

interface CopyButtonProps {
  text: string;
  successMessage?: string;
  className?: string;
  size?: 'sm' | 'md';
}

export function CopyButton({
  text,
  successMessage = 'Copied',
  className,
  size = 'sm',
}: CopyButtonProps) {
  const { showToast } = useToast();
  const [didCopy, setDidCopy] = useState(false);

  const handleCopy = useCallback(async () => {
    const ok = await copyTextToClipboard(text);
    if (ok) {
      setDidCopy(true);
      window.setTimeout(() => setDidCopy(false), 1200);
      showToast(successMessage, 'success');
      return;
    }
    showToast('Copy failed', 'error');
  }, [showToast, successMessage, text]);

  const sizeClasses = size === 'md' ? 'px-3 py-2 text-label-md' : 'px-2 py-1.5 text-label-sm';

  return (
    <button
      type="button"
      onClick={handleCopy}
      className={cn(
        'inline-flex items-center gap-1.5 rounded-button',
        'bg-[#D9D9D9] text-text-primary hover:bg-[#CECECE]',
        'transition-colors',
        sizeClasses,
        className
      )}
      aria-label="Copy to clipboard"
    >
      {didCopy ? (
        <HiOutlineCheck className="w-4 h-4" />
      ) : (
        <HiOutlineClipboard className="w-4 h-4" />
      )}
      Copy
    </button>
  );
}

