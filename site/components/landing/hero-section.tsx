import { ArrowDown } from 'lucide-react';
import { HeroDemo } from '@/components/hero-demo';
import { siteConfig } from '@/lib/site-config';
import { DownloadLink } from './download-link';
import './hero-section.css';
export function HeroSection({
  onPlayingChange,
}: {
  onPlayingChange: (playing: boolean) => void;
}) {
  return (
    <section className="hero" aria-labelledby="hero-title">
      <div className="atmosphere" aria-hidden="true">
        <div className="ambient-glow" />
        <div className="orbit" />
      </div>
      <div className="hero-copy shell">
        <p className="hero-pill">
          <span className="status-dot" /> Open source
          <span className="pill-sep">·</span> Lives in your menu bar
        </p>
        <h1 id="hero-title">
          Let ChatGPT and Claude <br />
          talk it out.
        </h1>
        <p className="hero-description">
          Errol carries messages between the ChatGPT and Claude apps already on
          your Mac. Give it a topic, watch them work through it, and step in
          whenever you like.
        </p>
        <div className="hero-actions">
          <DownloadLink />
          <a href="#conversation" className="text-link">
            Watch a conversation <ArrowDown size={16} />
          </a>
        </div>
        <p className="download-note">
          macOS {siteConfig.minimumMacOS} or later <span>·</span> Free and open
          source <span>·</span> No API keys, no account
        </p>
      </div>
      <div id="conversation" className="conversation shell">
        <HeroDemo onPlayingChange={onPlayingChange} />
      </div>
    </section>
  );
}
