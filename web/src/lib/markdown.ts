/**
 * Simple markdown-like parser matching iOS implementation
 */

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

export type ContentLineType = 'heading' | 'bullet' | 'text' | 'spacer';

export interface ContentLine {
  type: ContentLineType;
  content: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// PARSER
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Parse details text into structured lines
 * Matches iOS CueDetailView line-by-line parsing:
 * - Lines starting with "### " are headings
 * - Lines starting with "* " or "- " are bullets
 * - Empty lines are spacers
 * - Otherwise regular text
 */
export function parseContentLines(text: string): ContentLine[] {
  if (!text) return [];

  // Handle both actual newlines and escaped \n
  const normalized = text.replace(/\\n/g, '\n');
  const lines = normalized.split('\n');
  const result: ContentLine[] = [];

  for (const line of lines) {
    const trimmed = line.trim();

    if (trimmed.startsWith('### ')) {
      result.push({
        type: 'heading',
        content: trimmed.slice(4),
      });
    } else if (trimmed.startsWith('* ') || trimmed.startsWith('- ')) {
      result.push({
        type: 'bullet',
        content: trimmed.slice(2),
      });
    } else if (trimmed === '') {
      result.push({
        type: 'spacer',
        content: '',
      });
    } else {
      result.push({
        type: 'text',
        content: trimmed,
      });
    }
  }

  return result;
}
