'use client';

import { useEffect, useRef } from 'react';
import './harness-art.css';

/**
 * The courier carrying replies around a loop between the two apps: over the
 * top from ChatGPT to Claude, back underneath, waiting at each app while it
 * answers. The loop is symmetric, so the far app sits exactly halfway along it.
 */
const LOOP = 'M102 85 C194 3 366 3 458 85 C366 167 194 167 102 85';
/** One lap, out and back, in milliseconds. */
const LAP = 7500;
/** Where each app's reply lands, as a fraction of the lap. */
const ARRIVE = { claude: 0.44, chatgpt: 0.9 };
/** How far back in time the tail reaches: it stretches with speed and draws in behind the dot as it stops. */
const TAIL_MS = 420;
const TAIL_POINTS = 32;
/** Half the tail's width where it leaves the dot. */
const TAIL_WIDTH = 2.3;
/** Where the dot sits before the loop starts, and when motion is reduced: the top of the loop. */
const REST = { x: 280, y: 23.5 };
const REST_LAP = 0.27;

const ease = (x: number) => (x < 0.5 ? 4 * x ** 3 : 1 - (-2 * x + 2) ** 3 / 2);

/** How far round the loop the dot is, from 0 to 1, at a point in the lap. */
function along(lap: number) {
  if (lap < 0.1) return 0;
  if (lap < ARRIVE.claude) return 0.5 * ease((lap - 0.1) / 0.34);
  if (lap < 0.56) return 0.5;
  if (lap < ARRIVE.chatgpt) return 0.5 + 0.5 * ease((lap - 0.56) / 0.34);
  return 1;
}

/** The warm glow behind an app as a reply lands: quick to rise, slow to fade. */
function bloom(lap: number, arrival: number) {
  const since = (lap - arrival + 1) % 1;
  if (since < 0.03) return since / 0.03;
  return Math.max(0, 1 - (since - 0.03) / 0.3) ** 2;
}

function App({ x, src, glow }: { x: number; src: string; glow: string }) {
  return (
    <>
      <circle cx={x} cy={85} r={54} fill={`url(#${glow})`} />
      <image
        href={src}
        x={x - 42}
        y={43}
        width={84}
        height={84}
        filter="url(#harness-shadow)"
      />
    </>
  );
}

