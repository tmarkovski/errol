import { Laptop, Layers, ShieldCheck, Wallet } from 'lucide-react';
import './why-the-apps.css';

const reasons = [
  {
    Icon: Layers,
    title: 'Their context comes along',
    text: "Claude's projects, memory, and connected tools. Codex's threads, skills, and workspace. Nothing is flattened into a prompt.",
  },
  {
    Icon: Wallet,
    title: 'Your plan, not a metered key',
    text: 'It uses the subscriptions you are already signed into. Nothing to create, nothing to bill.',
  },
  {
    Icon: Laptop,
    title: 'Nothing leaves your Mac',
    text: 'Errol reads the two windows through macOS Accessibility and presses Copy and Send. There is no server in the middle.',
  },
];

export function WhyTheApps() {
  return (
    <section
      id="why-the-apps"
      className="why-section band shell"
      aria-labelledby="why-title"
    >
      <div className="band-heading rise">
        <p className="eyebrow">Why the apps, not the API</p>
        <h2 id="why-title">Both sides bring their whole selves.</h2>
        <p>
          Errol talks to the desktop apps, not the bare models. That is slower
          than an API loop, and it is the reason to use it.
        </p>
      </div>
      <ul className="card-grid">
        {reasons.map(({ Icon, title, text }) => (
          <li key={title} className="feature-card rise">
            <span className="card-icon">
              <Icon size={17} strokeWidth={1.8} />
            </span>
            <h3>{title}</h3>
            <p>{text}</p>
          </li>
        ))}
      </ul>
      <p className="why-note rise">
        <ShieldCheck size={15} strokeWidth={1.8} />
        <span>
          Errol asks for one permission, Accessibility. Give it the desktop
          while a conversation is running; it is typing on your behalf.
        </span>
      </p>
    </section>
  );
}
