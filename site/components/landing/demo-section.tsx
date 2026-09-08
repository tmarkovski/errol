import { HeroDemo } from '@/components/hero-demo';
import './demo-section.css';

/** The walkthrough on its own slide, sized so the whole film fits one viewport. */
export function DemoSection({
  onPlayingChange,
}: {
  onPlayingChange: (playing: boolean) => void;
}) {
  return (
    <section
      id="conversation"
      className="demo-section slide shell"
      aria-label="Watch a conversation"
    >
      <div className="demo-frame">
        <HeroDemo onPlayingChange={onPlayingChange} />
      </div>
    </section>
  );
}
