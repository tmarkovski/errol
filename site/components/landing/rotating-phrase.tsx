'use client';

import { Fragment, useCallback, useEffect, useReducer, useRef } from 'react';
import './rotating-phrase.css';

/**
 * What the two can do together, finishing "Let ChatGPT and Claude …". The
 * first is the one the page loads with, and the one screen readers hear.
 */
const PHRASES = [
  'talk it out',
  'debate it',
  'compare notes',
  'review your code',
  'brainstorm',
  'pressure-test it',
];
/** How long each phrase stays, and how long the first waits for the headline's entrance. */
const HOLD = 2600;
const FIRST = 3400;

type Turn = { at: number; from: number; turns: number };
const next = (turn: Turn): Turn => ({
  at: (turn.at + 1) % PHRASES.length,
  from: turn.at,
  turns: turn.turns + 1,
});

/**
 * The headline's last line: a phrase that changes every few seconds, word by
 * word, with the gold period gliding to the end of each new one. It waits
 * while the headline is off screen or the tab is hidden, and never changes
 * for a visitor who prefers reduced motion.
 */
export function RotatingPhrase() {
  const [turn, advance] = useReducer(next, { at: 0, from: -1, turns: 0 });
  const boxRef = useRef<HTMLSpanElement>(null);
  const phraseRefs = useRef<(HTMLSpanElement | null)[]>([]);
  const atRef = useRef(0);

  // The box takes the width of the phrase showing, so the period sits right
  // after it and glides as the width changes.
  const fit = useCallback(() => {
    const box = boxRef.current;
    const phrase = phraseRefs.current[atRef.current];
    if (box && phrase)
      box.style.width = `${phrase.getBoundingClientRect().width}px`;
  }, []);

  useEffect(() => {
    atRef.current = turn.at;
    fit();
  }, [turn.at, fit]);

  useEffect(() => {
    const box = boxRef.current;
    if (!box) return;
    // From here on every phrase takes part in the layout, and the box is sized
    // to the one showing. Fonts arriving and the window resizing both change
    // the widths.
    box.dataset.ready = 'true';
    fit();
    const observer = new ResizeObserver(fit);
    for (const phrase of phraseRefs.current)
      if (phrase) observer.observe(phrase);
    return () => observer.disconnect();
  }, [fit]);

  useEffect(() => {
    const box = boxRef.current;
    if (!box) return;
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
    let visible = false;
    let started = false;
    let timer = 0;
    const sync = () => {
      window.clearTimeout(timer);
      if (!visible || document.hidden || reduced.matches) return;
      timer = window.setTimeout(
        () => {
          started = true;
          advance();
          sync();
        },
        started ? HOLD : FIRST,
      );
    };
    const observer = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      sync();
    });
    observer.observe(box);
    document.addEventListener('visibilitychange', sync);
    reduced.addEventListener('change', sync);
    return () => {
      window.clearTimeout(timer);
      observer.disconnect();
      document.removeEventListener('visibilitychange', sync);
      reduced.removeEventListener('change', sync);
    };
  }, []);

  return (
    <>
      <span className="sr-only">{PHRASES[0]}.</span>
      <span ref={boxRef} className="turn" aria-hidden="true">
        {PHRASES.map((phrase, i) => (
          <span
            key={phrase}
            ref={(el) => {
              phraseRefs.current[i] = el;
            }}
            className="turn-phrase"
            data-state={i === turn.at ? 'in' : i === turn.from ? 'out' : 'idle'}
          >
            {phrase.split(' ').map((word, j) => (
              <Fragment key={j}>
                {j > 0 && ' '}
                <span style={{ '--word': j } as React.CSSProperties}>
                  {word}
                </span>
              </Fragment>
            ))}
          </span>
        ))}
      </span>
      {/* Remounted on each change so its hop plays again; the first landing is the headline's own. */}
      <span
        key={turn.turns}
        className="hero-dot"
        data-hop={turn.turns > 0}
        aria-hidden="true"
      >
        .
      </span>
    </>
  );
}
