import { ArrowUpRight } from 'lucide-react';
import { siteConfig } from '@/lib/site-config';
import { Brand } from './brand';
import './site-footer.css';
export function SiteFooter() {
  return (
    <footer className="site-footer shell">
      <Brand />
      <p>A quiet courier between two bright minds.</p>
      <a
        className="text-link"
        href={siteConfig.repositoryUrl}
        target="_blank"
        rel="noopener noreferrer"
      >
        Made in the open <ArrowUpRight size={15} />
      </a>
    </footer>
  );
}
