import { ArrowUpRight } from 'lucide-react';
import { siteConfig } from '@/lib/site-config';
import { Brand } from './brand';
import { DownloadLink } from './download-link';
import './site-header.css';

export function SiteHeader() {
  return (
    <header className="site-header">
      <div className="site-header-bar shell">
        <Brand />
        <nav aria-label="Main navigation">
          <a
            className="nav-link"
            href={siteConfig.repositoryUrl}
            target="_blank"
            rel="noopener noreferrer"
          >
            GitHub <ArrowUpRight size={14} />
          </a>
          <DownloadLink small />
        </nav>
      </div>
    </header>
  );
}
