'use client';

import { useEffect, useRef } from 'react';
import './why-errol.css';

const reasons = [
  {
    title: 'Replies move automatically.',
    text: 'Errol carries each finished reply to the other app and presses Send.',
  },
  {
    title: 'Keep the apps you know.',
    text: 'Your projects, memory, and connected tools stay with each app.',
  },
  {
    title: 'You set the direction.',
    text: 'Add a nudge along the way. Stop whenever you have what you need.',
  },
];

export function WhyErrol() {
  const sectionRef = useRef<HTMLElement>(null);

  useEffect(() => {
    const section = sectionRef.current;
    if (!section) return;

    // A single, quiet pass over the reasons. Pause it off screen or in a
    // hidden tab; CSS disables it entirely for reduced-motion visitors.
    let visible = false;
    const sync = () => {
      section.dataset.visible = String(visible && !document.hidden);
    };
    const observer = new IntersectionObserver(
      ([entry]) => {
        visible = entry.intersectionRatio >= 0.35;
        sync();
      },
      { threshold: 0.35 },
    );
    observer.observe(section);
    document.addEventListener('visibilitychange', sync);
    return () => {
      observer.disconnect();
      document.removeEventListener('visibilitychange', sync);
    };
  }, []);

  return (
    <section
      ref={sectionRef}
      id="why"
      className="why shell"
      aria-labelledby="why-title"
    >
      <div className="why-layout">
        <div className="why-heading">
          <h2 id="why-title">Why Errol?</h2>
          <p className="why-promise">
            More perspective.
            <br />
            <span>Less copy-paste.</span>
          </p>
          <p className="why-lead">
            Let ChatGPT and Claude build on each other’s ideas, in the apps you
            already use.
          </p>
          <p className="why-note">
            Runs on your Mac. No API keys. No Errol account.
          </p>
        </div>
        {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles -- Preserve list semantics in Safari with list-style: none. */}
        <ul className="why-reasons" role="list">
          {reasons.map(({ title, text }, index) => (
            <li
              key={title}
              style={{ '--reason': index } as React.CSSProperties}
            >
              <span className="why-number" aria-hidden="true">
                {String(index + 1).padStart(2, '0')}
              </span>
              <div>
                <h3>{title}</h3>
                <p>{text}</p>
              </div>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
