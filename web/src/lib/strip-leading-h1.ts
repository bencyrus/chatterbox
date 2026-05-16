/** Remove the first top-level heading so the page header can own the title */
export function stripLeadingH1(markdown: string): string {
  return markdown.replace(/^#\s+[^\n]+\n+/, '');
}
