import { ArrowDownToLine, ArrowUpRight } from 'lucide-react';
import { siteConfig } from '@/lib/site-config';
import './shared.css';

export function DownloadLink({ small = false }: { small?: boolean }) {
  return (
    <a
      className={`download-button ${small ? 'download-small' : ''}`}
      href={siteConfig.downloadUrl}
      target="_blank"
      rel="noopener noreferrer"
    >
      <ArrowDownToLine size={small ? 15 : 18} strokeWidth={1.8} />
      <span>{small ? 'Download' : 'Download for Mac'}</span>
      {!small && <ArrowUpRight className="button-arrow" size={17} />}
    </a>
  );
}
