// Typing pace: the person types at about 32 characters per second and the
// assistants stream at about 50. ChatGPT's second reply is the exception; it
// keeps streaming until the note is sent, so its pace follows the steering.
const INTRO_DURATION = 4;
const SETUP_EXTENSION = 1;
const START_PRESS = 4.1;
const STEER_APPROACH = 16.9;
const STEER_HOVER = 17.6;
const STEER_PRESS = 18.35;
const STEER_OPEN = 18.45;
const NOTE_START = 18.75;
const NOTE_END = 20.05;
const NOTE_SEND = 20.3;
const STEER_CLOSE = 20.5;
const CLAUDE_REPLY_END = 13.6;
const REDUCED_SNAPSHOT = INTRO_DURATION + SETUP_EXTENSION + 25.55;
export const DEMO_DURATION = INTRO_DURATION + SETUP_EXTENSION + 29;

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
  // One sequence drives deliveries, messages, and status labels. Only turn four
  // carries the person's note, entered while turn three is still streaming,
  // and the demo ends on Claude's steered reply.
  const turns = [
    {
      app: 'gpt',
      arrive: 4.05,
      sent: 4.75,
      start: 5.2,
      end: 7.4,
      input: topic,
      text: first,
    },
    {
      app: 'claude',
      arrive: 9.6,
      sent: 10.7,
      start: 11.1,
      end: CLAUDE_REPLY_END,
      input: first,
      text: second,
    },
    {
      app: 'gpt',
      arrive: 15.3,
      sent: 16.2,
      start: 16.5,
      // Keep streaming until the note is sent; steering never cuts a reply off.
      end: STEER_CLOSE + 0.3,
      input: second,
      text: counterpoint,
    },
    {
      app: 'claude',
      arrive: 22.1,
      sent: 23.35,
      start: 23.65,
      end: 25.5,
      input: counterpoint,
      text: revised,
      withNote: true,
    },
  ];
  const noteTurn = turns[3];
  const steeringCopy = { app: 'gpt', at: turns[2].end, until: 21.75 };
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
    [3.05, 600, 207, 1.92],
    [3.95, 600, 365, 1],
    [START_PRESS, 600, 365, 1],
  ];
  const shots = [
    [START_PRESS - SETUP_EXTENSION, 600, 365, 1],
    [3.95, 600, 365, 1],
    [4.9, 297, 491, 1.72],
    // Ease out over 1.55 seconds so the opening text leads the camera move.
    [5.5, 297, 491, 1.72],
    [7.05, 600, 365, 1],
    [8.75, 600, 365, 1],
    [9.6, 903, 491, 1.72],
    [11.4, 903, 491, 1.72],
    [13.1, 600, 365, 1],
    // Begin steering during ChatGPT's opening words. Frame both Errol and the
    // streaming reply, so the viewer can see the conversation continue.
    [STEER_APPROACH, 600, 365, 1],
    [18.1, 480, 327, 1.4, 'steer'],
    [NOTE_END, 480, 327, 1.4, 'steer'],
    // Pull back as the note finishes, before both dots collect their texts.
    [steeringCopy.at, 600, 365, 1],
    [29, 600, 365, 1],
  ];
  const relayCopies = [
    { app: 'gpt', at: 7.85, until: 8.75 },
    { app: 'claude', at: 13.8, until: 14.55 },
    steeringCopy,
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
    const x = a[1] + (b[1] - a[1]) * p,
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
          [3.7, '.ef-topic'],
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
        (setupTime >= 3.7 && setupTime < START_PRESS + 0.5)
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
  // Every handoff is one flight, mirroring the app's TransferOverlay: a golden
  // dot leaves the previous reply's Copy control (or Errol's prompt) once the
  // receiving app is in front, arcs to its composer in 0.55 seconds, and
  // dissolves into a bloom as the pasted text lights the composer's outline.
  // A fresh note flies beside its reply on a shallower arc and lands with it.
  const FLIGHT = 0.55;
  const flights = turns.map((turn, index) => ({
    at: turn.arrive - FLIGHT,
    land: turn.arrive,
    to: `.ef-${turn.app} .ef-chat-composer`,
    sources: [
      index ? `.ef-${turns[index - 1].app} .ef-copy` : '.ef-topic',
      ...(turn.withNote ? ['.ef-steer-prompt'] : []),
    ],
  }));
  const dots = ['.ef-courier', '.ef-note-courier'];
  function arc(start, end, lane, progress) {
    // Same progress clock and endpoint for every lane; the bend keeps two
    // wakes apart. The arc bows upward, as it does on the desktop.
    const e = smooth(progress),
      q = 1 - e;
    const distance = Math.hypot(end[0] - start[0], end[1] - start[1]);
    const bend = Math.min(100, distance * 0.18) * (lane ? 0.55 : 1);
    const control = [
      (start[0] + end[0]) / 2,
      Math.min(start[1], end[1]) - bend,
    ];
    return [
      q * q * start[0] + 2 * q * e * control[0] + e * e * end[0],
      q * q * start[1] + 2 * q * e * control[1] + e * e * end[1],
    ];
  }
  function drawTail(selector, pointAt, opacity) {
    // Recent positions form a tapered wake. As the dot stops, the wake
    // catches up with it and vanishes instead of leaving a line across the apps.
    const tail = $(selector);
    const points = [];
    for (let i = 0; i <= 24; i++)
      points.push(pointAt(t - 0.18 + (i / 24) * 0.18));
    const left = [],
      right = [];
    points.forEach(([x, y], i) => {
      const a = points[Math.max(0, i - 1)];
      const b = points[Math.min(points.length - 1, i + 1)];
      const length = Math.max(0.001, Math.hypot(b[0] - a[0], b[1] - a[1]));
      const width = 3.9 * Math.pow(i / 24, 1.5);
      const dx = (-(b[1] - a[1]) / length) * width,
        dy = ((b[0] - a[0]) / length) * width;
      left.push([x + dx, y + dy]);
      right.push([x - dx, y - dy]);
    });
    const d =
      [...left, ...right.reverse()]
        .map(([x, y], i) => `${i ? 'L' : 'M'}${x.toFixed(2)},${y.toFixed(2)}`)
        .join(' ') + ' Z';
    for (const path of tail.querySelectorAll('path')) path.setAttribute('d', d);
    tail.style.opacity = String(opacity * 0.55);
  }
  function courier() {
    const bloom = $('.ef-bloom');
    bloom.style.opacity = '0';
    for (const app of ['gpt', 'claude'])
      $(`.ef-${app} .ef-chat-composer`).style.setProperty('--ef-glow', '0');
    for (const dot of dots) {
      $(dot).style.opacity = '0';
      $(dot + '-tail').style.opacity = '0';
    }
    const flight = flights.find((f) => between(f.at, f.land + 0.95));
    if (!flight) return;
    const end = center(flight.to);
    const age = Math.max(0, t - flight.land);
    const dissolve = clamp(age / 0.24);
    const moving = !reduced.matches;
    const fadeIn = clamp((t - flight.at) / 0.07);
    const opacity = moving ? fadeIn * (1 - dissolve) : 0;
    const radius = 5.5 * (1 - dissolve * 0.75);
    flight.sources.forEach((source, lane) => {
      const from = center(source);
      const pointAt = (time) =>
        arc(from, end, lane, (time - flight.at) / FLIGHT);
      const [x, y] = pointAt(t);
      const dot = $(dots[lane]);
      dot.style.opacity = String(opacity);
      dot.style.transform = `translate(${x - 5.5}px,${y - 5.5}px) scale(${radius / 5.5})`;
      if (moving) drawTail(dots[lane] + '-tail', pointAt, opacity);
    });
    if (t >= flight.land && moving) {
      const bloomRadius = 5.5 + dissolve * 20;
      bloom.style.width = bloom.style.height = `${bloomRadius * 2}px`;
      bloom.style.transform = `translate(${end[0] - bloomRadius}px,${end[1] - bloomRadius}px)`;
      bloom.style.opacity = String((1 - dissolve) * 0.65);
    }
    if (t >= flight.land) {
      const rise = clamp(age / 0.09);
      const fall = Math.max(0, 1 - Math.max(0, age - 0.18) / 0.77);
      $(flight.to).style.setProperty(
        '--ef-glow',
        String(reduced.matches ? 0.85 : rise * fall * fall),
      );
    }
  }
  function render() {
    // Finish typing before releasing the relay clock. The camera pulls back
    // during the last words, and the dot leaves shortly after the person presses Play.
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
    set('.ef-topic', part(topic, 1.7, 3.4, setupTime));
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
      t < 3.2 || holding ? 0.5 : receivingTurn?.app === 'claude' ? 0.92 : 0.08;
    $('.ef-bead').style.transform =
      `translate(${(bead - 0.5) * 143}px,${Math.pow((bead - 0.5) * 2, 2) * 12}px)`;
    set(
      '.ef-front-app',
      !running || between(STEER_APPROACH, STEER_CLOSE + 0.4)
        ? 'Errol'
        : between(8.95, 14.7) || t >= 21.5
          ? 'Claude'
          : 'ChatGPT',
    );
    point();
    courier();
    $('.ef-ending').style.opacity = String(smooth((t - 26.95) / 0.65));
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
