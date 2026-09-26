import './courier.css';

/**
 * The gold courier dot from the film, falling from a screen's bottom edge to
 * carry the reader down to the next one. The screen sets `--fall`, the drop.
 */
export function Courier() {
  return (
    <div className="courier" aria-hidden="true">
      <span />
    </div>
  );
}
