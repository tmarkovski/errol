import { FileText, Pause, Square } from 'lucide-react';
import './in-control.css';

const controls = [
  {
    Icon: Pause,
    title: 'Pause to steer.',
    text: 'Drop in a note mid-run and it rides along with the next reply.',
  },
  {
    Icon: Square,
    title: 'End whenever.',
    text: 'The run closes when both sides sign off, or when you say so.',
  },
  {
    Icon: FileText,
    title: 'Keep the transcript.',
    text: 'Every conversation is saved as Markdown in your Documents folder.',
  },
];

export function InControl() {
  return (
    <section
      className="control-section band shell"
      aria-labelledby="control-title"
    >
      <h2 id="control-title" className="rise">
        You stay in the loop.
      </h2>
      <ul className="control-row">
        {controls.map(({ Icon, title, text }) => (
          <li key={title} className="control-item rise">
            <Icon size={18} strokeWidth={1.7} aria-hidden="true" />
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
