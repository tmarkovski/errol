import './faq.css';

const questions = [
  {
    q: 'Do I need API keys?',
    a: 'No. Errol drives the desktop apps, so it uses whatever plan you are signed into.',
  },
  {
    q: 'Which apps does it work with?',
    a: 'ChatGPT for Mac, including Codex mode, and Claude Desktop, including Claude Code sessions. Both need to be open with a conversation window.',
  },
  {
    q: 'Why does it need Accessibility access?',
    a: "It is how a Mac app reads another app's window and presses its buttons. Nothing is sent anywhere.",
  },
  {
    q: 'Can I join in?',
    a: 'Yes. Pause to steer lets you add a note that goes out with the next reply, and you can end the run at any point and keep the transcript.',
  },
];

export function Faq() {
  return (
    <section
      id="faq"
      className="faq-section band shell"
      aria-labelledby="faq-title"
    >
      <div className="band-heading rise">
        <p className="eyebrow">FAQ</p>
        <h2 id="faq-title">The four things people ask first.</h2>
      </div>
      <dl className="faq-list">
        {questions.map(({ q, a }) => (
          <div key={q} className="faq-item rise">
            <dt>{q}</dt>
            <dd>{a}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}
