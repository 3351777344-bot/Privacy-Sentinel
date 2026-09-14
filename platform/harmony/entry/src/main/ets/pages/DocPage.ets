import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { AppHeader } from '../components/AppHeader';
import { ResultPanel } from '../components/ResultPanel';
import { SectionCard } from '../components/SectionCard';
import { DocCheckItem, DocCheckResponse, Finding } from '../models/SecurityModels';
import { ThreatScanReport } from '../models/ThreatModels';
import { GuardianApi } from '../services/GuardianApi';
import { HistoryStore } from '../services/HistoryStore';
import { ReputationClient, ReputationOutcome, ReputationQuery } from '../services/ReputationClient';
import { DEFAULT_REQUIREMENT, RequirementStore } from '../services/RequirementStore';
import { RequirementAudit, auditRequirement, scoreForFindings } from '../services/RequirementAudit';
import { RequirementHint, precheck } from '../services/scanners/RequirementKeywords';
import {
  appendFindings,
  buildLocalSummary,
  describeError,
  mergeFindings,
  riskLevelOfScore,
  toFindings,
  toFindingsFromThreat
} from '../services/ScanReportMapper';
import { SignatureDB } from '../services/SignatureDB';
import { ThreatScanner } from '../services/ThreatScanner';

/** Upper bound for an on-device scan; keeps peak memory predictable. */
const MAX_SCAN_BYTES: number = 12 * 1024 * 1024;

/** Placeholder hint shown before the brief has been pre-checked. */
const EMPTY_HINT: RequirementHint = { level: 'ok', message: '', tags: [] };

/** Debounce window for persisting keystrokes into KV-Store. */
const SAVE_DEBOUNCE_MS: number = 600;

/** Outcome of the on-device pass, before the optional server pass. */
interface LocalScanOutcome {
  findings: Finding[];
  score: number;
  scannedFiles: number;
  summary: string;
  /** What the device read out of the brief, for the attribution card. */
  localEcho: string;
}

@Entry
@Component
struct DocPage {
  /**
   * Persisted across page visits — this used to be a bare literal, so leaving
   * the page and returning reset the brief to the built-in sample and the next
   * scan silently ran against that instead of what the user typed.
   */
  @State requirementText: string = DEFAULT_REQUIREMENT;
  /** Exact brief the on-screen report was produced from. */
  @State scannedRequirement: string = '';
  /** Rules the server reported extracting, rendered under the report. */
  @State parsedEcho: string = '';
  /** Set when the brief or the file set changed after the last scan. */
  @State reportStale: boolean = false;
  @State hint: RequirementHint = EMPTY_HINT;
  @State selectedUris: string[] = [];
  @State selectedNames: string[] = [];
  @State findings: Finding[] = [];
  @State score: number = 100;
  @State statusMessage: string = '尚未选择材料';
  @State scanning: boolean = false;
  @State engineMessage: string = '';
  /** Result of the on-device naming/format audit of the brief, if any. */
  @State requirementNote: string = '';
  /** What the device read out of the brief, shown under the report. */
  @State localEcho: string = '';
  @State scannedCount: number = 0;
  /** Opt-in: allow a hash-only reputation lookup for suspicious files. */
  @State cloudAssist: boolean = false;
  @State cloudNote: string = '';
  /** Pending debounced write of the brief; `-1` when idle. */
  private saveTimer: number = -1;
  /** Set once KV-Store has been read, so `onPageShow` can retry if it failed. */
  private requirementLoaded: boolean = false;

