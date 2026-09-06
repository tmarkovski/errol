const INTRO_DURATION = 4;
const SETUP_EXTENSION = 3;
const START_PRESS = 5.2;
const START_RELEASE = 7.1;
const STEER_HOVER = 19.15;
const STEER_PRESS = 19.9;
const STEER_OPEN = 20;
const CLAUDE_REPLY_END = 18.05;
export const DEMO_DURATION = INTRO_DURATION + SETUP_EXTENSION + 42;
export const INTRO_TEXT = 'What if your AIs could talk to each other?';

/**
 * The motion study, rendered from one deterministic clock.
 * No timers, network requests, or real clipboard operations are involved.
 * @param {HTMLElement} root
 * @param {(playback: {time: number, playing: boolean, caption: string, chapter: string}) => void} onChange
 */
export function mountErrolDemo(root, onChange) {
  const $ = (s) => root.querySelector(s);
  const screen = $('.ef-screen'),
    world = $('.ef-world');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const topic = 'Should we launch on the web or build a native Mac app?';
  const first =
    'I’d start on the web. Launch sooner, reach more people, and learn what they need before committing to a platform.';
  const second =
    'Native could be the reason people choose it. If the work needs local files and fast shortcuts, the web may compromise the experience.';
  const note = 'Assume our users work offline every day.';
  const revised =
    'That changes my recommendation. Start native: local files and reliable offline work are core to the product. Add the web later for sharing.';
  const agreement =
    'Agreed. Make the first release excellent offline. Keep the scope small: one Mac app, one workflow, then validate demand.';
  let elapsed = reduced.matches ? INTRO_DURATION + SETUP_EXTENSION + 31 : 0,
    setupTime = 0,
    t = 0,
    playing = !reduced.matches,
    last = 0,
    visible = false,
    frame = 0;
  let disposed = false,
    lastEmittedTime = -1,
    lastEmittedPlaying;
  let width = screen.clientWidth,
    height = screen.clientHeight,
    captionIndex = -1;
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const smooth = (x) => {
    x = clamp(x);
    return x * x * (3 - 2 * x);
  };
  const part = (txt, start, end, time = t) =>
    time < start
      ? ''
      : txt.slice(
          0,
          Math.floor(txt.length * clamp((time - start) / (end - start))),
        );
  const show = (s, on) => {
    $(s).hidden = !on;
  };
  const set = (s, txt) => {
    const e = $(s);
    if (e.textContent !== txt) e.textContent = txt;
  };
  const between = (a, b) => t >= a && t < b;
  const shots = [
    [0, 600, 207, 1.92],
    [4.1, 600, 207, 1.92],
    [5.05, 600, 365, 1],
    [6, 297, 491, 1.72],
    // Ease out over 3.3 seconds so the opening text leads the camera move.
    [6.6, 297, 491, 1.72],
    [9.9, 600, 365, 1],
    [11.6, 600, 365, 1],
    [12.45, 903, 491, 1.72],
    [14.25, 903, 491, 1.72],
    [17.55, 600, 365, 1],
    [18.85, 600, 365, 1],
    [19.8, 600, 219, 1.92],
    [23.8, 600, 219, 1.92],
    // Once the note is sent, hold the desktop for the remaining exchange.
    [24.55, 600, 365, 1],
    [42, 600, 365, 1],
  ];
  const openingBeats = [
    [-INTRO_DURATION, INTRO_TEXT, '01'],
    [0, 'Choose how you want your AIs to talk.', '01'],
    [1.05, 'Choose Debate. Give them a question.', '01'],
    [START_PRESS, 'Start the conversation.', '01'],
  ];
  const beats = [
    [-INTRO_DURATION, INTRO_TEXT, '01'],
    [0, 'Give them something to debate.', '01'],
    [4.1, 'Errol starts the conversation.', '01'],
    [6, 'ChatGPT makes the opening case.', '02'],
    [10.45, 'Errol picks up ChatGPT’s reply.', '02'],
    [11.65, 'Errol carries the reply to Claude.', '02'],
    [13.75, 'Claude reads it and challenges the idea.', '02'],
    [18.05, 'Errol picks up Claude’s reply.', '02'],
    [18.85, 'Hover over Pause to steer the conversation.', '03'],
    [STEER_OPEN, 'Errol holds the next handoff.', '03'],
    [20.2, 'Add the detail that changes the discussion.', '03'],
    [23.5, 'Your note travels with Claude’s reply.', '03'],
    [26.25, 'ChatGPT rethinks its recommendation.', '04'],
    [31.1, 'Errol carries the new answer back to Claude.', '04'],
    [34, 'The conversation continues in their own apps.', '04'],
    [39.3, 'You set the direction. Errol carries the conversation.', '04'],
  ];
  const relayCopies = [
    { app: 'gpt', at: 10.7, until: 11.6 },
    { app: 'claude', at: 18.25, until: 18.85 },
    { app: 'gpt', at: 31.4, until: 32.3 },
  ];
  const relaySends = [
    { app: 'gpt', arrive: 5.15, sent: 5.85 },
    { app: 'claude', arrive: 12.45, sent: 13.55 },
    { app: 'gpt', arrive: 24.9, sent: 26.15 },
    { app: 'claude', arrive: 33, sent: 33.95 },
  ];
  // Every frame is a pure function of time, so scrubbing never skips a state.
  function camera() {
    let i = 0;
    while (i < shots.length - 2 && shots[i + 1][0] <= t) i++;
    const portrait = root.clientWidth <= 580;
    const framing = (shot) => {
      if (!portrait) return shot;
      const [at, x, y, z] = shot;
      // Keep close-ups readable, then reveal the whole desktop during replies.
      if (x !== 600) return [at, x, 535, 1200 / 540];
      if (z > 1.5) return [at, 600, y === 207 ? 221 : 238, (1200 / 450) * 1.04];
      return [at, 600, 410, 1];
    };
    const a = framing(shots[i]),
      b = framing(shots[i + 1]),
      p = reduced.matches ? 0 : smooth((t - a[0]) / (b[0] - a[0]));
    let x = a[1] + (b[1] - a[1]) * p,
      y = a[2] + (b[2] - a[2]) * p,
      z = a[3] + (b[3] - a[3]) * p;
    $('.ef-errol').style.opacity = String(
      1 - smooth((Math.abs(x - 600) - 45) / 180),
    );
    const s = (width / 1200) * z;
    world.style.transform = `translate(${width / 2 - x * s}px,${height / 2 - y * s}px) scale(${s})`;
  }
  function chat(
    prefix,
    { sent, input, text, start, end, draft, withNote = false },
  ) {
    const p = '.ef-' + prefix;
    show(p + ' .ef-empty', !sent);
    show(p + ' .ef-thread', sent);
    const incoming = $(p + ' .ef-incoming');
    incoming.classList.toggle('ef-has-note', withNote);
    if (withNote) {
      const key = input + '|' + note;
      if (incoming.dataset.content !== key) {
        incoming.replaceChildren(document.createTextNode(input));
        const el = document.createElement('span');
        el.className = 'ef-note-in-message';
        el.textContent = 'Your note: ' + note;
        incoming.appendChild(el);
        incoming.dataset.content = key;
      }
    } else if (incoming.dataset.content !== input) {
      incoming.textContent = input;
      incoming.dataset.content = input;
    }
    set(p + ' .ef-response', part(text, start, end));
    const copy = relayCopies.some(
      (action) => action.app === prefix && between(action.at, action.until),
    );
    show(p + ' .ef-copy', sent && t >= end);
    set(p + ' .ef-copy span', copy ? 'Copied' : 'Copy');
    $(p + ' .ef-copy').classList.toggle('ef-pressed', copy);
    set(
      p + ' .ef-draft',
      draft || 'Message ' + (prefix === 'gpt' ? 'ChatGPT' : 'Claude'),
    );
    $(p + ' .ef-chat-composer').classList.toggle('ef-filled', !!draft);
    $(p + ' .ef-chat-composer').classList.toggle(
      'ef-relay-focus',
      relaySends.some(
        (action) =>
          action.app === prefix &&
          between(action.arrive - 0.1, action.sent + 0.3),
      ),
    );
  }
  function center(selector) {
    // The resting prompt is 100px tall. Keep its center stable when the note
    // editor opens, so the person's pointer does not jump on the click.
    const pauseFace = selector === '.ef-pause-face';
    let element = $(pauseFace ? '.ef-compose' : selector);
    let x = element.offsetWidth / 2;
    let y = pauseFace ? 50 : element.offsetHeight / 2;
    while (element && element !== world) {
      x += element.offsetLeft;
      y += element.offsetTop;
      element = element.offsetParent;
    }
    return [x, y];
  }
  function point() {
    // Only the person's setup and steering actions use a mouse pointer.
    const opening = setupTime < START_RELEASE + 0.5;
    const pointerTime = opening ? setupTime : t;
    const moves = opening
      ? [
          [0, '.ef-mode-free'],
          [0.35, '.ef-mode-free'],
          [1.05, '.ef-mode-debate'],
          [1.35, '.ef-mode-debate'],
          [1.6, '.ef-topic'],
          [4.8, '.ef-topic'],
          [START_PRESS, '.ef-play'],
          [START_RELEASE + 0.5, '.ef-play'],
        ]
      : [
          [18.85, [760, 461]],
          [STEER_HOVER, '.ef-pause-face'],
          [STEER_PRESS, '.ef-pause-face'],
          [STEER_OPEN, '.ef-pause-face'],
          [20.3, '.ef-steer-prompt'],
          [22.95, '.ef-steer-prompt'],
          [23.5, '.ef-note-send'],
          [24.1, '.ef-note-send'],
        ];
    const [x, y] = follow(moves, pointerTime);
    const pointerOn = opening
      ? (setupTime >= 0 && setupTime < 1.7) ||
        (setupTime >= 4.8 && setupTime < START_PRESS + 0.2)
      : between(18.85, 23.7) && !between(20.4, 22.95);
    const pointer = $('.ef-pointer');
    pointer.style.transform = `translate(${x}px,${y}px)`;
    pointer.style.opacity = pointerOn ? '1' : '0';
    const clicks = opening ? [1.05, START_PRESS] : [STEER_PRESS, 23.5];
    const click = clicks.find(
      (at) => pointerTime >= at && pointerTime < at + 0.5,
    );
    const ring = $('.ef-click');
    const c = click === undefined ? 1 : clamp((pointerTime - click) / 0.5);
    ring.style.opacity =
      click === undefined || !pointerOn ? '0' : String(1 - c);
    ring.style.transform = `translate(${x - 15}px,${y - 15}px) scale(${0.5 + c * 1.5})`;
  }
  function follow(path, time) {
    let i = 0;
    while (i < path.length - 2 && path[i + 1][0] <= time) i++;
    const a = path[i],
      b = path[i + 1];
    const start = typeof a[1] === 'string' ? center(a[1]) : a[1];
    const end = typeof b[1] === 'string' ? center(b[1]) : b[1];
    const p = reduced.matches
      ? Number(time >= b[0])
      : smooth((time - a[0]) / (b[0] - a[0]));
    return [
      start[0] + (end[0] - start[0]) * p,
      start[1] + (end[1] - start[1]) * p,
    ];
  }
  const courierPaths = [
    [
      [4.6, '.ef-pause-face'],
      [5.15, '.ef-gpt .ef-chat-composer'],
      [6.2, '.ef-gpt .ef-chat-composer'],
    ],
    [
      [10.25, '.ef-gpt .ef-chat-composer'],
      [10.65, '.ef-gpt .ef-response'],
      [11.35, '.ef-gpt .ef-response'],
      [12.45, '.ef-claude .ef-chat-composer'],
      [13.9, '.ef-claude .ef-chat-composer'],
    ],
    [
      [17.65, '.ef-claude .ef-chat-composer'],
      [18.15, '.ef-claude .ef-response'],
      [18.75, '.ef-claude .ef-response'],
    ],
    [
      [24.1, '.ef-pause-face'],
      [24.9, '.ef-gpt .ef-chat-composer'],
      [26.5, '.ef-gpt .ef-chat-composer'],
    ],
    [
      [30.95, '.ef-gpt .ef-chat-composer'],
      [31.35, '.ef-gpt .ef-response'],
      [32, '.ef-gpt .ef-response'],
      [33, '.ef-claude .ef-chat-composer'],
      [34.3, '.ef-claude .ef-chat-composer'],
    ],
  ];
  function courierTail(path, fade) {
    const tail = $('.ef-courier-tail');
    const glow = $('.ef-courier-tail-glow');
    const core = $('.ef-courier-tail-core');
    tail.style.opacity = '0';
    glow.setAttribute('d', '');
    core.setAttribute('d', '');
    if (!path || reduced.matches) return;

    // Sample the clock, not previous frames: seeking and replaying produce the
    // same short wake, which catches up naturally when the owl stops moving.
    const points = [];
    let length = 0;
    for (let i = 0; i <= 24; i++) {
      const at = Math.max(path[0][0], t - (i / 24) * 0.38);
      const point = follow(path, at);
      if (points.length) {
        const previous = points.at(-1);
        const distance = Math.hypot(
          point[0] - previous[0],
          point[1] - previous[1],
        );
        if (distance < 0.5) continue;
        if (length + distance > 170) break;
        length += distance;
      }
      points.push(point);
      if (at === path[0][0]) break;
    }
    if (points.length < 3 || length < 16) return;
    points.reverse();
    const left = [],
      right = [];
    points.forEach(([x, y], i) => {
      const before = points[Math.max(0, i - 1)];
      const after = points[Math.min(points.length - 1, i + 1)];
      const dx = after[0] - before[0],
        dy = after[1] - before[1];
      const distance = Math.hypot(dx, dy) || 1;
      const radius = 6 * Math.pow(i / (points.length - 1), 1.3);
      left.push([x - (dy / distance) * radius, y + (dx / distance) * radius]);
      right.push([x + (dy / distance) * radius, y - (dx / distance) * radius]);
    });
    const outline = [...left, ...right.reverse()];
    const d =
      outline
        .map(([x, y], i) => `${i ? 'L' : 'M'}${x.toFixed(2)},${y.toFixed(2)}`)
        .join(' ') + ' Z';
    glow.setAttribute('d', d);
    core.setAttribute('d', d);
    const gradient = $('#ef-courier-tail-gradient');
    gradient.setAttribute('x1', String(points[0][0]));
    gradient.setAttribute('y1', String(points[0][1]));
    gradient.setAttribute('x2', String(points.at(-1)[0]));
    gradient.setAttribute('y2', String(points.at(-1)[1]));
    tail.style.opacity = String(fade * smooth(length / 55));
  }
  function courier() {
    const path = courierPaths.find((path) =>
      between(path[0][0], path.at(-1)[0]),
    );
    const logo = $('.ef-courier');
    const pulse = $('.ef-courier-pulse');
    const mark = $('.ef-courier-mark');
    logo.style.opacity = '0';
    logo.style.transform = 'translate(0px,0px)';
    pulse.style.opacity = '0';
    pulse.style.transform = 'scale(1)';
    mark.style.transform = 'scale(1)';
    if (!path) {
      courierTail(null, 0);
      return;
    }
    const [x, y] = follow(path, t);
    const fade = reduced.matches
      ? 1
      : smooth((t - path[0][0]) / 0.16) * smooth((path.at(-1)[0] - t) / 0.25);
    logo.style.opacity = String(fade);
    logo.style.transform = `translate(${x - 21}px,${y - 21}px)`;
    courierTail(path, fade);
    const copy = relayCopies.find((action) =>
      between(action.at, action.at + 0.45),
    );
    if (copy && !reduced.matches) {
      const p = clamp((t - copy.at) / 0.45);
      mark.style.transform = `scale(${1 - 0.16 * Math.sin(p * Math.PI)})`;
      pulse.style.opacity = String(0.7 * (1 - p));
      pulse.style.transform = `scale(${0.8 + p * 1.05})`;
    }
  }
  function render() {
    // Hold the camera while Start moves to the prompt's center and becomes Pause, then
    // resume the existing relay choreography without changing its pacing.
    setupTime = elapsed - INTRO_DURATION;
    t =
      setupTime < START_RELEASE
        ? Math.min(setupTime, START_RELEASE - SETUP_EXTENSION)
        : setupTime - SETUP_EXTENSION;
    const reveal = smooth((elapsed - 3.3) / 0.7);
    set('.ef-intro-lead', part('What if your AIs', -3.8, -2.95));
    set('.ef-intro-question', part('could talk to each other?', -2.8, -1.5));
    $('.ef-intro').classList.toggle('ef-intro-writing-lead', elapsed < 1.2);
    $('.ef-intro').style.opacity = String(1 - reveal);
    $('.ef-intro').style.transform = `translateY(${-12 * reveal}px)`;
    $('.ef-intro-caret').style.opacity =
      elapsed >= 1.2 && (elapsed < 2.5 || Math.floor(elapsed * 2) % 2 === 0)
        ? '1'
        : '0';
    world.style.opacity = String(reveal);
    const running = setupTime >= START_PRESS,
      steering = between(STEER_OPEN, 23.7),
      gpt2 = t >= 26.15,
      claude2 = t >= 33.95;
    root.classList.toggle('ef-is-running', running);
    root.classList.toggle('ef-is-steering', steering);
    camera();
    show('.ef-setup', setupTime < 6.1);
    show('.ef-running', steering);
    show('.ef-play', !steering);
    show('.ef-pause-status', running && !steering);
    $('.ef-mode-free').classList.toggle('ef-selected', setupTime < 1.05);
    $('.ef-mode-debate').classList.toggle('ef-selected', setupTime >= 1.05);
    $('.ef-topic').dataset.placeholder =
      setupTime < 1.05
        ? 'What would you like to talk about?'
        : 'What would you like them to debate?';
    set('.ef-topic', part(topic, 1.7, 4.5, setupTime));
    const move = reduced.matches
      ? Number(setupTime >= START_PRESS)
      : smooth((setupTime - START_PRESS) / 0.9);
    const morph = reduced.matches
      ? Number(setupTime >= START_PRESS)
      : smooth((setupTime - 5.55) / 0.55);
    const layout = reduced.matches
      ? Number(running)
      : smooth((setupTime - 6.35) / 0.65);
    const hover = between(STEER_HOVER, STEER_OPEN)
      ? reduced.matches
        ? 1
        : smooth((t - STEER_HOVER) / 0.55)
      : 0;
    root.style.setProperty('--ef-run-layout', String(layout));
    const play = $('.ef-play');
    const compose = $('.ef-compose');
    const labelWidth = ($('.ef-pause-label-text').scrollWidth + 12) * hover;
    play.style.setProperty('--ef-steer-label-width', `${labelWidth}px`);
    // Preserve the 32px circle during the move. Only the later hover adds width.
    play.style.width = `${32 + labelWidth}px`;
    play.style.height = '32px';
    play.style.right = `${10 + ((compose.clientWidth - 32) / 2 - 10) * move - labelWidth / 2}px`;
    play.style.bottom = `${10 + ((compose.clientHeight - 32) / 2 - 10) * move}px`;
    play.setAttribute(
      'aria-label',
      running ? 'Pause to steer' : 'Start conversation',
    );
    $('.ef-play-symbol').style.opacity = String(1 - morph);
    $('.ef-play-symbol').style.transform = reduced.matches
      ? 'none'
      : `rotate(${-45 * morph}deg) scale(${1 - 0.4 * morph})`;
    $('.ef-pause-symbol').style.opacity = String(morph);
    $('.ef-pause-symbol').style.transform = reduced.matches
      ? 'none'
      : `scale(${0.6 + 0.4 * morph})`;
    $('.ef-pause-label').style.opacity = String(hover);
    $('.ef-pause-face').classList.toggle(
      'ef-pause-pressed',
      between(STEER_PRESS, STEER_OPEN),
    );
    $('.ef-setup').style.filter = reduced.matches
      ? 'none'
      : `blur(${3 * move}px)`;
    $('.ef-setup').style.opacity = String(1 - move);
    show('.ef-steer-prompt', steering);
    show('.ef-note-send', steering);
    set(
      '.ef-steer-prompt',
      part(note, 20.3, 22.95) || 'Write a note for the next handoff…',
    );
    const holding = between(STEER_OPEN, 23.7);
    set('.ef-status', holding ? 'Paused' : running ? 'Running' : 'Ready');
    set(
      '.ef-turn',
      !running
        ? 'Turn 0 · ChatGPT opens'
        : holding
          ? 'Turn 2 · Paused at the handoff'
          : between(STEER_PRESS, STEER_OPEN)
            ? 'Turn 2 · Pausing at the next handoff'
            : t < 10.4
              ? 'Turn 1 · ChatGPT is replying'
              : t < 13.7
                ? 'Turn 1 · Relaying to Claude'
                : t < CLAUDE_REPLY_END
                  ? 'Turn 2 · Claude is replying'
                  : t < STEER_PRESS
                    ? 'Turn 2 · Claude’s reply is ready'
                    : t < 26.3
                      ? 'Turn 2 · Relaying to ChatGPT'
                      : t < 31.2
                        ? 'Turn 3 · ChatGPT is replying'
                        : t < 34
                          ? 'Turn 3 · Relaying to Claude'
                          : 'Turn 4 · Claude is replying',
    );
    set(
      '.ef-note-status',
      steering
        ? 'Writing a note for ChatGPT'
        : between(23.7, 25)
          ? 'Note queued · goes with the next handoff'
          : between(25, 26.2)
            ? 'Sending note to ChatGPT…'
            : t >= 26.2
              ? 'Note sent to ChatGPT with turn 2'
              : '',
    );
    set(
      '.ef-gpt-status',
      !running
        ? 'Ready'
        : between(5.8, 10.3) || between(26.3, 31.05)
          ? 'Replying…'
          : t > 5.8
            ? 'Reply ready'
            : 'Waiting',
    );
    set(
      '.ef-claude-status',
      !running
        ? 'Ready'
        : between(13.6, CLAUDE_REPLY_END) || t >= 34
          ? 'Replying…'
          : t >= CLAUDE_REPLY_END
            ? 'Reply ready'
            : 'Waiting',
    );
    const bead =
      t < 4.3 || holding ? 0.5 : t < 11.7 || between(25, 32.2) ? 0.08 : 0.92;
    $('.ef-bead').style.transform =
      `translate(${(bead - 0.5) * 143}px,${Math.pow((bead - 0.5) * 2, 2) * 12}px)`;
    const gDraft = between(5.15, 5.85)
      ? topic
      : between(24.9, 26.15)
        ? second + '\n\nYour note: ' + note
        : '';
    const cDraft = between(12.45, 13.55)
      ? first
      : between(33, 33.95)
        ? revised
        : '';
    chat('gpt', {
      sent: t >= 5.85,
      input: gpt2 ? second : topic,
      text: gpt2 ? revised : first,
      start: gpt2 ? 26.45 : 6.3,
      end: gpt2 ? 31 : 10.25,
      draft: gDraft,
      withNote: gpt2,
    });
    chat('claude', {
      sent: t >= 13.55,
      input: claude2 ? revised : first,
      text: claude2 ? agreement : second,
      start: claude2 ? 34.25 : 13.95,
      end: claude2 ? 38.2 : CLAUDE_REPLY_END,
      draft: cDraft,
    });
    set(
      '.ef-front-app',
      !running || between(18.85, 24.1)
        ? 'Errol'
        : between(11.8, 18.85) || t >= 32.4
          ? 'Claude'
          : 'ChatGPT',
    );
    point();
    courier();
    $('.ef-ending').style.opacity = String(smooth((t - 39.65) / 0.65));
    let index = 0;
    const activeBeats = setupTime < START_RELEASE ? openingBeats : beats;
    const beatTime = setupTime < START_RELEASE ? setupTime : t;
    activeBeats.forEach((b, i) => {
      if (beatTime >= b[0]) index = i;
    });
    if (
      Math.floor(elapsed * 10) !== lastEmittedTime ||
      playing !== lastEmittedPlaying ||
      index !== captionIndex
    ) {
      lastEmittedTime = Math.floor(elapsed * 10);
      lastEmittedPlaying = playing;
      captionIndex = index;
      onChange({
        time: elapsed,
        playing,
        caption: activeBeats[index][1],
        chapter: activeBeats[index][2],
      });
    }
  }

  function tick(now) {
    frame = 0;
    if (disposed || !root.isConnected) return;
    if (last && playing && visible && !document.hidden)
      elapsed = Math.min(
        DEMO_DURATION,
        elapsed + Math.min((now - last) / 1000, 0.1),
      );
    last = now;
    if (elapsed >= DEMO_DURATION) playing = false;
    render();
    if (playing && visible && !document.hidden)
      frame = requestAnimationFrame(tick);
  }
  function run() {
    last = 0;
    if (!disposed && !frame && playing && visible && !document.hidden)
      frame = requestAnimationFrame(tick);
  }
  function toggle() {
    if (elapsed >= DEMO_DURATION) elapsed = 0;
    playing = !playing;
    render();
    run();
  }
  function replay() {
    elapsed = 0;
    playing = true;
    render();
    run();
  }
  function seek(value) {
    elapsed = clamp(value, 0, DEMO_DURATION);
    playing = false;
    render();
  }
  const resize = new ResizeObserver((entries) => {
    width = entries[0].contentRect.width;
    height = entries[0].contentRect.height;
    render();
  });
  resize.observe(screen);
  const intersection = new IntersectionObserver(
    (entries) => {
      visible =
        entries[0].isIntersecting && entries[0].intersectionRatio >= 0.15;
      run();
    },
    { threshold: 0.15 },
  );
  intersection.observe(screen);
  function onReducedMotion() {
    if (reduced.matches) {
      playing = false;
      elapsed = INTRO_DURATION + SETUP_EXTENSION + 31;
      render();
    }
  }
  document.addEventListener('visibilitychange', run);
  reduced.addEventListener('change', onReducedMotion);
  render();
  return {
    toggle,
    replay,
    seek,
    dispose() {
      disposed = true;
      cancelAnimationFrame(frame);
      resize.disconnect();
      intersection.disconnect();
      document.removeEventListener('visibilitychange', run);
      reduced.removeEventListener('change', onReducedMotion);
    },
  };
}
