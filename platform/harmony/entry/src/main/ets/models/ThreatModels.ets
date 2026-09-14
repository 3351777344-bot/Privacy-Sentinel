/**
 * Doc Shield threat model — device-side file security scanning.
 *
 * Pure data types shared by the L1 (ArkTS) scanners. Kept free of ArkTS-only
 * APIs so the scanner logic stays unit-testable outside the emulator.
 */

export type ThreatLevel = 'high' | 'medium' | 'low' | 'info';

export type ThreatCategory =
  | 'type-spoof'
  | 'archive-bomb'
  | 'archive-slip'
  | 'archive-nesting'
  | 'archive-encrypted'
  | 'credential-leak'
  | 'privacy-leak'
  | 'dangerous-script'
  | 'macro'
  | 'pe-structure'
  | 'pe-behavior'
  | 'entropy'
  | 'ioc'
  | 'signature-match';

export type ThreatVerdict = 'clean' | 'suspicious' | 'malicious' | 'unknown';

export interface ThreatFinding {
  /** Stable machine id, e.g. `type.double-extension`. */
  id: string;
  category: ThreatCategory;
  /** Short Chinese label shown in the UI. */
  label: string;
  /** One-line explanation of why this fired. */
  detail: string;
  level: ThreatLevel;
  /** Scanner that produced the finding. */
  source: string;
  /** Optional raw evidence (matched token, path, offset...). */
  evidence?: string;
}

export interface ThreatScanReport {
  fileName: string;
  fileSize: number;
  /** Lower-case hex SHA-256 of the scanned bytes. */
  sha256: string;
  /** Label derived from magic bytes. */
  detectedType: string;
  /** Label derived from the file extension. */
  declaredType: string;
  typeConsistent: boolean;
  /** MIME-ish container detected, e.g. `zip`, `pe`, `pdf`. */
  containerKind: string;
  findings: ThreatFinding[];
  /**
   * Network indicators pulled out of the file. Carried on the report so an
   * opt-in cloud lookup can submit them without rescanning the payload.
   */
  indicators: string[];
  verdict: ThreatVerdict;
  /** 0-100, 100 meaning no risk found. */
  score: number;
  durationMs: number;
  /** Which detection layers actually ran, e.g. `L1`. */
  layers: string;
  summary: string;
}

/** A byte range plus a printable-ASCII hint — used for text-side scanning. */
export interface TextChunk {
  offset: number;
  text: string;
}

/** Result of scanning a decodable text payload (plain file or archive entry). */
export interface ContentScanResult {
  findings: ThreatFinding[];
  textLength: number;
}
