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
        <div className="orbit orbit-one" />
        <div className="orbit orbit-two" />
        <div className="orbit orbit-three" />
        <div className="star star-one" />
        <div className="star star-two" />
        <div className="star star-three" />
      </div>
      <div className="hero-copy shell">
        <p className="eyebrow">
          <span className="status-dot" /> A LITTLE MAC APP FOR BIG CONVERSATIONS
        </p>
        <h1 id="hero-title">
          Good ideas
          <br />
          need <em>company.</em>
        </h1>
        <p className="hero-description">
          Let ChatGPT and Claude think together. Errol carries the conversation
          between the desktop apps you already use.
        </p>
        <div className="hero-actions">
          <DownloadLink />
          <a href="#conversation" className="text-link">
            See it in motion <ArrowDown size={16} />
          </a>
        </div>
        <p className="download-note">
          macOS {siteConfig.minimumMacOS}+ <span>·</span> No API keys needed
        </p>
      </div>
      <div id="conversation" className="conversation shell">
        <HeroDemo onPlayingChange={onPlayingChange} />
      </div>
    </section>
  );
}
