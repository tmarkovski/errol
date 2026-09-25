'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Pause, Play, RotateCcw, Volume2, VolumeX } from 'lucide-react';
import './promo-film.css';

/** Screens this tall get the 9:16 cut, whose captions stay legible at phone width. */
const TALL = '(max-aspect-ratio: 2/3)';
const FILM = {
  wide: '/demos/errol-promo-16x9',
  tall: '/demos/errol-promo-9x16',
};

/**
 * `auto` plays whenever the film is on screen; `paused` waits for Play (the
 * visitor paused it, prefers reduced motion, or autoplay was refused); `ended`
 * holds the end card after a play-through with sound.
 */
type Mode = 'auto' | 'paused' | 'ended';

export function PromoFilm() {
  const videoRef = useRef<HTMLVideoElement>(null);
  const barRef = useRef<HTMLSpanElement>(null);
  const modeRef = useRef<Mode>('auto');
  // Set once the visitor asks for playback, which overrides reduced motion.
  const askedRef = useRef(false);
  const syncRef = useRef<() => void>(() => {});
  const [mode, setModeState] = useState<Mode>('auto');
  const [playing, setPlaying] = useState(false);
  const [started, setStarted] = useState(false);
  const [muted, setMuted] = useState(true);
  const [heard, setHeard] = useState(false);
  const [failed, setFailed] = useState(false);

  const setMode = useCallback((next: Mode) => {
    modeRef.current = next;
    setModeState(next);
    syncRef.current();
  }, []);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    // React sets `muted` as a property, so the server markup can't be trusted to carry it.
    video.muted = true;
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
    const tall = window.matchMedia(TALL);
    let visible = false;

    const sync = () => {
      if (modeRef.current === 'auto' && reduced.matches && !askedRef.current) {
        setMode('paused');
        return;
      }
      if (visible && !document.hidden && modeRef.current === 'auto') {
        if (video.paused)
          video.play().catch(() => {
            // Autoplay refused (Low Power Mode, browser policy): wait for Play.
            if (video.paused) setMode('paused');
          });
      } else if (!video.paused) {
        video.pause();
      }
    };
    syncRef.current = sync;

    // Plays once a quarter of the film is on screen: enough to show its opening question.
    const observer = new IntersectionObserver(
      ([entry]) => {
        visible = entry.isIntersecting && entry.intersectionRatio >= 0.25;
        sync();
      },
      { threshold: [0, 0.25] },
    );
    observer.observe(video);
    // Rotating a phone picks the other cut: load() runs source selection again.
    const formatChanged = () => {
      const at = video.currentTime;
      video.load();
      video.currentTime = at;
      setStarted(false);
      sync();
    };
    document.addEventListener('visibilitychange', sync);
    reduced.addEventListener('change', sync);
    tall.addEventListener('change', formatChanged);
    return () => {
      observer.disconnect();
      document.removeEventListener('visibilitychange', sync);
      reduced.removeEventListener('change', sync);
      tall.removeEventListener('change', formatChanged);
      video.pause();
    };
  }, [setMode]);

  // The progress hairline follows playback every frame, outside React.
  useEffect(() => {
    const video = videoRef.current;
    const bar = barRef.current;
    if (!video || !bar) return;
    let frame = 0;
    const draw = () => {
      bar.style.transform = `scaleX(${video.duration ? video.currentTime / video.duration : 0})`;
      if (playing) frame = requestAnimationFrame(draw);
    };
    draw();
    return () => cancelAnimationFrame(frame);
  }, [playing]);

  const togglePlay = () => {
    const video = videoRef.current;
    if (!video) return;
    askedRef.current = true;
    if (mode === 'auto') {
      setMode('paused');
    } else {
      if (mode === 'ended') video.currentTime = 0;
      setMode('auto');
    }
  };

  const toggleSound = () => {
    const video = videoRef.current;
    if (!video) return;
    const unmuting = video.muted;
    video.muted = !unmuting;
    // With sound the film plays once and holds its end card; muted, it loops quietly.
    video.loop = !unmuting;
    askedRef.current = true;
    if (unmuting && !heard) {
      // The first time sound comes on, start over so the opening is heard.
      video.currentTime = 0;
      setHeard(true);
    }
    setMuted(!unmuting);
    if (unmuting && !heard) setMode('auto');
  };

  const playLabel =
    mode === 'auto' ? 'Pause' : mode === 'ended' ? 'Replay' : 'Play';
  const soundLabel = !muted ? 'Mute' : heard ? 'Unmute' : 'Play with sound';

  return (
    <section className="film" aria-label="Errol in 23 seconds">
      <div className="film-glow" aria-hidden="true" />
      <div
        className="film-frame"
        data-playing={playing}
        data-started={started}
        data-mode={mode}
      >
        <video
          ref={videoRef}
          muted
          loop
          playsInline
          preload="metadata"
          aria-describedby="film-description"
          onClick={togglePlay}
          onPlaying={() => {
            setPlaying(true);
            setStarted(true);
          }}
          onPause={() => setPlaying(false)}
          onEnded={() => {
            setPlaying(false);
            setMode('ended');
          }}
        >
          <source media={TALL} src={`${FILM.tall}.mp4`} type="video/mp4" />
          {/* Only the last source's error means neither cut could play. */}
          <source
            src={`${FILM.wide}.mp4`}
            type="video/mp4"
            onError={() => setFailed(true)}
          />
        </video>
        {/* The poster is the film's first frame in the matching cut, so playback starts without a jump. */}
        <picture className="film-poster">
          <source media={TALL} srcSet={`${FILM.tall}-poster.webp`} />
          <img
            src={`${FILM.wide}-poster.webp`}
            alt=""
            width={1920}
            height={1080}
          />
        </picture>
        <span className="film-cue" aria-hidden="true">
          <Play size={26} fill="currentColor" strokeWidth={0} />
        </span>
        {!failed && (
          <div className="film-controls">
            <button
              type="button"
              className="film-button"
              aria-label={playLabel}
              title={playLabel}
              onClick={togglePlay}
            >
              {mode === 'auto' ? (
                <Pause size={15} fill="currentColor" strokeWidth={0} />
              ) : mode === 'ended' ? (
                <RotateCcw size={15} strokeWidth={2.2} />
              ) : (
                <Play size={15} fill="currentColor" strokeWidth={0} />
              )}
            </button>
            <button
              type="button"
              className="film-button film-sound"
              data-invite={muted && !heard}
              onClick={toggleSound}
            >
              {muted ? (
                <VolumeX size={15} strokeWidth={2} />
              ) : (
                <Volume2 size={15} strokeWidth={2} />
              )}
              <span>{soundLabel}</span>
            </button>
          </div>
        )}
        <div className="film-progress" aria-hidden="true">
          <span ref={barRef} />
        </div>
      </div>
      {failed && (
        <output className="film-error">
          The film couldn’t load.{' '}
          <a href={`${FILM.wide}.mp4`}>Open it directly.</a>
        </output>
      )}
      <p className="sr-only" id="film-description">
        A 23-second film with music and sound effects. Someone copies replies
        between ChatGPT and Claude by hand. Then Errol drops from the menu bar,
        takes the topic “Price by seat or by usage?”, and carries each reply
        from one app to the other. A note typed during a pause joins the next
        reply. It ends on “Let your AIs talk.”
      </p>
    </section>
  );
}
