import { ErrolSymbol } from './brand';
import { DownloadLink } from './download-link';
import './download-section.css';
export function DownloadSection() {
  return (
    <section className="closing shell" aria-labelledby="closing-title">
      <div className="closing-glow" aria-hidden="true" />
      <ErrolSymbol className="closing-symbol" />
      <p className="eyebrow">Good ideas need company</p>
      <h2 id="closing-title">
        Let it <em>fly.</em>
      </h2>
      <p>Give two assistants one good question.</p>
      <DownloadLink />
      <span className="download-note">
        Made for macOS. Built for the back-and-forth.
      </span>
    </section>
  );
}
