import { ArrowDownToLine } from 'lucide-react';
import { siteConfig } from '@/lib/site-config';
import './shared.css';

/** The Apple mark, drawn inline because lucide ships no brand icons. */
function AppleGlyph({ size }: { size: number }) {
  return (
    <svg
      className="apple-glyph"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      aria-hidden="true"
      focusable="false"
    >
      <path
        fill="currentColor"
        d="M16.4 12.6c0-2.5 2-3.7 2.1-3.7-1.2-1.7-3-1.9-3.6-2-1.5-.2-3 .9-3.8.9-.8 0-2-.9-3.3-.8-1.7 0-3.2 1-4.1 2.5-1.8 3-.5 7.6 1.3 10.1.9 1.2 1.9 2.6 3.2 2.6 1.3-.1 1.8-.8 3.3-.8 1.5 0 2 .8 3.4.8 1.4 0 2.3-1.2 3.1-2.5 1-1.4 1.4-2.8 1.4-2.9 0 0-2.7-1-2.7-4.2zM13.9 5.2c.7-.8 1.2-2 1-3.2-1 0-2.2.7-3 1.5-.6.7-1.2 1.9-1.1 3.1 1.2.1 2.3-.6 3.1-1.4z"
      />
    </svg>
  );
}

export function DownloadLink({ small = false }: { small?: boolean }) {
  return (
    <a
      className={`download-button ${small ? 'download-small' : ''}`}
      href={siteConfig.downloadUrl}
    >
      {small ? (
        <ArrowDownToLine size={15} strokeWidth={1.8} />
      ) : (
        <AppleGlyph size={17} />
      )}
      <span>{small ? 'Download' : 'Download for Mac'}</span>
    </a>
  );
}
