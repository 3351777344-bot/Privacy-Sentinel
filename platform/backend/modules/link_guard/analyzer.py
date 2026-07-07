from .report_generator import build_link_report
from .source_risk import evaluate_source
from .url_rules import normalize_url, run_url_rules


def analyze_link(url: str, source: str | None = None) -> dict:
    normalized_url = normalize_url(url)
    checks, suspicious_params = run_url_rules(normalized_url)
    source_risk = evaluate_source(source)
    return build_link_report(normalized_url, checks, suspicious_params, source_risk)

