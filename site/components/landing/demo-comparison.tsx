'use client';

import { useCallback, useEffect, useState } from 'react';
import { HeroDemo } from '@/components/hero-demo';
import { DEMO_DURATION } from '@/components/hero-demo/timeline';
import { ShortDemo } from '@/components/short-demo';
import './demo-comparison.css';

export function DemoComparison({
  onPlayingChange,
}: {
  onPlayingChange: (playing: boolean) => void;
}) {
  const [quickPlaying, setQuickPlaying] = useState(false);
  const [fullPlaying, setFullPlaying] = useState(true);
  const onQuickPlayingChange = useCallback(
    (playing: boolean) => setQuickPlaying(playing),
    [],
  );
  const onFullPlayingChange = useCallback(
    (playing: boolean) => setFullPlaying(playing),
    [],
  );

  useEffect(() => {
    onPlayingChange(quickPlaying || fullPlaying);
  }, [quickPlaying, fullPlaying, onPlayingChange]);

  return (
    <div className="demo-comparison">
      <section className="demo-variant" aria-labelledby="quick-demo-title">
        <div className="demo-variant-heading">
          <h2 id="quick-demo-title">Quick demo</h2>
          <span>10 seconds</span>
        </div>
        <ShortDemo onPlayingChange={onQuickPlayingChange} />
      </section>
      <section className="demo-variant" aria-labelledby="full-demo-title">
        <div className="demo-variant-heading">
          <h2 id="full-demo-title">Full walkthrough</h2>
          <span>{DEMO_DURATION} seconds</span>
        </div>
        <HeroDemo onPlayingChange={onFullPlayingChange} />
      </section>
    </div>
  );
}
