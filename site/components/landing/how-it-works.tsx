import { Check, Sparkles } from 'lucide-react';
import './how-it-works.css';
export function HowItWorks() {
  return (
    <section
      id="how-it-works"
      className="how-section shell"
      aria-labelledby="how-title"
    >
      <div className="section-heading">
        <p className="eyebrow">YOUR IDEAS, WITH A LITTLE BACK-AND-FORTH</p>
        <h2 id="how-title">
          You set the direction.
          <br />
          <span>Errol takes it from there.</span>
        </h2>
        <p>
          Brainstorm an idea. Challenge an assumption. Get a second pair of eyes
          on your code. All without being the copy-and-paste person in the
          middle.
        </p>
      </div>
      <div className="steps">
        <article className="step">
          <span className="step-number">
            01 <span />
          </span>
          <h3>Bring your two minds.</h3>
          <p>
            Open ChatGPT or Codex alongside Claude on your Mac. Their tools,
            memory, and context come along.
          </p>
        </article>
        <article className="step">
          <span className="step-number">
            02 <span />
          </span>
          <h3>Give them something good.</h3>
          <p>
            Choose a conversation style and write a brief. A question is all it
            takes.
          </p>
        </article>
        <article className="step">
          <span className="step-number">
            03 <span />
          </span>
          <h3>Let the conversation fly.</h3>
          <p>
            Errol relays each reply. Pause to steer the discussion, or end it
            and keep the transcript.
          </p>
        </article>
      </div>
      <div className="practical-note">
        <span>
          <Sparkles size={15} /> Lives in your menu bar
        </span>
        <span>
          <Check size={15} /> Uses your existing AI apps
        </span>
        <span>
          <Check size={15} /> Saves a readable transcript
        </span>
      </div>
      <p className="permission-note">
        Errol uses macOS Accessibility to copy and send messages. Give it the
        desktop while a conversation is running.
      </p>
    </section>
  );
}
