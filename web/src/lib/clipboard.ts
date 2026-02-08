/**
 * Clipboard utilities
 */

/**
 * Copy plain text to the clipboard.
 * Uses the async Clipboard API when available, with a safe fallback.
 */
export async function copyTextToClipboard(text: string): Promise<boolean> {
  const value = text ?? '';
  if (!value.trim()) return false;

  // Modern async clipboard (requires secure context)
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(value);
      return true;
    }
  } catch {
    // fall through to fallback
  }

  // Fallback: hidden textarea + execCommand
  try {
    const el = document.createElement('textarea');
    el.value = value;
    el.setAttribute('readonly', '');
    el.style.position = 'fixed';
    el.style.top = '-9999px';
    el.style.left = '-9999px';
    document.body.appendChild(el);
    el.focus();
    el.select();
    const ok = document.execCommand('copy');
    document.body.removeChild(el);
    return ok;
  } catch {
    return false;
  }
}