  private abilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    this.restoreRequirement();
  }

  /**
   * Also restore on every show. `aboutToAppear` runs before the page is fully
   * attached, so this is the path that actually guarantees a persisted brief is
   * picked up once storage is reachable.
   */
  onPageShow(): void {
    if (!this.requirementLoaded) {
      this.restoreRequirement();
    }
  }

  /**
   * Restore the persisted brief. Without this every visit started from the
   * hardcoded sample, so a changed requirement appeared to "revert".
   * Returns without touching the editor when storage is not readable yet —
   * `onPageShow` then retries.
   */
  private async restoreRequirement(): Promise<void> {
    let stored: string | undefined = undefined;
    try {
      stored = await RequirementStore.load(this.abilityContext());
    } catch (_) {
      stored = undefined;
    }
    if (stored === undefined) {
      return;
    }
    this.requirementLoaded = true;
    this.requirementText = stored;
    this.hint = precheck(stored);
  }

  /**
   * Handle an editor keystroke. The previously displayed report is flagged
   * stale the moment the brief changes — before this it simply stayed on
   * screen, still describing the earlier requirement.
   */
  private applyRequirementEdit(value: string): void {
    this.requirementText = value;
    this.hint = precheck(value);
    if (this.scannedCount > 0 || this.findings.length > 0) {
      this.reportStale = true;
    }
    this.scheduleSave(value);
  }

  private scheduleSave(value: string): void {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout(() => {
      this.saveTimer = -1;
      this.persistRequirement(value);
    }, SAVE_DEBOUNCE_MS);
  }

  private async persistRequirement(value: string): Promise<void> {
    try {
      await RequirementStore.save(this.abilityContext(), value);
    } catch (_) {
    }
  }

  aboutToDisappear(): void {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
      this.persistRequirement(this.requirementText);
    }
  }

  private async pickDocuments(): Promise<void> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = [
        '文档材料|.pdf,.docx,.doc,.txt,.md,.ppt,.pptx,.xlsx,.xls',
        '图片材料|.png,.jpg,.jpeg,.webp',
        '压缩与可执行|.zip,.rar,.7z,.tar,.gz,.exe,.msi,.bat,.cmd,.ps1,.sh',
        '含宏文档|.docm,.xlsm,.pptm'
      ];
      options.maxSelectNumber = 8;
      const result = await new picker.DocumentViewPicker().select(options);
      if (result.length === 0) {
        return;
      }
      this.selectedUris = result;
      this.selectedNames = result.map((uri: string): string => this.fileNameFromUri(uri));
      this.statusMessage = `已选择 ${result.length} 个文件，等待检查`;
      // A different file set invalidates any report already on screen.
      if (this.scannedCount > 0 || this.findings.length > 0) {
        this.reportStale = true;
      }
    } catch (error) {
      this.statusMessage = describeError(error, '未能打开系统文件选择器');
    }
  }

  private async scan(): Promise<void> {
    if (this.requirementText.trim().length === 0) {
      this.statusMessage = '请先填写提交要求';
      return;
    }
    if (this.selectedUris.length === 0) {
      this.statusMessage = '请至少选择一个材料文件';
      return;
    }
    // Snapshot the brief: everything below — and the report attribution —
    // refers to exactly this text, even if the editor changes mid-scan.
    const brief: string = this.requirementText.trim();
    this.scanning = true;
    this.statusMessage = '正在本机检查文件类型、结构与隐私风险…';
    await this.persistRequirement(brief);

    try {
      const local: LocalScanOutcome = await this.runLocalScan(brief);

      // The server pass is optional: a richer checklist when reachable, but the
      // on-device findings above already stand on their own when it is not.
      let backendFindings: Finding[] = [];
      let backendScore: number = 0;
      let backendSummary: string = '';
      let backendParseEcho: string = '';
      let backendReachable: boolean = false;
      try {
        const report: DocCheckResponse = await GuardianApi.checkDocuments(
          brief,
          this.selectedUris,
          this.selectedNames
        );
        const suggestion: string = report.suggestions.length > 0 ?
          report.suggestions[0] : '提交前打开每个文件进行最终复核。';
        backendFindings = report.checks.map((item: DocCheckItem): Finding => {
          return {
            title: item.label,
            evidence: item.evidence,
            suggestion: suggestion,
            riskLevel: item.riskLevel
          };
        });
        backendScore = report.score;
        backendSummary = report.summary;
        backendParseEcho = RequirementStore.describeParsed(report.parsedRequirements);
        backendReachable = true;
      } catch (_) {
        backendReachable = false;
      }

      this.scannedCount = local.scannedFiles;
      this.scannedRequirement = brief;
      this.parsedEcho = backendParseEcho;
      this.localEcho = local.localEcho;
      this.reportStale = false;
      this.findings = mergeFindings(local.findings, backendFindings);
      this.score = backendReachable ? Math.min(local.score, backendScore) : local.score;
      this.statusMessage = backendReachable
        ? `${local.summary}${backendSummary}`
        : `${local.summary}（服务端复核不可用；命名与格式已由端内引擎判定，材料清单与文本隐私未参与）`;

      await HistoryStore.add(this.abilityContext(), {
        module: 'doc',
        moduleLabel: '提交护盾',
        riskLevel: riskLevelOfScore(this.score),
        score: this.score,
        summary: this.statusMessage
      });
    } catch (error) {
      this.statusMessage = describeError(error, '材料检查失败');
    } finally {
      this.scanning = false;
    }
  }

  /**
   * Run every on-device scanner over each selected file, then audit the file
   * names against the brief.
   *
   * The naming/format audit needs only the names, so it is part of the local
   * pass — a correct verdict here does not depend on the server being reachable.
   */
  private async runLocalScan(brief: string): Promise<LocalScanOutcome> {
    const context: common.UIAbilityContext = this.abilityContext();
    let engineNote: string = '';
    try {
      await SignatureDB.ensureLoaded(context);
    } catch (_) {
    }
    engineNote = `端内引擎 L1 · 特征库 ${SignatureDB.metaLabel()}`;
    this.engineMessage = engineNote;
    this.cloudNote = '';
    this.requirementNote = '';

    const findings: Finding[] = [];
    let worstScore: number = 100;
    let scannedFiles: number = 0;
    let maliciousFiles: number = 0;
    let suspiciousFiles: number = 0;
    let unreadableFiles: number = 0;
    let cloudHits: number = 0;
    let cloudQueried: number = 0;
    const blacklist = SignatureDB.current();

    for (let index = 0; index < this.selectedUris.length; index++) {
      const fileName: string = this.selectedNames[index];
      try {
        const buffer: ArrayBuffer =
          await GuardianApi.readSelectedFile(this.selectedUris[index], MAX_SCAN_BYTES);
        const report: ThreatScanReport = ThreatScanner.scanFile(
          fileName,
          new Uint8Array(buffer),
          { blacklist: blacklist }
        );
        scannedFiles++;
        appendFindings(findings, toFindings(report, fileName));
        if (report.score < worstScore) {
          worstScore = report.score;
        }
        if (report.verdict === 'malicious') {
          maliciousFiles++;
        } else if (report.verdict === 'suspicious') {
          suspiciousFiles++;
          if (this.cloudAssist) {
            cloudQueried++;
            const query: ReputationQuery = {
              sha256: report.sha256,
              fileName: fileName,
              declaredExtension: DocPage.extensionOf(fileName),
              detectedType: report.detectedType,
              localVerdict: report.verdict,
              indicators: report.indicators
            };
            const outcome: ReputationOutcome = await ReputationClient.lookup(query);
            if (outcome.findings.length > 0) {
              cloudHits++;
              appendFindings(findings, toFindingsFromThreat(outcome.findings, fileName));
            }
          }
        }
      } catch (error) {
        unreadableFiles++;
        findings.push({
          title: `【${fileName}】无法在端内读取`,
          evidence: `${describeError(error, '读取失败')}；该文件未完成扫描。`,
          suggestion: '重新选择该文件，或先确认其大小未超出 12 MB 限制。',
          riskLevel: 'medium'
        });
      }
    }

    if (this.cloudAssist) {
      this.cloudNote = `已向情报库匿名查询 ${cloudQueried} 个可疑文件的哈希，命中 ${cloudHits} 个。`;
    }

    // Requirement audit: names and extensions only, nothing is uploaded. Its
    // findings enter the same list as the threat findings and, when the server
    // is unreachable, they are the only thing that moves the score.
    const audit: RequirementAudit = auditRequirement(brief, this.selectedNames);
    if (audit.findings.length > 0) {
      appendFindings(findings, audit.findings);
      const auditScore: number = scoreForFindings(audit.findings);
      if (auditScore < worstScore) {
        worstScore = auditScore;
      }
    }
    this.requirementNote = audit.note;
    const summary: string = audit.note.length > 0
      ? `${buildLocalSummary(scannedFiles, maliciousFiles, suspiciousFiles, unreadableFiles)}${audit.note}`
      : buildLocalSummary(scannedFiles, maliciousFiles, suspiciousFiles, unreadableFiles);

    return {
      findings: findings,
      score: worstScore,
      scannedFiles: scannedFiles,
      summary: summary,
      localEcho: audit.echo
    };
  }

  private fileNameFromUri(uri: string): string {
    const rawName = uri.substring(uri.lastIndexOf('/') + 1);
    return decodeURIComponent(rawName) || '未命名材料';
  }

  /** Lower-case extension including the dot, `''` when the name has none. */
  private static extensionOf(fileName: string): string {
    const dot: number = fileName.lastIndexOf('.');
    if (dot < 0 || dot === fileName.length - 1) {
      return '';
    }
    return fileName.substring(dot).toLowerCase();
  }

  build() {
    Column() {
      AppHeader({
        title: 'Doc Shield',
        subtitle: '材料上传前完整性检查'
      })

      Scroll() {
        Column() {
          SectionCard({
            title: '01 提交要求',
            copy: '输入要求和准备提交的文件名，先在端内完成格式、结构与隐私自查。'
          }) {
            TextArea({
              text: this.requirementText,
              placeholder: '粘贴完整提交要求'
            })
              .height(130)
              .fontSize(13)
              .backgroundColor('#F8FAFC')
              .borderRadius(12)
              .padding(11)
              .onChange((value: string) => {
                this.applyRequirementEdit(value);
              })

            if (this.hint.message.length > 0) {
              Text(this.hint.message)
                .fontSize(11)
                .fontColor(this.hint.level === 'weak' ? '#B45309' : '#94A3B8')
                .lineHeight(17)
                .margin({ top: 6 })
                .width('100%')
            }

            Text('待提交材料')
              .fontSize(12)
              .fontColor('#475569')
              .margin({ top: 12, bottom: 6 })

            Button(this.selectedNames.length > 0 ? '重新选择材料' : '从系统选择材料')
              .width('100%')
              .height(44)
              .fontSize(13)
              .fontColor('#C2410C')
              .backgroundColor('#FFEDD5')
              .borderRadius(12)
              .onClick(() => {
                this.pickDocuments();
              })

            if (this.selectedNames.length > 0) {
              Column() {
                ForEach(this.selectedNames, (fileName: string) => {
                  Text(`• ${fileName}`)
                    .fontSize(12)
                    .fontColor('#475569')
                    .lineHeight(19)
                    .width('100%')
                }, (fileName: string) => fileName)
              }
              .alignItems(HorizontalAlign.Start)
              .padding(10)
              .backgroundColor('#FFF7ED')
              .borderRadius(11)
              .margin({ top: 9 })
              .width('100%')
            }

            Row() {
              Column() {
                Text('可疑文件允许匿名云端复核')
                  .fontSize(13)
                  .fontColor('#172033')
                  .width('100%')
                Text('仅上传文件哈希与其中的域名，绝不上传文件本身')
                  .fontSize(11)
                  .fontColor('#94A3B8')
                  .lineHeight(17)
                  .margin({ top: 2 })
                  .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.cloudAssist })
                .selectedColor('#EA7C24')
                .onChange((isOn: boolean) => {
                  this.cloudAssist = isOn;
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .padding(11)
            .backgroundColor('#F8FAFC')
            .borderRadius(12)
            .margin({ top: 12 })

            Button(this.scanning ? '检查中…' : '开始提交前检查')
              .enabled(!this.scanning)
              .width('100%')
              .height(46)
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor(this.scanning ? '#94A3B8' : '#EA7C24')
              .borderRadius(13)
              .margin({ top: 12 })
              .onClick(() => {
                this.scan();
              })

            Text(this.statusMessage)
              .fontSize(12)
              .fontColor('#64748B')
              .lineHeight(19)
              .margin({ top: 9 })
              .width('100%')

            if (this.reportStale) {
              Text('提交要求或所选材料已改动，下方报告仍是上一次检查的结果。'
                + '请点上方按钮重新检查，否则你看到的是旧要求下的结论。')
                .fontSize(12)
                .fontColor('#B45309')
                .lineHeight(19)
                .padding(10)
                .backgroundColor('#FEF3C7')
                .borderRadius(11)
                .margin({ top: 9 })
                .width('100%')
            }

            if (this.scannedCount > 0 && !this.scanning) {
              Text(this.engineMessage)
                .fontSize(11)
                .fontColor('#94A3B8')
                .lineHeight(18)
                .margin({ top: 4 })
                .width('100%')

              if (this.requirementNote.length > 0) {
                Text(this.requirementNote)
                  .fontSize(11)
                  .fontColor('#94A3B8')
                  .lineHeight(18)
                  .margin({ top: 2 })
                  .width('100%')
              }

              if (this.cloudNote.length > 0) {
                Text(this.cloudNote)
                  .fontSize(11)
                  .fontColor('#94A3B8')
                  .lineHeight(18)
                  .margin({ top: 2 })
                  .width('100%')
              }
            }
          }

          if (this.scannedRequirement.length > 0) {
            Column() {
              Text('本次报告依据的提交要求')
                .fontSize(12)
                .fontColor('#475569')
                .width('100%')
              Text(this.scannedRequirement)
                .fontSize(12)
                .fontColor('#172033')
                .lineHeight(19)
                .margin({ top: 4 })
                .width('100%')
              if (this.parsedEcho.length > 0) {
                Text(`服务端解析出的规则：${this.parsedEcho}`)
                  .fontSize(11)
                  .fontColor('#64748B')
                  .lineHeight(18)
                  .margin({ top: 6 })
                  .width('100%')
              }
              if (this.localEcho.length > 0) {
                Text(`端内解析出的规则：${this.localEcho}`)
                  .fontSize(11)
                  .fontColor('#64748B')
                  .lineHeight(18)
                  .margin({ top: 2 })
                  .width('100%')
              }
            }
            .alignItems(HorizontalAlign.Start)
            .padding(11)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .margin({ top: 12 })
            .width('100%')
          }

          ResultPanel({
            findings: this.findings,
            score: this.score,
            emptyCopy: '检查材料缺失、格式、命名、文件结构与隐私风险。'
          })
          .margin({ top: 12 })
        }
        .padding({ left: 16, right: 16, bottom: 28 })
        .width('100%')
      }
      .layoutWeight(1)
    }
    .backgroundColor('#F4F7FB')
    .width('100%')
    .height('100%')
  }
}
