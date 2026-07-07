import type { HistoryRecord } from '../types/privacy';
import { HistoryTimeline } from './RiskComponents';

interface HistoryListProps {
  records: HistoryRecord[];
}

export default function HistoryList({ records }: HistoryListProps) {
  return <HistoryTimeline records={records} />;
}
