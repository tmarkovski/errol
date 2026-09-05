import { Owl } from './brand';
import { DownloadLink } from './download-link';
import './download-section.css';
export function DownloadSection() {
  return (
    <section className="closing shell" aria-labelledby="closing-title">
      <div className="closing-glow" aria-hidden="true" />
      <Owl className="closing-owl" />
      <p className="eyebrow">SOMETHING GOOD COULD COME OF THIS</p>
      <h2 id="closing-title">
        Let it <em>fly.</em>
      </h2>
      <p>Your next idea deserves a conversation.</p>
      <DownloadLink />
      <span className="download-note">
        Made for macOS. Built for the back-and-forth.
      </span>
    </section>
  );
}
