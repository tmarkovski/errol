'use client';

import { memo, useEffect, useRef, useState } from 'react';
import {
  ArrowUp,
  BatteryFull,
  Copy,
  MousePointer2,
  PanelLeft,
  Pause,
  Play,
  RotateCcw,
  Wifi,
} from 'lucide-react';
import { Field } from '@base-ui/react/field';
import { Slider } from '@/components/ui/slider';
import { DEMO_DURATION, INTRO_TEXT, mountErrolDemo } from './timeline';
import './hero-demo.css';

function AppIcon({ app }: { app: 'chatgpt' | 'claude' }) {
  return <img className="ef-app-icon" src={`/app-icons/${app}.png`} alt="" />;
}

// Keep the cinematic scene outside React's playback updates. The timeline owns
// its transient text and transforms; React owns the accessible player controls.
const Scene = memo(function Scene() {
  return (
    <div className="ef-device">
      <div
        className="ef-screen"
        aria-label="Simulated Mac screen. Errol starts and steers a debate between ChatGPT and Claude."
      >
        <div className="ef-intro" aria-hidden="true">
          <div className="ef-intro-copy">
            <span className="ef-intro-measure">
              What if your AIs
              <br />
              could talk to each other?
            </span>
            <span className="ef-intro-typed">
              <span className="ef-intro-lead"></span>
              <br />
              <span className="ef-intro-question"></span>
              <span className="ef-intro-caret"></span>
            </span>
          </div>
        </div>
        <div className="ef-world" aria-hidden="true" inert>
          <div className="ef-wallpaper"></div>
          <div className="ef-menubar">
            <span>●</span>
            <span className="ef-front-app">Errol</span>
            <span>File</span>
            <span>Edit</span>
            <span>View</span>
            <div className="ef-right">
              <img src="/errol.svg" alt="" />
              <Wifi size={16} aria-hidden="true" />
              <BatteryFull size={16} aria-hidden="true" />
              <span>Sat 9:41</span>
            </div>
          </div>
          <div className="ef-window ef-chat ef-gpt">
            <div className="ef-titlebar">
              <div className="ef-traffic">
                <b></b>
                <b></b>
                <b></b>
              </div>
              <AppIcon app="chatgpt" /> ChatGPT
              <span className="ef-title-icon">
                <PanelLeft size={16} aria-hidden="true" />
              </span>
            </div>
            <div className="ef-chat-main">
              <div className="ef-empty">
                <AppIcon app="chatgpt" />
                <span>What are we thinking about?</span>
              </div>
              <div className="ef-thread" hidden>
                <div className="ef-incoming"></div>
                <div className="ef-author">
                  <AppIcon app="chatgpt" />
                  ChatGPT
                </div>
                <p className="ef-response"></p>
                <button className="ef-copy" type="button">
                  <Copy size={16} aria-hidden="true" />
                  <span>Copy</span>
                </button>
              </div>
            </div>
            <div className="ef-chat-composer">
              <span className="ef-plus">+</span>
              <div className="ef-draft">Message ChatGPT</div>
              <button
                className="ef-send"
                type="button"
                aria-label="Send to ChatGPT"
              >
                <ArrowUp size={16} aria-hidden="true" />
              </button>
            </div>
          </div>
          <div className="ef-window ef-chat ef-claude">
            <div className="ef-titlebar">
              <div className="ef-traffic">
                <b></b>
                <b></b>
                <b></b>
              </div>
              <AppIcon app="claude" /> Claude
              <span className="ef-title-icon">
                <PanelLeft size={16} aria-hidden="true" />
              </span>
            </div>
            <div className="ef-chat-main">
              <div className="ef-empty">
                <AppIcon app="claude" />
                <span>Where should we begin?</span>
              </div>
              <div className="ef-thread" hidden>
                <div className="ef-incoming"></div>
                <div className="ef-author">
                  <AppIcon app="claude" />
                  Claude
                </div>
                <p className="ef-response"></p>
                <button className="ef-copy" type="button">
                  <Copy size={16} aria-hidden="true" />
                  <span>Copy</span>
                </button>
              </div>
            </div>
            <div className="ef-chat-composer">
              <span className="ef-plus">+</span>
              <div className="ef-draft">Message Claude</div>
              <button
                className="ef-send"
                type="button"
                aria-label="Send to Claude"
              >
                <ArrowUp size={16} aria-hidden="true" />
              </button>
            </div>
          </div>
          <div className="ef-window ef-errol">
            <div className="ef-errol-body">
              <div className="ef-titlebar">
                <div className="ef-traffic">
                  <b></b>
                  <b></b>
                  <b></b>
                </div>
                Errol<span className="ef-status">Ready</span>
              </div>
              <div className="ef-perches">
                <div className="ef-perch">
                  <span className="ef-avatar">
                    <AppIcon app="chatgpt" />
                  </span>
                  <span>ChatGPT</span>
                  <small className="ef-gpt-status">Ready</small>
                </div>
                <div className="ef-flight-path"></div>
                <span className="ef-bead"></span>
                <div className="ef-perch">
                  <span className="ef-avatar">
                    <AppIcon app="claude" />
                  </span>
                  <span>Claude</span>
                  <small className="ef-claude-status">Ready</small>
                </div>
              </div>
              <p className="ef-turn">Turn 0 · ChatGPT opens</p>
              <p className="ef-note-status"></p>
              <div className="ef-compose">
                <div className="ef-setup">
                  <div className="ef-shapes">
                    <span className="ef-mode-free ef-selected">Free chat</span>
                    <span>Brainstorm</span>
                    <span className="ef-mode-debate">Debate</span>
                  </div>
                  <p className="ef-topic"></p>
                </div>
                <div className="ef-running" hidden>
                  <div className="ef-run-context">Debate</div>
                  <div className="ef-steer-prompt" hidden></div>
                  <div className="ef-steer-hint">
                    Return to send and continue
                  </div>
                  <button
                    className="ef-primary ef-note-send"
                    type="button"
                    hidden
                  >
                    <ArrowUp size={16} aria-hidden="true" />
                    <span>Send note</span>
                  </button>
                </div>
                <div className="ef-pause-status" hidden>
                  <span className="ef-pause-context">Debate</span>
                  <span className="ef-pause-hint">
                    The conversation is running
                  </span>
                </div>
                <button
                  className="ef-play"
                  type="button"
                  aria-label="Start conversation"
                >
                  <span className="ef-pause-face">
                    <span className="ef-play-symbol">
                      <Play size={16} aria-hidden="true" />
                    </span>
                    <span className="ef-pause-symbol">
                      <Pause size={20} aria-hidden="true" />
                    </span>
                    <span className="ef-pause-label">
                      <span className="ef-pause-label-text">
                        Pause to steer
                      </span>
                    </span>
                  </span>
                </button>
              </div>
            </div>
          </div>
          <svg
            className="ef-courier-tail"
            viewBox="0 0 1200 750"
            aria-hidden="true"
          >
            <defs>
              <linearGradient
                id="ef-courier-tail-gradient"
                gradientUnits="userSpaceOnUse"
              >
                <stop offset="0" stopColor="var(--ef-accent)" stopOpacity="0" />
                <stop
                  offset="0.45"
                  stopColor="var(--ef-accent)"
                  stopOpacity="0.35"
                />
                <stop
                  offset="1"
                  stopColor="var(--ef-accent)"
                  stopOpacity="0.9"
                />
              </linearGradient>
            </defs>
            <path className="ef-courier-tail-glow" />
            <path className="ef-courier-tail-core" />
          </svg>
          <div className="ef-click"></div>
          <div className="ef-pointer">
            <MousePointer2 size={16} aria-hidden="true" />
            <span>You</span>
          </div>
          <div className="ef-courier" aria-hidden="true">
            <span className="ef-courier-pulse"></span>
            <span className="ef-courier-mark">
              <img src="/errol.svg" alt="" />
            </span>
          </div>
        </div>
        <div className="ef-ending">
          <img src="/errol.svg" alt="Errol" />
          <strong>Let your AIs talk.</strong>
          <span>You can step in whenever you want.</span>
        </div>
      </div>
    </div>
  );
});

