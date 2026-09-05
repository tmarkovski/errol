import { ArrowUpRight } from 'lucide-react';
import { siteConfig } from '@/lib/site-config';
import { Brand } from './brand';
import { DownloadLink } from './download-link';
import './site-header.css';
export function SiteHeader() {
  return (
    <header className="site-header shell">
      <Brand />
      <nav aria-label="Main navigation">
        <a className="nav-link" href="#how-it-works">
          How it works
        </a>
        <a
          className="nav-link github-link"
          href={siteConfig.repositoryUrl}
          target="_blank"
          rel="noopener noreferrer"
        >
          GitHub <ArrowUpRight size={14} />
        </a>
        <DownloadLink small />
      </nav>
    </header>
  );
}
