import './shared.css';

export function Owl({ className = '' }: { className?: string }) {
  return (
    <img
      className={`owl ${className}`}
      src="/errol.svg"
      width="40"
      height="40"
      alt=""
    />
  );
}

export function Brand() {
  return (
    <a href="#" className="brand" aria-label="Errol home">
      <Owl />
      <span>
        errol<span className="brand-dot">.</span>
      </span>
    </a>
  );
}
