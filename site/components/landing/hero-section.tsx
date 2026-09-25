import { siteConfig } from '@/lib/site-config';
import { DownloadLink } from './download-link';
import './hero-section.css';

export function HeroSection() {
  return (
    <section className="hero shell" aria-labelledby="hero-title">
      <div className="hero-glow" aria-hidden="true" />
      <p className="hero-pill">
        <span className="status-dot" /> Free <span className="pill-sep">·</span>{' '}
        Open source <span className="pill-sep">·</span> For Mac
      </p>
      <h1 id="hero-title">
        Let ChatGPT and Claude <br />
        talk it out<span className="hero-dot">.</span>
      </h1>
      <p className="hero-description">
        Errol carries every reply between the ChatGPT and Claude apps on your
        Mac. Give them a topic, and step in whenever you like.
      </p>
      <div className="hero-actions">
        <DownloadLink />
      </div>
      <p className="download-note">
        macOS {siteConfig.minimumMacOS} or later <span>·</span> No API keys{' '}
        <span>·</span> No account
      </p>
      {/* The courier dot from the film, carrying the reader down to it. */}
      <div className="courier" aria-hidden="true">
        <span />
      </div>
    </section>
  );
}
