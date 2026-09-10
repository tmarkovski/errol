import './shared.css';

export function ErrolSymbol({ className = '' }: { className?: string }) {
  return (
    <img
      className={`errol-symbol ${className}`}
      src="/errol-symbol.svg"
      width="40"
      height="40"
      alt=""
    />
  );
}

export function Brand() {
  return (
    <a href="#" className="brand" aria-label="Errol home">
      <ErrolSymbol />
      <span>
        errol<span className="brand-dot">.</span>
      </span>
    </a>
  );
}
