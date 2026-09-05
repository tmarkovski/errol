'use client';

import { useCallback, useState } from 'react';
import { SiteHeader } from '@/components/landing/site-header';
import { HeroSection } from '@/components/landing/hero-section';
import { HowItWorks } from '@/components/landing/how-it-works';
import { DownloadSection } from '@/components/landing/download-section';
import { SiteFooter } from '@/components/landing/site-footer';
import { useLandingMotion } from '@/hooks/use-landing-motion';

export default function Home() {
  const [motionPaused, setMotionPaused] = useState(false);
  const pageRef = useLandingMotion(motionPaused);
  const onPlayingChange = useCallback(
    (playing: boolean) => setMotionPaused(!playing),
    [],
  );

  return (
    <div className="landing" ref={pageRef} data-motion-paused={motionPaused}>
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <SiteHeader />
      <main id="main">
        <HeroSection onPlayingChange={onPlayingChange} />
        <HowItWorks />
        <DownloadSection />
      </main>
      <SiteFooter />
    </div>
  );
}