type Playback = {
  time: number;
  playing: boolean;
  caption: string;
  chapter: string;
};
type DemoController = ReturnType<typeof mountErrolDemo>;

export function HeroDemo({
  onPlayingChange,
}: {
  onPlayingChange?: (playing: boolean) => void;
}) {
  const root = useRef<HTMLDivElement>(null);
  const controller = useRef<DemoController | null>(null);
  const [playback, setPlayback] = useState<Playback>({
    time: 0,
    playing: true,
    caption: INTRO_TEXT,
    chapter: '01',
  });

  useEffect(() => {
    if (!root.current) return;
    const demo = mountErrolDemo(root.current, setPlayback);
    controller.current = demo;
    return () => {
      demo.dispose();
      controller.current = null;
    };
  }, []);

  useEffect(() => {
    onPlayingChange?.(playback.playing);
  }, [onPlayingChange, playback.playing]);

  return (
    <div
      id="errol-hero-film"
      ref={root}
      aria-label="Watch how Errol works"
      aria-describedby="errol-demo-description"
    >
      <Scene />
      <div className="ef-caption" aria-live="polite">
        <span>{playback.caption}</span>
        <small>{playback.chapter} / 04</small>
      </div>
      <div className="ef-controls" role="group" aria-label="Demo playback">
        <button
          className="ef-control"
          type="button"
          onClick={() => controller.current?.toggle()}
          aria-label={
            playback.playing
              ? 'Pause demo'
              : playback.time >= DEMO_DURATION
                ? 'Replay demo'
                : 'Play demo'
          }
        >
          {playback.playing ? <Pause size={17} /> : <Play size={17} />}
        </button>
        <button
          className="ef-control"
          type="button"
          onClick={() => controller.current?.replay()}
          aria-label="Restart demo"
        >
          <RotateCcw size={17} />
        </button>
        <Field.Root className="ef-seek-field">
          <Field.Label className="sr-only">Demo time in seconds</Field.Label>
          <Slider
            className="ef-seek"
            min={0}
            max={DEMO_DURATION}
            step={0.1}
            value={[playback.time]}
            onValueChange={(value) =>
              controller.current?.seek(Array.isArray(value) ? value[0] : value)
            }
          />
        </Field.Root>
        <span className="ef-clock">
          0:{String(Math.floor(playback.time)).padStart(2, '0')} / 0:
          {DEMO_DURATION}
        </span>
      </div>
      <p className="ef-disclosure" id="errol-demo-description">
        A simulated conversation with simplified interfaces.
      </p>
      <noscript>
        <p>
          Errol automatically carries replies back and forth between ChatGPT and
          Claude. Start with a topic and let them continue. You can pause to add
          a steering note whenever you want.
        </p>
      </noscript>
    </div>
  );
}
