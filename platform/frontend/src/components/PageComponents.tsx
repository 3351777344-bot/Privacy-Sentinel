import { RiskBadge } from './RiskComponents';

export function PageHero({
  eyebrow,
  title,
  copy,
  onBack
}: {
  eyebrow: string;
  title: string;
  copy: string;
  onBack: () => void;
}) {
  return (
    <header className="page-hero">
      <div>
        <p className="eyebrow">{eyebrow}</p>
        <h1>{title}</h1>
        <p>{copy}</p>
      </div>
      <button onClick={onBack}>返回安全中心</button>
    </header>
  );
}

export function ImageCompareCard({ title, imageUrl }: { title: string; imageUrl: string }) {
  return (
    <div className="compare-card">
      <strong>{title}</strong>
      <img src={imageUrl} alt={title} />
    </div>
  );
}

export function DecisionCard({
  title,
  ok,
  positive,
  negative
}: {
  title: string;
  ok: boolean;
  positive: string;
  negative: string;
}) {
  return (
    <section className={`card decision-card ${ok ? 'low' : 'high'}`}>
      <strong>{title}</strong>
      <RiskBadge level={ok ? 'low' : 'high'} compact />
      <p>{ok ? positive : negative}</p>
    </section>
  );
}
