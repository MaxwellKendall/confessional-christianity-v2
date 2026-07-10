import { marked } from 'marked';

// Long-form markdown (reflections, teaching notes) rendered at build time.
// The content is first-party authored files in this repo, so raw HTML
// injection is acceptable; styling comes from .reading-prose in globals.css.
export function Markdown({ source }: { source: string }) {
  const html = marked.parse(source, { async: false });
  return (
    <div
      className="reading-prose"
      dangerouslySetInnerHTML={{ __html: html }}
    />
  );
}
