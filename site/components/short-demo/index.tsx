'use client';

import { useEffect, useRef, useState } from 'react';
import './short-demo.css';

export function ShortDemo({
  onPlayingChange,
}: {
  onPlayingChange: (playing: boolean) => void;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
    let visible = false;
    let started = false;
    const sync = () => {
      if (!visible || document.hidden || reduced.matches) {
        video.pause();
      } else if (!started) {
        // Play once when the film comes into view. Native controls handle
        // replay, seeking and fullscreen; scrolling back never overrides Pause.
        started = true;
        void video.play().catch(() => {
          // Autoplay can be unavailable; the poster and Play remain usable.
        });
      }
    };
    const observer = new IntersectionObserver(
      ([entry]) => {
        visible = entry.isIntersecting && entry.intersectionRatio >= 0.25;
        sync();
      },
      { threshold: 0.25 },
    );
    observer.observe(video);
    document.addEventListener('visibilitychange', sync);
    reduced.addEventListener('change', sync);
    return () => {
      observer.disconnect();
      document.removeEventListener('visibilitychange', sync);
      reduced.removeEventListener('change', sync);
      video.pause();
    };
  }, []);

  return (
    <div className="short-demo">
      <div className="short-demo-frame">
        <video
          ref={videoRef}
          controls
          muted
          playsInline
          preload="metadata"
          src="/demos/errol-quick-demo.mp4"
          width={1280}
          height={800}
          poster="/demos/errol-quick-demo-poster.png"
          aria-label="Errol in ten seconds"
          aria-describedby="short-demo-description"
          onPlay={() => onPlayingChange(true)}
          onPause={() => onPlayingChange(false)}
          onEnded={() => onPlayingChange(false)}
          onError={() => {
            setFailed(true);
            onPlayingChange(false);
          }}
        >
          Your browser cannot play this video.{' '}
          <a href="/demos/errol-quick-demo.mp4" download>
            Download the short demo.
          </a>
        </video>
      </div>
      {failed && (
        <output className="short-demo-error">
          The demo couldn’t load.{' '}
          <a href="/demos/errol-quick-demo.mp4" download>
            Download the video.
          </a>
        </output>
      )}
      <p className="short-demo-description" id="short-demo-description">
        A prompt starts the conversation. Replies travel between the apps, and
        your steering note joins the next handoff.
        <span className="sr-only">
          {' '}
          Silent demonstration with simplified interfaces. Yellow dots carry the
          text; the receiving prompt glows when it arrives.
        </span>
      </p>
    </div>
  );
}
