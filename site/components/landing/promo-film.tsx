'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Pause, Play, RotateCcw, Volume2, VolumeX } from 'lucide-react';
import { Courier } from './courier';
import './promo-film.css';

/** Screens this tall get the 9:16 cut, whose captions stay legible at phone width. */
const TALL = '(max-aspect-ratio: 2/3)';
const FILM = {
  wide: '/demos/errol-promo-16x9',
  tall: '/demos/errol-promo-9x16',
};
/** Seeks stop this far short of the end, so a drag to the end holds the end card instead of ending. */
const END_MARGIN = 0.05;
const KEY_STEPS: Record<string, number> = {
  ArrowRight: 1,
  ArrowUp: 1,
  ArrowLeft: -1,
  ArrowDown: -1,
  PageUp: 5,
  PageDown: -5,
};

/**
 * `auto` plays whenever the film's section fills the screen; `paused` waits
 * for Play (the visitor paused it, prefers reduced motion, or autoplay was
 * refused); `ended` holds the end card, with Replay in the corner.
 */
type Mode = 'auto' | 'paused' | 'ended';

export function PromoFilm() {
  const sectionRef = useRef<HTMLElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const scrubRef = useRef<HTMLDivElement>(null);
  const trackRef = useRef<HTMLSpanElement>(null);
  const modeRef = useRef<Mode>('auto');
  // Set once the visitor asks for playback, which overrides reduced motion.
  const askedRef = useRef(false);
  const scrubbingRef = useRef(false);
  const syncRef = useRef<() => void>(() => {});
  const [mode, setModeState] = useState<Mode>('auto');
  const [playing, setPlaying] = useState(false);
  const [started, setStarted] = useState(false);
  const [scrubbing, setScrubbing] = useState(false);
  const [muted, setMuted] = useState(true);
  const [heard, setHeard] = useState(false);
  const [failed, setFailed] = useState(false);
  const [second, setSecond] = useState(0);
  const [length, setLength] = useState(0);

  const setMode = useCallback((next: Mode) => {
    modeRef.current = next;
    setModeState(next);
    syncRef.current();
  }, []);

  useEffect(() => {
    const section = sectionRef.current;
    const video = videoRef.current;
    if (!section || !video) return;
    // React sets `muted` as a property, so the server markup can't be trusted to carry it.
    video.muted = true;
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
    const tall = window.matchMedia(TALL);
    let inPlace = false;

    const sync = () => {
      if (modeRef.current === 'auto' && reduced.matches && !askedRef.current) {
        setMode('paused');
        return;
      }
      const run =
        inPlace &&
        !document.hidden &&
        modeRef.current === 'auto' &&
        !scrubbingRef.current;
      if (run) {
        if (video.paused)
          video.play().catch((error: DOMException) => {
            // Autoplay refused (Low Power Mode, browser policy): wait for Play.
            // An AbortError only means a pause overtook the play.
            if (error.name === 'NotAllowedError') setMode('paused');
          });
      } else if (!video.paused) {
        video.pause();
      }
    };
    syncRef.current = sync;

    // The root is the top 1% of the screen, so the section meets it only once
    // it has scrolled all the way in and snapped under the header. The root
    // starts a pixel down: with the next screen snapped in, the section's bottom
    // edge sits exactly on the screen's top edge, and an edge that only touches
    // the root still counts as intersecting.
    const observer = new IntersectionObserver(
      ([entry]) => {
        inPlace = entry.isIntersecting;
        sync();
      },
      { rootMargin: '-1px 0px -99% 0px' },
    );
    observer.observe(section);
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

  /** Moves the scrubber to the playhead; `--at` drives both the fill and the thumb. */
  const paint = useCallback(() => {
    const video = videoRef.current;
    const scrub = scrubRef.current;
    if (!video || !scrub) return;
    const at = video.duration ? video.currentTime / video.duration : 0;
    scrub.style.setProperty('--at', String(Math.min(1, at)));
  }, []);

  // The scrubber follows playback every frame, outside React.
  useEffect(() => {
    let frame = 0;
    const draw = () => {
      paint();
      if (playing) frame = requestAnimationFrame(draw);
    };
    draw();
    return () => cancelAnimationFrame(frame);
  }, [playing, paint]);

  const seek = (to: number) => {
    const video = videoRef.current;
    if (!video?.duration) return;
    video.currentTime = Math.max(0, Math.min(to, video.duration - END_MARGIN));
    paint();
  };

  /** After a seek from the end card, a point short of the end plays on from there. */
  const leaveEnd = () => {
    const video = videoRef.current;
    if (
      video &&
      modeRef.current === 'ended' &&
      video.currentTime < video.duration - END_MARGIN * 2
    )
      setMode('auto');
    else syncRef.current();
  };

  const scrubTo = (clientX: number) => {
    const video = videoRef.current;
    const track = trackRef.current;
    if (!video?.duration || !track) return;
    const box = track.getBoundingClientRect();
    seek(((clientX - box.left) / box.width) * video.duration);
  };

  const startScrub = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!event.isPrimary || event.button !== 0 || !videoRef.current?.duration)
      return;
    event.currentTarget.setPointerCapture(event.pointerId);
    // Holds the film still under the pointer; sync() plays it again on release.
    scrubbingRef.current = true;
    setScrubbing(true);
    syncRef.current();
    scrubTo(event.clientX);
  };

  const endScrub = () => {
    if (!scrubbingRef.current) return;
    scrubbingRef.current = false;
    setScrubbing(false);
    leaveEnd();
  };

  const scrubByKey = (event: React.KeyboardEvent<HTMLDivElement>) => {
    const video = videoRef.current;
    if (!video?.duration) return;
    const step = KEY_STEPS[event.key];
    if (event.key === 'Home') seek(0);
    else if (event.key === 'End') seek(video.duration);
    else if (step) seek(video.currentTime + step);
    else return;
    event.preventDefault();
    leaveEnd();
  };

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
    askedRef.current = true;
    setMuted(!unmuting);
    if (unmuting && !heard) {
      // The first time sound comes on, start over so the opening is heard.
      video.currentTime = 0;
      setHeard(true);
      setMode('auto');
    }
  };

  const playLabel =
    mode === 'auto' ? 'Pause' : mode === 'ended' ? 'Replay' : 'Play';
  const soundLabel = !muted ? 'Mute' : heard ? 'Unmute' : 'Play with sound';

  return (
    <section
      ref={sectionRef}
      id="film"
      className="film"
      aria-label="Errol in 23 seconds"
    >
      <div className="film-glow" aria-hidden="true" />
      <div
        className="film-frame"
        data-playing={playing}
        data-started={started}
        data-scrubbing={scrubbing}
        data-mode={mode}
      >
        <video
          ref={videoRef}
          muted
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
          onDurationChange={(event) => {
            setLength(Math.round(event.currentTarget.duration) || 0);
            paint();
          }}
          onTimeUpdate={(event) =>
            setSecond(Math.round(event.currentTarget.currentTime))
          }
          onSeeked={() => {
            // A seek before the first play still has to show its frame, not the poster.
            setStarted(true);
            paint();
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
              className="film-button film-play"
              data-invite={mode === 'ended'}
              aria-label={playLabel}
              title={playLabel}
              onClick={togglePlay}
            >
              {mode === 'auto' ? (
                <Pause size={15} fill="currentColor" strokeWidth={0} />
              ) : mode === 'ended' ? (
                <>
                  <RotateCcw size={15} strokeWidth={2.2} />
                  <span>Replay</span>
                </>
              ) : (
                <Play size={15} fill="currentColor" strokeWidth={0} />
              )}
            </button>
            {/* Drag anywhere along it to scrub; the film holds still until release. */}
            <div
              ref={scrubRef}
              className="film-scrub"
              // Not an <input type="range">: on iOS that drags only from its thumb, and this seeks from anywhere along the track.
              // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role
              role="slider"
              tabIndex={0}
              aria-label="Seek"
              aria-valuemin={0}
              aria-valuemax={length}
              aria-valuenow={second}
              aria-valuetext={`${second} of ${length} seconds`}
              onPointerDown={startScrub}
              onPointerMove={(event) => {
                if (scrubbingRef.current) scrubTo(event.clientX);
              }}
              onPointerUp={endScrub}
              onPointerCancel={endScrub}
              onLostPointerCapture={endScrub}
              onKeyDown={scrubByKey}
            >
              <span ref={trackRef} className="film-track">
                <span className="film-fill" />
                <span className="film-thumb" />
              </span>
            </div>
            <button
              type="button"
              className="film-button film-sound"
              data-invite={muted && !heard && mode !== 'ended'}
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
      {/* Carries the reader on to why Errol exists. */}
      <Courier />
    </section>
  );
}