export function HarnessArt() {
  const svgRef = useRef<SVGSVGElement>(null);
  const loopRef = useRef<SVGPathElement>(null);
  const headRef = useRef<SVGGElement>(null);
  const tailRef = useRef<SVGPathElement>(null);
  const fadeRef = useRef<SVGLinearGradientElement>(null);
  const claudeRef = useRef<SVGCircleElement>(null);
  const chatgptRef = useRef<SVGCircleElement>(null);

  useEffect(() => {
    const svg = svgRef.current;
    const loop = loopRef.current;
    const head = headRef.current;
    const tail = tailRef.current;
    const fade = fadeRef.current;
    const claude = claudeRef.current;
    const chatgpt = chatgptRef.current;
    if (!svg || !loop || !head || !tail || !fade || !claude || !chatgpt) return;

    // Points evenly spaced along the loop, so a frame never has to measure it.
    const samples = 720;
    const total = loop.getTotalLength();
    const table = Array.from({ length: samples + 1 }, (_, i) =>
      loop.getPointAtLength((total * i) / samples),
    );
    const pointAt = (f: number) => {
      const at = Math.min(1, Math.max(0, f)) * samples;
      const i = Math.min(samples - 1, Math.floor(at));
      const a = table[i];
      const b = table[i + 1];
      const t = at - i;
      return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t };
    };

    const draw = (lap: number) => {
      // The tail runs through where the dot has been over the last TAIL_MS.
      const points = Array.from({ length: TAIL_POINTS + 1 }, (_, i) => {
        const then = (lap - (i / TAIL_POINTS) * (TAIL_MS / LAP) + 1) % 1;
        return pointAt(along(then));
      });
      const front = points[0];
      const end = points[TAIL_POINTS];
      head.setAttribute('transform', `translate(${front.x} ${front.y})`);
      claude.setAttribute('opacity', bloom(lap, ARRIVE.claude).toFixed(3));
      chatgpt.setAttribute('opacity', bloom(lap, ARRIVE.chatgpt).toFixed(3));

      if (Math.hypot(front.x - end.x, front.y - end.y) < 1) {
        tail.setAttribute('d', '');
        return;
      }
      // One outline that narrows to a point, filled with a fade from the dot
      // to nothing along the tail's own direction.
      const left: string[] = [];
      const right: string[] = [];
      let nx = 0;
      let ny = 0;
      points.forEach((p, i) => {
        const a = points[Math.max(0, i - 1)];
        const b = points[Math.min(TAIL_POINTS, i + 1)];
        const dx = a.x - b.x;
        const dy = a.y - b.y;
        const length = Math.hypot(dx, dy);
        if (length > 0.001) {
          nx = -dy / length;
          ny = dx / length;
        }
        const w = TAIL_WIDTH * (1 - i / TAIL_POINTS);
        left.push(`${(p.x + nx * w).toFixed(2)} ${(p.y + ny * w).toFixed(2)}`);
        right.unshift(
          `${(p.x - nx * w).toFixed(2)} ${(p.y - ny * w).toFixed(2)}`,
        );
      });
      tail.setAttribute('d', `M${left.join('L')}L${right.join('L')}Z`);
      fade.setAttribute('x1', String(front.x));
      fade.setAttribute('y1', String(front.y));
      fade.setAttribute('x2', String(end.x));
      fade.setAttribute('y2', String(end.y));
    };

    // Runs only while the art is on screen and motion is welcome, and picks
    // up where it stopped.
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
    let elapsed = REST_LAP * LAP;
    let last = 0;
    let frame = 0;
    let visible = false;
    const tick = (now: number) => {
      if (last) elapsed += now - last;
      last = now;
      draw((elapsed % LAP) / LAP);
      frame = requestAnimationFrame(tick);
    };
    const sync = () => {
      const run = visible && !reduced.matches;
      if (run && !frame) {
        last = 0;
        frame = requestAnimationFrame(tick);
      } else if (!run && frame) {
        cancelAnimationFrame(frame);
        frame = 0;
      }
      if (reduced.matches) draw(REST_LAP);
    };
    const observer = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      sync();
    });
    observer.observe(svg);
    reduced.addEventListener('change', sync);
    return () => {
      observer.disconnect();
      reduced.removeEventListener('change', sync);
      cancelAnimationFrame(frame);
    };
  }, []);

  return (
    <div className="harness">
      <svg
        ref={svgRef}
        viewBox="0 -20 560 210"
        preserveAspectRatio="xMidYMid slice"
        // An inline SVG takes role="img" to be read as one picture with this label; an <img> can't carry the animation.
        // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role
        role="img"
        aria-label="A gold dot carries each reply from the ChatGPT app to the Claude app and back, around a loop, waiting at each app while it answers."
      >
        <defs>
          <linearGradient
            id="harness-lens"
            x1="102"
            y1="0"
            x2="458"
            y2="0"
            gradientUnits="userSpaceOnUse"
          >
            <stop offset="0" stopColor="#ffffff" stopOpacity="0.1" />
            <stop offset="0.5" stopColor="#edba72" stopOpacity="0.5" />
            <stop offset="1" stopColor="#ffffff" stopOpacity="0.1" />
          </linearGradient>
          {/* Runs from the dot to the tail's end; each frame moves both ends. */}
          <linearGradient
            ref={fadeRef}
            id="harness-fade"
            gradientUnits="userSpaceOnUse"
          >
            <stop offset="0" stopColor="#f5cb8d" stopOpacity="0.95" />
            <stop offset="0.35" stopColor="#edba72" stopOpacity="0.45" />
            <stop offset="1" stopColor="#edba72" stopOpacity="0" />
          </linearGradient>
          <radialGradient id="harness-halo">
            <stop offset="0" stopColor="#edba72" stopOpacity="0.55" />
            <stop offset="1" stopColor="#edba72" stopOpacity="0" />
          </radialGradient>
          <radialGradient id="harness-bloom">
            <stop offset="0" stopColor="#edba72" stopOpacity="0.32" />
            <stop offset="0.6" stopColor="#edba72" stopOpacity="0.08" />
            <stop offset="1" stopColor="#edba72" stopOpacity="0" />
          </radialGradient>
          <radialGradient id="harness-glow-chatgpt">
            <stop offset="0" stopColor="#ffffff" stopOpacity="0.09" />
            <stop offset="1" stopColor="#ffffff" stopOpacity="0" />
          </radialGradient>
          <radialGradient id="harness-glow-claude">
            <stop offset="0" stopColor="#d97757" stopOpacity="0.2" />
            <stop offset="1" stopColor="#d97757" stopOpacity="0" />
          </radialGradient>
          <filter
            id="harness-shadow"
            x="-30%"
            y="-30%"
            width="160%"
            height="170%"
          >
            <feDropShadow
              dx="0"
              dy="8"
              stdDeviation="8"
              floodColor="#000"
              floodOpacity="0.55"
            />
          </filter>
        </defs>

        {/* Field lines around the loop, fainter the further out they sit. */}
        <g fill="none" strokeLinecap="round">
          <path
            d="M102 85 C182 -30 378 -30 458 85"
            stroke="#ffffff0d"
            strokeDasharray="1 7"
          />
          <path
            d="M102 85 C182 200 378 200 458 85"
            stroke="#ffffff0d"
            strokeDasharray="1 7"
          />
          <path d="M102 85 C200 48 360 48 458 85" stroke="#ffffff0a" />
          <path d="M102 85 C200 122 360 122 458 85" stroke="#ffffff0a" />
          <path
            ref={loopRef}
            d={LOOP}
            stroke="url(#harness-lens)"
            strokeWidth={1.25}
          />
        </g>

        <circle
          ref={chatgptRef}
          cx={60}
          cy={85}
          r={66}
          fill="url(#harness-bloom)"
          opacity={0}
        />
        <circle
          ref={claudeRef}
          cx={500}
          cy={85}
          r={66}
          fill="url(#harness-bloom)"
          opacity={0}
        />
        <App x={60} src="/app-icons/chatgpt.png" glow="harness-glow-chatgpt" />
        <App x={500} src="/app-icons/claude.png" glow="harness-glow-claude" />

        <path ref={tailRef} fill="url(#harness-fade)" />
        <g ref={headRef} transform={`translate(${REST.x} ${REST.y})`}>
          <circle r={11} fill="url(#harness-halo)" />
          <circle r={3.4} fill="#f5cb8d" />
        </g>
      </svg>
    </div>
  );
}
