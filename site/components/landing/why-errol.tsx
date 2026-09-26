import { Layers, MousePointerClick, ShieldCheck } from 'lucide-react';
import { HarnessArt } from './harness-art';
import './why-errol.css';

const reasons = [
  {
    Icon: MousePointerClick,
    title: 'It drives your Mac, on purpose',
    text: 'It copies, pastes, and presses Send for you.',
  },
  {
    Icon: Layers,
    title: 'Each app keeps its own context',
    text: 'Your memory, projects, and tools stay in play.',
  },
  {
    Icon: ShieldCheck,
    title: 'Nothing sits in the middle',
    text: 'No account, no server, no API keys.',
  },
];

export function WhyErrol() {
  return (
    <section id="why" className="why shell" aria-labelledby="why-title">
      <div className="why-top">
        <div className="why-heading">
          <p className="why-eyebrow">
            <span className="status-dot" /> Why Errol
          </p>
          <h2 id="why-title">
            A harness that drives{' '}
            <span className="why-quiet">the apps you already use</span>
            <span className="why-dot">.</span>
          </h2>
          <p className="why-lead">
            Using ChatGPT and Claude together means endless copying and pasting
            between them. We built Errol to do the carrying.
          </p>
        </div>
        <HarnessArt />
      </div>
      <ul className="why-reasons">
        {reasons.map(({ Icon, title, text }) => (
          <li key={title}>
            <span className="why-chip" aria-hidden="true">
              <Icon size={16} strokeWidth={1.8} />
            </span>
            <div>
              <h3>{title}</h3>
              <p>{text}</p>
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}
