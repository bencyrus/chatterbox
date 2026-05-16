import { useEffect, useId, useRef, useState } from 'react';

let mermaidInitialized = false;

interface MermaidDiagramProps {
  chart: string;
}

export function MermaidDiagram({ chart }: MermaidDiagramProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const reactId = useId();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    let cancelled = false;

    async function render() {
      setError(null);
      el!.replaceChildren();

      try {
        const mermaid = (await import('mermaid')).default;

        if (!mermaidInitialized) {
          mermaid.initialize({
            startOnLoad: false,
            theme: 'neutral',
            securityLevel: 'strict',
            fontFamily: 'Inter, system-ui, sans-serif',
          });
          mermaidInitialized = true;
        }

        const id = `mermaid-${reactId.replace(/:/g, '')}`;
        const { svg } = await mermaid.render(id, chart.trim());
        if (cancelled) return;
        el!.innerHTML = svg;
      } catch (err) {
        if (cancelled) return;
        setError(err instanceof Error ? err.message : 'Failed to render diagram');
      }
    }

    void render();

    return () => {
      cancelled = true;
    };
  }, [chart, reactId]);

  if (error) {
    return (
      <div className="my-6 rounded-lg border border-error-200 bg-error-50 p-4 text-body-sm text-error-700">
        <p className="font-medium">Mermaid diagram error</p>
        <pre className="mt-2 overflow-x-auto text-caption text-error-600">{error}</pre>
      </div>
    );
  }

  return (
    <div
      ref={containerRef}
      className="my-8 flex min-h-[120px] justify-center overflow-x-auto rounded-lg border border-border-secondary bg-surface-secondary p-6 [&_svg]:max-w-full"
      aria-label="Diagram"
    />
  );
}
