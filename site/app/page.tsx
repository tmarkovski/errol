'use client';

import { useEffect, useRef, useState } from 'react';
import { ArrowDown, ArrowDownToLine, ArrowRight, ArrowUp, ArrowUpRight, Check, Code2, Lightbulb, MessageCircle, PanelLeft, Pause, Play, Plus, Sparkles } from 'lucide-react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';

const DOWNLOAD_URL = 'https://github.com/tmarkovski/errol/releases';
const REPO_URL = 'https://github.com/tmarkovski/errol';
const examples = [
  { id: 'brainstorm', label: 'Brainstorm', icon: Lightbulb, prompt: 'What could make a personal reading app feel different?', first: 'What if your library was organized around the questions you’re trying to answer?', second: 'I like that. And a book could belong to more than one question. Let’s explore what happens between them.' },
  { id: 'debate', label: 'Debate', icon: MessageCircle, prompt: 'Should a small team build a native app or start on the web?', first: 'I’d start on the web. A smaller launch lets the team learn before committing to a platform.', second: 'But if the experience depends on feeling at home on the Mac, native could be the thing that makes it worth using.' },
  { id: 'review', label: 'Code review', icon: Code2, prompt: 'Review the design of a background sync queue together.', first: 'A retry could create duplicate jobs. I’d give each operation a stable ID before it enters the queue.', second: 'Agreed. The ID also needs to survive a restart. Let’s check where the queue is persisted.' },
];
function Owl({ className = '' }: { className?: string }) {
  return <img className={`owl ${className}`} src="/errol.svg" width="40" height="40" alt="" />;
}
function DownloadLink({ small = false }: { small?: boolean }) {
  return <a className={`download-button ${small ? 'download-small' : ''}`} href={DOWNLOAD_URL} target="_blank" rel="noopener noreferrer"><ArrowDownToLine size={small ? 15 : 18} strokeWidth={1.8} /><span>{small ? 'Download' : 'Download for Mac'}</span>{!small && <ArrowUpRight className="button-arrow" size={17} />}</a>;
}
function ChatWindow({ app, incoming, reply }: { app: 'Codex' | 'Claude'; incoming: string; reply: string }) {
  return (
    <article className={`chat-card ${app.toLowerCase()}-card`} aria-label={`${app} example conversation`}>
      <div className="mac-titlebar">
        <div className="window-controls" aria-hidden="true">
          <span className="window-close" />
          <span className="window-minimize" />
          <span className="window-zoom" />
        </div>
        <h3>{app}</h3>
        <PanelLeft className="window-toolbar-icon" size={15} strokeWidth={1.5} aria-hidden="true" />
      </div>
      <div className="chat-thread">
        <div className="chat-user-message"><span className="sr-only">Incoming message: </span><p>{incoming}</p></div>
        <div className="chat-message">
          <div className="message-author">{app === 'Codex' ? <Code2 size={15} aria-hidden="true" /> : <Sparkles size={15} aria-hidden="true" />}<span>{app}</span></div>
          <p>{reply}</p>
        </div>
      </div>
      <div className="chat-composer" aria-hidden="true">
        <Plus size={16} strokeWidth={1.5} />
        <span>Message {app}…</span>
        <span className="composer-send"><ArrowUp size={14} strokeWidth={2} /></span>
      </div>
    </article>
  );
}
export default function Home() {
  const [example, setExample] = useState('brainstorm');
  const [motionPaused, setMotionPaused] = useState(false);
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
      page.style.setProperty('--scroll-shift', `${Math.min(window.scrollY, 1400) * 0.16}px`);
      frame = Math.abs(targetX - x) + Math.abs(targetY - y) > 0.08 ? requestAnimationFrame(update) : 0;
    };
    const schedule = () => {
      if (!motionPaused && !reducedMotion.matches && !document.hidden && !frame) frame = requestAnimationFrame(update);
    };
    const pointerMove = (event: PointerEvent) => {
      if (!finePointer.matches) return;
      targetX = (event.clientX / window.innerWidth - 0.5) * 30;
      targetY = (event.clientY / window.innerHeight - 0.5) * 20;
      schedule();
    };
    const resetPointer = () => { targetX = 0; targetY = 0; schedule(); };
    const resetMotion = () => {
      cancelAnimationFrame(frame);
      frame = 0;
      x = y = targetX = targetY = 0;
      for (const property of ['--pointer-x', '--pointer-y', '--scroll-shift']) page.style.removeProperty(property);
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
  return (
    <div className="landing" ref={pageRef} data-motion-paused={motionPaused}>
      <a className="skip-link" href="#main">Skip to content</a>
      <header className="site-header shell">
        <a href="#" className="brand" aria-label="Errol home"><Owl /><span>errol<span className="brand-dot">.</span></span></a>
        <nav aria-label="Main navigation"><a className="nav-link" href="#how-it-works">How it works</a><a className="nav-link github-link" href={REPO_URL} target="_blank" rel="noopener noreferrer">GitHub <ArrowUpRight size={14} /></a><DownloadLink small /></nav>
      </header>
      <main id="main">
        <section className="hero" aria-labelledby="hero-title">
          <div className="atmosphere" aria-hidden="true"><div className="ambient-glow" /><div className="orbit orbit-one" /><div className="orbit orbit-two" /><div className="orbit orbit-three" /><div className="star star-one" /><div className="star star-two" /><div className="star star-three" /></div>
          <div className="hero-copy shell">
            <p className="eyebrow"><span className="status-dot" /> A LITTLE MAC APP FOR BIG CONVERSATIONS</p>
            <h1 id="hero-title">Good ideas<br />need <em>company.</em></h1>
            <p className="hero-description">Let Codex and Claude think together. Errol carries the conversation between the desktop apps you already use.</p>
            <div className="hero-actions"><DownloadLink /><a href="#conversation" className="text-link">See it in motion <ArrowDown size={16} /></a></div>
            <p className="download-note">macOS 26.4+ <span>·</span> No API keys needed</p>
          </div>
          <div id="conversation" className="conversation shell">
            <Tabs className="conversation-tabs" value={example} onValueChange={value => setExample(String(value))}>
              <div className="demo-intro"><span className="micro-label">ONE BRIEF. TWO PERSPECTIVES.</span><TabsList className="mode-tabs" aria-label="Example conversation type">{examples.map(item => <TabsTrigger className="mode-tab" key={item.id} value={item.id}><item.icon size={14} />{item.label}</TabsTrigger>)}</TabsList></div>
              {examples.map(item => <TabsContent key={item.id} value={item.id} className="example-panel">
                <div className="relay-stage">
                  <svg className="relay-paths" viewBox="0 0 1100 310" fill="none" preserveAspectRatio="none" aria-hidden="true"><path className="path-base" d="M220 125 C370 125 350 230 550 230 C750 230 730 125 880 125" /><path className="path-base path-return" d="M220 158 C370 158 350 263 550 263 C750 263 730 158 880 158" /><path className="path-signal" d="M220 125 C370 125 350 230 550 230 C750 230 730 125 880 125" /><path className="path-signal signal-return" d="M220 158 C370 158 350 263 550 263 C750 263 730 158 880 158" /></svg>
                  <ChatWindow app="Codex" incoming={item.prompt} reply={item.first} />
                  <div className="messenger"><div className="messenger-orbit" aria-hidden="true" /><div className="messenger-icon"><Owl /></div><span className="messenger-name">errol</span><span className="relay-state"><span className="status-dot" /> Carrying the conversation</span></div>
                  <ChatWindow app="Claude" incoming={item.first} reply={item.second} />
                </div>
                <div className="seed"><span className="seed-label">YOUR BRIEF</span><p>{item.prompt}</p><ArrowRight size={17} aria-hidden="true" /></div>
              </TabsContent>)}
            </Tabs>
            <div className="demo-caption"><span>An example exchange. The possibilities are yours.</span><button className="motion-toggle" type="button" onClick={() => setMotionPaused(p => !p)} aria-pressed={motionPaused} aria-label={motionPaused ? 'Resume page animations' : 'Pause page animations'}>{motionPaused ? <Play size={12} /> : <Pause size={12} />}<span>{motionPaused ? 'Resume motion' : 'Pause motion'}</span></button></div>
          </div>
        </section>
        <section id="how-it-works" className="how-section shell" aria-labelledby="how-title">
          <div className="section-heading"><p className="eyebrow">YOUR IDEAS, WITH A LITTLE BACK-AND-FORTH</p><h2 id="how-title">You set the direction.<br /><span>Errol takes it from there.</span></h2><p>Brainstorm an idea. Challenge an assumption. Get a second pair of eyes on your code. All without being the copy-and-paste person in the middle.</p></div>
          <div className="steps"><article className="step"><span className="step-number">01 <span /></span><h3>Bring your two minds.</h3><p>Open Codex and Claude on your Mac. Their tools, memory, and context come along.</p></article><article className="step"><span className="step-number">02 <span /></span><h3>Give them something good.</h3><p>Choose a conversation style and write a brief. A question is all it takes.</p></article><article className="step"><span className="step-number">03 <span /></span><h3>Let the conversation fly.</h3><p>Errol relays each reply. You can end the session at any time and keep the transcript.</p></article></div>
          <div className="practical-note"><span><Sparkles size={15} /> Lives in your menu bar</span><span><Check size={15} /> Uses your existing AI apps</span><span><Check size={15} /> Saves a readable transcript</span></div>
          <p className="permission-note">Errol uses macOS Accessibility to copy and send messages. Give it the desktop while a conversation is running.</p>
        </section>
        <section className="closing shell" aria-labelledby="closing-title"><div className="closing-glow" aria-hidden="true" /><Owl className="closing-owl" /><p className="eyebrow">SOMETHING GOOD COULD COME OF THIS</p><h2 id="closing-title">Let it <em>fly.</em></h2><p>Your next idea deserves a conversation.</p><DownloadLink /><span className="download-note">Made for macOS. Built for the back-and-forth.</span></section>
      </main>
      <footer className="site-footer shell"><a href="#" className="brand" aria-label="Errol home"><Owl /><span>errol<span className="brand-dot">.</span></span></a><p>A quiet courier between two bright minds.</p><a className="text-link" href={REPO_URL} target="_blank" rel="noopener noreferrer">Made in the open <ArrowUpRight size={15} /></a></footer>
    </div>
  );
}
