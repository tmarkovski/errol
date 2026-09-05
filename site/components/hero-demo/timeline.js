const INTRO_DURATION = 4;
const SETUP_EXTENSION = 3;
const START_PRESS = 5.2;
const START_RELEASE = 7.1;
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
    [18.45, 600, 365, 1],
    [19.4, 600, 219, 1.92],
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
    [10.45, 'Errol presses Copy on the finished reply.', '02'],
    [11.65, 'Switch to Claude. Paste the reply. Send.', '02'],
    [13.75, 'Claude reads it and challenges the idea.', '02'],
    [18.05, 'Pause to steer. Errol holds the next handoff.', '03'],
    [20, 'Add the detail that changes the discussion.', '03'],
    [23.5, 'Your note travels with Claude’s reply.', '03'],
    [26.25, 'ChatGPT rethinks its recommendation.', '04'],
    [31.1, 'Errol carries the new answer back to Claude.', '04'],
    [34, 'The conversation continues in their own apps.', '04'],
    [39.3, 'You set the direction. Errol carries the conversation.', '04'],
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
    { sent, input, text, start, end, draft, copy, sendAt, withNote = false },
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
    show(p + ' .ef-copy', sent && t >= end);
    set(p + ' .ef-copy span', copy ? 'Copied' : 'Copy');
    $(p + ' .ef-copy').classList.toggle('ef-pressed', copy);
    set(
      p + ' .ef-draft',
      draft || 'Message ' + (prefix === 'gpt' ? 'ChatGPT' : 'Claude'),
    );
    $(p + ' .ef-chat-composer').classList.toggle('ef-filled', !!draft);
    $(p + ' .ef-send').classList.toggle(
      'ef-pressed',
      sendAt !== undefined && between(sendAt, sendAt + 0.45),
    );
  }
  function point() {
    // Gold marks Errol's automated actions; the neutral pointer is the person.
    const opening = setupTime < START_RELEASE + 0.5;
    const pointerTime = opening ? setupTime : t;
    const moves = opening
      ? [
          [0, 520, 260, false, 'You'],
          [0.35, 520, 260, false, 'You'],
          [1.05, 700, 260, false, 'You'],
          [1.35, 700, 260, false, 'You'],
          [1.6, 590, 275, false, 'You'],
          [4.8, 590, 275, false, 'You'],
          [START_PRESS, 749, 310, false, 'You'],
          [START_RELEASE + 0.5, 749, 310, false, 'You'],
        ]
      : [
          [4.6, 749, 310, true, 'Errol'],
          [5.2, 355, 654, true, 'Errol · Paste'],
          [5.65, 503, 654, true, 'Errol · Send'],
          [6.2, 503, 654, true, 'Errol'],
          [10.25, 503, 654, true, 'Errol'],
          [10.65, 93, 543, true, 'Errol · Copy'],
          [11.35, 93, 543, true, 'Errol · Copied'],
          [12.45, 834, 654, true, 'Errol · Paste'],
          [13.3, 1109, 654, true, 'Errol · Send'],
          [13.9, 1109, 654, true, 'Errol'],
          [17.9, 760, 461, false, 'You'],
          [18.6, 600, 309, false, 'You'],
          [19.35, 582, 297, false, 'You'],
          [22.95, 582, 297, false, 'You'],
          [23.5, 730, 335, false, 'You'],
          [24.1, 730, 335, false, 'You'],
          [25, 334, 649, true, 'Errol · Paste + note'],
          [26, 503, 654, true, 'Errol · Send'],
          [26.4, 503, 654, true, 'Errol'],
          [31, 503, 654, true, 'Errol'],
          [31.35, 94, 594, true, 'Errol · Copy'],
          [32, 94, 594, true, 'Errol · Copied'],
          [33, 851, 654, true, 'Errol · Paste'],
          [33.75, 1109, 654, true, 'Errol · Send'],
          [34.2, 1109, 654, true, 'Errol'],
          [42, 1109, 654, true, 'Errol'],
        ];
    const anchors = opening
      ? {
          0: '.ef-mode-free',
          0.35: '.ef-mode-free',
          1.05: '.ef-mode-debate',
          1.35: '.ef-mode-debate',
          1.6: '.ef-topic',
          4.8: '.ef-topic',
          [START_PRESS]: '.ef-play',
          [START_RELEASE + 0.5]: '.ef-play',
        }
      : {
          5.2: '.ef-gpt .ef-draft',
          5.65: '.ef-gpt .ef-send',
          6.2: '.ef-gpt .ef-send',
          10.25: '.ef-gpt .ef-send',
          10.65: '.ef-gpt .ef-copy',
          11.35: '.ef-gpt .ef-copy',
          12.45: '.ef-claude .ef-draft',
          13.3: '.ef-claude .ef-send',
          13.9: '.ef-claude .ef-send',
          18.6: '.ef-steer-button',
          19.35: '.ef-steer-prompt',
          22.95: '.ef-steer-prompt',
          23.5: '.ef-note-send',
          24.1: '.ef-note-send',
          25: '.ef-gpt .ef-draft',
          26: '.ef-gpt .ef-send',
          26.4: '.ef-gpt .ef-send',
          31: '.ef-gpt .ef-send',
          31.35: '.ef-gpt .ef-copy',
          32: '.ef-gpt .ef-copy',
          33: '.ef-claude .ef-draft',
          33.75: '.ef-claude .ef-send',
          34.2: '.ef-claude .ef-send',
        };
    for (const m of moves) {
      const selector = anchors[m[0]];
      if (!selector) continue;
      let e = $(selector);
      if (!e.offsetWidth) continue;
      let x = e.offsetWidth / 2,
        y = e.offsetHeight / 2;
      while (e && e !== world) {
        x += e.offsetLeft;
        y += e.offsetTop;
        e = e.offsetParent;
      }
      m[1] = x;
      m[2] = y;
    }
    let i = 0;
    while (i < moves.length - 2 && moves[i + 1][0] <= pointerTime) i++;
    const a = moves[i],
      b = moves[i + 1],
      p = smooth((pointerTime - a[0]) / (b[0] - a[0]));
    let x = a[1] + (b[1] - a[1]) * p,
      y = a[2] + (b[2] - a[2]) * p;
    const pointer = $('.ef-pointer');
    pointer.style.transform = `translate(${x}px,${y}px)`;
    pointer.classList.toggle('ef-auto', a[3]);
    set('.ef-pointer span', a[4]);
    const pointerOn = opening
      ? (setupTime >= 0 && setupTime < 1.7) ||
        (setupTime >= 4.8 && setupTime < START_PRESS + 0.2)
      : (t < 6.25 ||
          between(10.15, 13.95) ||
          between(17.85, 26.5) ||
          between(30.9, 34.3)) &&
        !between(19.45, 22.95);
    pointer.style.opacity = pointerOn ? '1' : '0';
    const clicks = opening
      ? [1.05, START_PRESS]
      : [5.65, 10.7, 13.3, 18.6, 23.5, 26, 31.4, 33.75];
    const click = clicks.find(
      (at) => pointerTime >= at && pointerTime < at + 0.5,
    );
    const ring = $('.ef-click');
    const c = click === undefined ? 1 : clamp((pointerTime - click) / 0.5);
    ring.style.opacity = click === undefined ? '0' : String(1 - c);
    ring.style.transform = `translate(${x - 15}px,${y - 15}px) scale(${0.5 + c * 1.5})`;
  }
  function render() {
    // Extend setup and hold the camera through the start-button emphasis, then
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
    const running = t >= 4.3,
      steering = between(18.65, 23.7),
      gpt2 = t >= 26.15,
      claude2 = t >= 33.95;
    root.classList.toggle('ef-is-running', running);
    root.classList.toggle('ef-is-steering', steering);
    camera();
    show('.ef-setup', !running);
    show('.ef-running', running);
    show('.ef-play', !running);
    $('.ef-mode-free').classList.toggle('ef-selected', setupTime < 1.05);
    $('.ef-mode-debate').classList.toggle('ef-selected', setupTime >= 1.05);
    $('.ef-topic').dataset.placeholder =
      setupTime < 1.05
        ? 'What would you like to talk about?'
        : 'What would you like them to debate?';
    set('.ef-topic', part(topic, 1.7, 4.5, setupTime));
    const lift = reduced.matches
      ? Number(setupTime >= START_PRESS)
      : smooth((setupTime - START_PRESS) / 0.7);
    const settle = smooth((setupTime - 6.6) / 0.5);
    const emphasis = lift * (1 - settle);
    const play = $('.ef-play');
    const errol = $('.ef-errol');
    const dx = errol.clientWidth / 2 - play.offsetLeft - play.offsetWidth / 2;
    const dy = errol.clientHeight / 2 - play.offsetTop - play.offsetHeight / 2;
    play.style.transform = `translate(${dx * lift}px, ${dy * lift}px) scale(${1 + lift * 0.65})`;
    play.style.opacity = String(1 - settle);
    $('.ef-errol-body').style.filter = reduced.matches
      ? 'none'
      : `blur(${3.5 * emphasis}px)`;
    $('.ef-errol-body').style.opacity = String(1 - 0.38 * emphasis);
    show('.ef-rest-primary', !steering);
    show('.ef-steer-prompt', steering);
    show('.ef-note-send', steering);
    set(
      '.ef-steer-prompt',
      part(note, 19.6, 22.25) || 'Write a note for the next handoff…',
    );
    set(
      '.ef-steer-hint',
      steering ? 'Return to send and continue' : 'The conversation is running',
    );
    const holding = between(19, 23.7);
    set('.ef-status', holding ? 'Paused' : running ? 'Running' : 'Ready');
    set(
      '.ef-turn',
      !running
        ? 'Turn 0 · ChatGPT opens'
        : holding
          ? 'Turn 2 · Paused at the handoff'
          : between(18.65, 19)
            ? 'Turn 2 · Pausing at the next handoff'
            : t < 10.4
              ? 'Turn 1 · ChatGPT is replying'
              : t < 13.7
                ? 'Turn 1 · Relaying to Claude'
                : t < 18.9
                  ? 'Turn 2 · Claude is replying'
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
        : between(13.6, 18.6) || t >= 34
          ? 'Replying…'
          : t > 18.6
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
      copy: between(10.65, 11.6) || between(31.35, 32.3),
      sendAt: gpt2 ? 26 : 5.65,
      withNote: gpt2,
    });
    chat('claude', {
      sent: t >= 13.55,
      input: claude2 ? revised : first,
      text: claude2 ? agreement : second,
      start: claude2 ? 34.25 : 13.95,
      end: claude2 ? 38.2 : 18.65,
      draft: cDraft,
      copy: between(18.95, 19.4),
      sendAt: claude2 ? 33.75 : 13.3,
    });
    set(
      '.ef-front-app',
      !running || steering
        ? 'Errol'
        : between(11.8, 18.7) || t >= 32.4
          ? 'Claude'
          : 'ChatGPT',
    );
    point();
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
