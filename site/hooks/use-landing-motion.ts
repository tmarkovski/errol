'use client';

import { useEffect, useRef } from 'react';

/** Keeps decorative page motion in sync with the demo's playback control. */
export function useLandingMotion(motionPaused: boolean) {
  const pageRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const page = pageRef.current;
    if (!page) return;
    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
    const finePointer = window.matchMedia('(pointer: fine)');
    let frame = 0;
    let targetX = 0;
    let targetY = 0;
    let x = 0;
    let y = 0;
    const update = () => {
      x += (targetX - x) * 0.09;
      y += (targetY - y) * 0.09;
      page.style.setProperty('--pointer-x', `${x.toFixed(2)}px`);
      page.style.setProperty('--pointer-y', `${y.toFixed(2)}px`);
      page.style.setProperty(
        '--scroll-shift',
        `${Math.min(window.scrollY, 1400) * 0.16}px`,
      );
      frame =
        Math.abs(targetX - x) + Math.abs(targetY - y) > 0.08
          ? requestAnimationFrame(update)
          : 0;
    };
    const schedule = () => {
      if (!motionPaused && !reducedMotion.matches && !document.hidden && !frame)
        frame = requestAnimationFrame(update);
    };
    const pointerMove = (event: PointerEvent) => {
      if (!finePointer.matches) return;
      targetX = (event.clientX / window.innerWidth - 0.5) * 30;
      targetY = (event.clientY / window.innerHeight - 0.5) * 20;
      schedule();
    };
    const resetPointer = () => {
      targetX = 0;
      targetY = 0;
      schedule();
    };
    const resetMotion = () => {
      cancelAnimationFrame(frame);
      frame = 0;
      x = y = targetX = targetY = 0;
      for (const property of ['--pointer-x', '--pointer-y', '--scroll-shift'])
        page.style.removeProperty(property);
      schedule();
    };
    window.addEventListener('pointermove', pointerMove, { passive: true });
    window.addEventListener('scroll', schedule, { passive: true });
    document.addEventListener('pointerleave', resetPointer);
    reducedMotion.addEventListener('change', resetMotion);
    schedule();
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener('pointermove', pointerMove);
      window.removeEventListener('scroll', schedule);
      document.removeEventListener('pointerleave', resetPointer);
      reducedMotion.removeEventListener('change', resetMotion);
    };
  }, [motionPaused]);
  return pageRef;
}
