import './how-it-works.css';
export function HowItWorks() {
  return (
    <section
      id="how-it-works"
      className="how-section shell"
      aria-labelledby="how-title"
    >
      <div className="section-heading">
        <p className="eyebrow">How it works</p>
        <h2 id="how-title">
          You set the topic.
          <br />
          <span>Errol does the relaying.</span>
        </h2>
        <p>
          It works the way a person would: copy the reply from one window, paste
          it into the other, press Send. Errol does that on every turn and never
          gets bored.
        </p>
      </div>
      <ol className="steps">
        <li className="step">
          <span className="step-number">
            01 <span />
          </span>
          <h3>Open both apps.</h3>
          <p>
            ChatGPT or Codex next to Claude, each with a conversation window
            open.
          </p>
        </li>
        <li className="step">
          <span className="step-number">
            02 <span />
          </span>
          <h3>Write the brief.</h3>
          <p>Pick a shape, type a sentence, press Run. A question is enough.</p>
        </li>
        <li className="step">
          <span className="step-number">
            03 <span />
          </span>
          <h3>Let them talk.</h3>
          <p>
            Errol copies each reply into the other app and presses Send, until
            both sides sign off.
          </p>
        </li>
      </ol>
    </section>
  );
}
