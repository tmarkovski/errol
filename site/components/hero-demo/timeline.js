const INTRO_DURATION = 4;
const SETUP_EXTENSION = 1;
const START_PRESS = 5.2;
const STEER_APPROACH = 21.35;
const STEER_HOVER = 22.05;
const STEER_PRESS = 22.8;
const STEER_OPEN = 22.9;
const NOTE_START = 23.2;
const NOTE_END = 25.85;
const NOTE_SEND = 26.1;
const STEER_CLOSE = 26.3;
const CLAUDE_REPLY_END = 18.05;
const REDUCED_SNAPSHOT = INTRO_DURATION + SETUP_EXTENSION + 36.25;
export const DEMO_DURATION = INTRO_DURATION + SETUP_EXTENSION + 40;

/**
 * The motion study, rendered from one deterministic clock.
 * No timers, network requests, or real clipboard operations are involved.
 * @param {HTMLElement} root
 * @param {(playback: {time: number, playing: boolean}) => void} onChange
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
  const counterpoint =
    'Those features matter, but a web launch would test demand faster. I’d still start there unless people need local access every day.';
  const note = 'Assume our users work offline every day.';
  const revised =
    'If our users work offline every day, native is the clear starting point. Build a focused Mac app around local files and reliable offline access.';
  const agreement =
    'Agreed. Start with one reliable offline workflow on the Mac. Validate demand, then add the web for sharing.';
  // One sequence drives deliveries, messages, and status labels. Only turn four
  // carries the person's note, entered while turn three is still streaming.
  const turns = [
    {
      app: 'gpt',
      arrive: 5.15,
      sent: 5.85,
      start: 6.3,
      end: 10.25,
      input: topic,
      text: first,
    },
    {
      app: 'claude',
      arrive: 12.45,
      sent: 13.55,
      start: 13.95,
      end: CLAUDE_REPLY_END,
      input: first,
      text: second,
    },
    {
      app: 'gpt',
      arrive: 19.75,
      sent: 20.65,
      start: 20.95,
      end: 26.6,
      input: second,
      text: counterpoint,
    },
    {
      app: 'claude',
      arrive: 27.9,
      sent: 29.15,
      start: 29.45,
      end: 31.3,
      input: counterpoint,
      text: revised,
      withNote: true,
    },
    {
      app: 'gpt',
      arrive: 33.3,
      sent: 34.25,
      start: 34.55,
      end: 36.2,
      input: revised,
      text: agreement,
    },
  ];
  const noteTurn = turns[3];
  const steeringCopy = { app: 'gpt', at: turns[2].end, until: 27.55 };
  const appName = (app) => (app === 'gpt' ? 'ChatGPT' : 'Claude');
  let elapsed = reduced.matches ? REDUCED_SNAPSHOT : 0,
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
    height = screen.clientHeight;
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
  const openingShots = [
    [0, 600, 207, 1.92],
    [4.15, 600, 207, 1.92],
    [5.05, 600, 365, 1],
    [START_PRESS, 600, 365, 1],
  ];
  const shots = [
    [START_PRESS - SETUP_EXTENSION, 600, 365, 1],
    [5.05, 600, 365, 1],
    [6, 297, 491, 1.72],
    // Ease out over 3.3 seconds so the opening text leads the camera move.
    [6.6, 297, 491, 1.72],
    [9.9, 600, 365, 1],
    [11.6, 600, 365, 1],
    [12.45, 903, 491, 1.72],
    [14.25, 903, 491, 1.72],
    [17.55, 600, 365, 1],
    // Begin steering during ChatGPT's opening words. Frame both Errol and the
    // streaming reply, so the viewer can see the conversation continue.
    [STEER_APPROACH, 600, 365, 1],
    [22.55, 480, 327, 1.4, 'steer'],
    [NOTE_END, 480, 327, 1.4, 'steer'],
    // Pull back as the note finishes, before both owls collect their texts.
    [steeringCopy.at, 600, 365, 1],
    [40, 600, 365, 1],
  ];
  const relayCopies = [
    { app: 'gpt', at: 10.7, until: 11.6 },
    { app: 'claude', at: 18.25, until: 19 },
    steeringCopy,
    { app: 'claude', at: 31.7, until: 32.6 },
  ];
  // Every frame is a pure function of time, so scrubbing never skips a state.
  function camera(stateOpacity) {
    const opening = setupTime < START_PRESS;
    const cameraShots = opening ? openingShots : shots;
    const cameraTime = opening ? setupTime : t;
    let i = 0;
    while (i < cameraShots.length - 2 && cameraShots[i + 1][0] <= cameraTime)
      i++;
    const portrait = root.clientWidth <= 580;
    const framing = (shot) => {
      if (!portrait) return shot;
      const [at, x, y, z, kind] = shot;
      // Keep both the note editor and ChatGPT's full text width on phones.
      if (kind === 'steer') return [at, 430, 350, 1.55, kind];
      // Keep close-ups readable, then reveal the whole desktop during replies.
      if (x !== 600) return [at, x, 535, 1200 / 540];
      if (z > 1.5) return [at, 600, y === 207 ? 221 : 238, (1200 / 450) * 1.04];
      return [at, 600, 410, 1];
    };
    const a = framing(cameraShots[i]),
      b = framing(cameraShots[i + 1]),
      p = reduced.matches ? 0 : smooth((cameraTime - a[0]) / (b[0] - a[0]));
    let x = a[1] + (b[1] - a[1]) * p,
      y = a[2] + (b[2] - a[2]) * p,
      z = a[3] + (b[3] - a[3]) * p;
    const appFocus = (shot) =>
      shot[4] === 'steer' ? 0 : Math.abs(shot[1] - 600);
    const focus = appFocus(a) + (appFocus(b) - appFocus(a)) * p;
    $('.ef-errol').style.opacity = String(
      (1 - smooth((focus - 45) / 180)) * stateOpacity,
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
    $(p + ' .ef-response').classList.toggle('ef-copied', copy);
    set(
      p + ' .ef-draft',
      draft || 'Message ' + (prefix === 'gpt' ? 'ChatGPT' : 'Claude'),
    );
    $(p + ' .ef-chat-composer').classList.toggle('ef-filled', !!draft);
    $(p + ' .ef-chat-composer').classList.toggle(
      'ef-relay-focus',
      turns.some(
        (action) =>
          action.app === prefix &&
          between(action.arrive - 0.1, action.sent + 0.3),
      ),
    );
  }
  function center(selector) {
    // The compose area's top stays fixed between its 100px resting and 142px
    // editing states. Keep anchors stable as the note editor opens or closes.
    const pauseFace = selector === '.ef-pause-face';
    const noteText = selector === '.ef-steer-prompt';
    let element = $(pauseFace || noteText ? '.ef-compose' : selector);
    let x = element.offsetWidth / 2;
    let y = pauseFace ? 50 : noteText ? 77.5 : element.offsetHeight / 2;
    while (element && element !== world) {
      x += element.offsetLeft;
      y += element.offsetTop;
      element = element.offsetParent;
    }
    return [x, y];
  }
  function point() {
    // Only the person's setup and steering actions use a mouse pointer.
    const opening = setupTime < START_PRESS + 0.5;
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
          [START_PRESS + 0.5, '.ef-play'],
        ]
      : [
          [STEER_APPROACH, [760, 461]],
          [STEER_HOVER, '.ef-pause-face'],
          [STEER_PRESS, '.ef-pause-face'],
          [STEER_OPEN, '.ef-pause-face'],
          [NOTE_START, '.ef-steer-prompt'],
          [NOTE_END, '.ef-steer-prompt'],
          [NOTE_SEND, '.ef-note-send'],
          [STEER_CLOSE + 0.4, '.ef-note-send'],
        ];
    const [x, y] = follow(moves, pointerTime);
    const pointerOn = opening
      ? (setupTime >= 0 && setupTime < 1.7) ||
        (setupTime >= 4.8 && setupTime < START_PRESS + 0.5)
      : between(STEER_APPROACH, STEER_CLOSE) &&
        !between(NOTE_START + 0.1, NOTE_END);
    const pointer = $('.ef-pointer');
    pointer.style.transform = `translate(${x}px,${y}px)`;
    pointer.style.opacity = pointerOn ? '1' : '0';
    const clicks = opening ? [1.05, START_PRESS] : [STEER_PRESS, NOTE_SEND];
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
      [START_PRESS - SETUP_EXTENSION, '.ef-topic'],
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
      [19.75, '.ef-gpt .ef-chat-composer'],
      [21, '.ef-gpt .ef-chat-composer'],
    ],
    [
      [steeringCopy.at, '.ef-gpt .ef-response'],
      [27.2, '.ef-gpt .ef-response'],
      [27.9, '.ef-claude .ef-chat-composer'],
      [29.5, '.ef-claude .ef-chat-composer'],
    ],
    [
      [31.25, '.ef-claude .ef-chat-composer'],
      [31.65, '.ef-claude .ef-response'],
      [32.3, '.ef-claude .ef-response'],
      [33.3, '.ef-gpt .ef-chat-composer'],
      [34.6, '.ef-gpt .ef-chat-composer'],
    ],
  ];
  // Wait for ChatGPT to finish, then collect both texts at the same time.
  // Both fly directly from their sources and meet in Claude's composer.
  const noteCourierPath = [
    [steeringCopy.at, '.ef-steer-prompt'],
    [27.2, '.ef-steer-prompt'],
    [noteTurn.arrive, '.ef-claude .ef-chat-composer'],
    [noteTurn.arrive + 0.25, '.ef-claude .ef-chat-composer'],
  ];
  function courierTail(path, fade, prefix) {
    const tail = $(prefix + '-tail');
    const glow = $(prefix + '-tail .ef-courier-tail-glow');
    const core = $(prefix + '-tail .ef-courier-tail-core');
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
    const gradient = $('#' + prefix.slice(1) + '-tail-gradient');
    gradient.setAttribute('x1', String(points[0][0]));
    gradient.setAttribute('y1', String(points[0][1]));
    gradient.setAttribute('x2', String(points.at(-1)[0]));
    gradient.setAttribute('y2', String(points.at(-1)[1]));
    tail.style.opacity = String(fade * smooth(length / 55));
  }
  function drawCourier(path, prefix, pulseAt) {
    const logo = $(prefix);
    const pulse = $(prefix + ' .ef-courier-pulse');
    const mark = $(prefix + ' .ef-courier-mark');
    logo.style.opacity = '0';
    logo.style.transform = 'translate(0px,0px)';
    pulse.style.opacity = '0';
    pulse.style.transform = 'scale(1)';
    mark.style.transform = 'scale(1)';
    if (!path) {
      courierTail(null, 0, prefix);
      return;
    }
    const [x, y] = follow(path, t);
    const fade = reduced.matches
      ? 1
      : smooth((t - path[0][0]) / 0.16) * smooth((path.at(-1)[0] - t) / 0.25);
    logo.style.opacity = String(fade);
    logo.style.transform = `translate(${x - 21}px,${y - 21}px)`;
    courierTail(path, fade, prefix);
    if (pulseAt !== undefined && !reduced.matches) {
      const p = clamp((t - pulseAt) / 0.45);
      mark.style.transform = `scale(${1 - 0.16 * Math.sin(p * Math.PI)})`;
      pulse.style.opacity = String(0.7 * (1 - p));
      pulse.style.transform = `scale(${0.8 + p * 1.05})`;
    }
  }
  function courier() {
    const path = courierPaths.find((path) =>
      between(path[0][0], path.at(-1)[0]),
    );
    const copy = relayCopies.find((action) =>
      between(action.at, action.at + 0.45),
    );
    const merging = between(noteTurn.arrive, noteTurn.arrive + 0.45);
    drawCourier(
      path,
      '.ef-courier',
      copy?.at ?? (merging ? noteTurn.arrive : undefined),
    );
    const carryingNote = between(
      noteCourierPath[0][0],
      noteCourierPath.at(-1)[0],
    );
    drawCourier(
      carryingNote ? noteCourierPath : null,
      '.ef-note-courier',
      between(steeringCopy.at, steeringCopy.at + 0.45)
        ? steeringCopy.at
        : undefined,
    );
  }
  function render() {
    // Finish typing before releasing the relay clock. The camera pulls back
    // during the last words, and the owl leaves as soon as the person presses Play.
    setupTime = elapsed - INTRO_DURATION;
    t =
      setupTime < START_PRESS
        ? Math.min(setupTime, START_PRESS - SETUP_EXTENSION)
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
      steering = between(STEER_OPEN, STEER_CLOSE),
      noteVisible = between(STEER_OPEN, steeringCopy.until);
    // After the opening delivery, fade out the setup and fade in the running
    // window. Swap the layout and control at zero opacity; neither moves nor morphs.
    const stateFade = reduced.matches
      ? Number(t >= turns[0].sent)
      : smooth((t - turns[0].sent) / 0.6);
    const pauseReady = stateFade >= 0.5;
    root.classList.toggle('ef-is-running', running);
    root.classList.toggle('ef-is-steering', noteVisible);
    camera(reduced.matches ? 1 : Math.abs(1 - 2 * stateFade));
    show('.ef-setup', !pauseReady);
    show('.ef-running', noteVisible);
    show('.ef-play', !noteVisible);
    show('.ef-pause-status', pauseReady && !noteVisible);
    $('.ef-mode-free').classList.toggle('ef-selected', setupTime < 1.05);
    $('.ef-mode-debate').classList.toggle('ef-selected', setupTime >= 1.05);
    $('.ef-topic').dataset.placeholder =
      setupTime < 1.05
        ? 'What would you like to talk about?'
        : 'What would you like them to debate?';
    set('.ef-topic', part(topic, 1.7, 4.5, setupTime));
    const layout = Number(pauseReady);
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
    // Play stays in its corner. Pause appears centered in the new window state;
    // only the later steering hover animates the control's width.
    play.style.width = `${32 + labelWidth}px`;
    play.style.height = '32px';
    play.style.right = `${pauseReady ? (compose.clientWidth - 32 - labelWidth) / 2 : 10}px`;
    play.style.bottom = `${pauseReady ? (compose.clientHeight - 32) / 2 : 10}px`;
    play.setAttribute(
      'aria-label',
      pauseReady ? 'Pause to steer' : 'Start conversation',
    );
    $('.ef-play-symbol').style.opacity = String(1 - layout);
    $('.ef-pause-symbol').style.opacity = String(layout);
    $('.ef-pause-label').style.opacity = String(hover);
    $('.ef-pause-face').classList.toggle(
      'ef-pause-pressed',
      between(STEER_PRESS, STEER_OPEN),
    );
    show('.ef-steer-prompt', noteVisible);
    show('.ef-steer-hint', steering);
    show('.ef-note-send', steering);
    set('.ef-steer-prompt', part(note, NOTE_START, NOTE_END));
    $('.ef-steer-prompt').classList.toggle(
      'ef-relay-focus',
      between(steeringCopy.at, steeringCopy.until),
    );
    const holding = steering;
    set('.ef-status', holding ? 'Steering' : running ? 'Running' : 'Ready');
    const turnIndex = Math.max(
      0,
      turns.findLastIndex((turn) => t >= turn.sent),
    );
    const activeTurn = turns[turnIndex];
    const nextTurn = turns[turnIndex + 1];
    const turnNumber = turnIndex + 1;
    set(
      '.ef-turn',
      !running
        ? 'Turn 0 · ChatGPT opens'
        : t < activeTurn.end
          ? `Turn ${turnNumber} · ${appName(activeTurn.app)} is replying`
          : holding
            ? `Turn ${turnNumber} · Holding the next handoff`
            : nextTurn && t >= nextTurn.arrive
              ? `Turn ${turnNumber} · Relaying to ${appName(nextTurn.app)}`
              : `Turn ${turnNumber} · ${appName(activeTurn.app)}’s reply is ready`,
    );
    set(
      '.ef-note-status',
      steering
        ? ''
        : between(STEER_CLOSE, noteTurn.arrive)
          ? 'Note queued · goes with the next handoff'
          : between(noteTurn.arrive, noteTurn.sent)
            ? 'Sending note to Claude…'
            : t >= noteTurn.sent
              ? 'Note sent to Claude with turn 3'
              : '',
    );
    for (const app of ['gpt', 'claude']) {
      const appTurns = turns.filter((turn) => turn.app === app);
      const current =
        appTurns.findLast((turn) => t >= turn.sent) || appTurns[0];
      const draft = appTurns.find((turn) => between(turn.arrive, turn.sent));
      set(
        `.ef-${app}-status`,
        !running
          ? 'Ready'
          : t < current.sent
            ? 'Waiting'
            : t < current.end
              ? 'Replying…'
              : 'Reply ready',
      );
      chat(app, {
        ...current,
        sent: t >= current.sent,
        draft: draft
          ? draft.input + (draft.withNote ? '\n\nYour note: ' + note : '')
          : '',
      });
    }
    const receivingTurn = turns.findLast((turn) => t >= turn.arrive);
    const bead =
      t < 4.3 || holding ? 0.5 : receivingTurn?.app === 'claude' ? 0.92 : 0.08;
    $('.ef-bead').style.transform =
      `translate(${(bead - 0.5) * 143}px,${Math.pow((bead - 0.5) * 2, 2) * 12}px)`;
    set(
      '.ef-front-app',
      !running || between(STEER_APPROACH, STEER_CLOSE + 0.4)
        ? 'Errol'
        : between(11.8, 19.15) || between(27.4, 32.7)
          ? 'Claude'
          : 'ChatGPT',
    );
    point();
    courier();
    $('.ef-ending').style.opacity = String(smooth((t - 37.65) / 0.65));
    if (
      Math.floor(elapsed * 10) !== lastEmittedTime ||
      playing !== lastEmittedPlaying
    ) {
      lastEmittedTime = Math.floor(elapsed * 10);
      lastEmittedPlaying = playing;
      onChange({
        time: elapsed,
        playing,
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
      elapsed = REDUCED_SNAPSHOT;
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
