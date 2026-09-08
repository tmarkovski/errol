import { Lightbulb, MessageSquare, MessagesSquare } from 'lucide-react';
import './conversation-shapes.css';

/** The three shapes the panel ships with, in the order its picker shows them. */
const shapes = [
  {
    Icon: MessageSquare,
    name: 'Free chat',
    text: 'Hand over a question and let them take it wherever it goes.',
    example: 'Should we launch on the web or build a native Mac app?',
  },
  {
    Icon: Lightbulb,
    name: 'Brainstorm',
    text: 'Rounds of ideas before they narrow to a shortlist.',
    example: 'Twenty names for a notes app made for musicians.',
  },
  {
    Icon: MessagesSquare,
    name: 'Debate',
    text: 'One argues for, one against. You get the strongest case for each side.',
    example: 'One repo or many, for a five-person team?',
  },
];

export function ConversationShapes() {
  return (
    <section
      id="shapes"
      className="shapes-section band shell"
      aria-labelledby="shapes-title"
    >
      <div className="band-heading rise">
        <p className="eyebrow">Three shapes</p>
        <h2 id="shapes-title">Pick the kind of conversation you need.</h2>
      </div>
      <ul className="card-grid">
        {shapes.map(({ Icon, name, text, example }) => (
          <li key={name} className="feature-card rise">
            <span className="card-icon">
              <Icon size={17} strokeWidth={1.8} />
            </span>
            <h3>{name}</h3>
            <p>{text}</p>
            <p className="shape-example">{example}</p>
          </li>
        ))}
      </ul>
    </section>
  );
}
