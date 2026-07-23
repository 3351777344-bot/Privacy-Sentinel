# GuardianHub 作品说明文档模板执行约定

## Reference

- Retained reference: `C:\Users\33517\AppData\Local\Temp\2026中国高校计算机大赛人工智能创意赛初赛（鸿蒙赛道）作品说明文档模板.docx`
- SHA-256: `6B858AEA863D9552AF4E7E625B6B940519DBA489E6241AEDD10F108DE0307E2F`
- Cached page count: 6
- Section count: 1
- Structural evidence:
  - `E:\GuardianHub\.codex\harmony_submission_doc\template_structure.json`
  - `E:\GuardianHub\.codex\harmony_submission_doc\template_summary.txt`
  - `E:\GuardianHub\.codex\harmony_submission_doc\template-style-evidence.json`
  - `E:\GuardianHub\.codex\harmony_submission_doc\template_package_inventory.json`
- Visual reference rendering was attempted with the packaged renderer. LibreOffice/soffice is not installed, so the reference could not be rasterized by that renderer.

## Page system

- One A4 portrait section: 8.26 × 11.69 inches.
- Actual section margins: left/right 1.25 inches; top/bottom 1.00 inch.
- Header distance: approximately 0.591 inch.
- Footer distance: approximately 0.590 inch.
- No different first page, odd/even page, column, or landscape pattern.
- Two explicit page breaks and four cached rendered-page breaks are present in the reference.
- Final document must remain A4 portrait, one section, and under the official 20-page body limit.

## Typography and paragraph system

- Template cover and instructional furniture use direct formatting with `HarmonyOS Sans SC`.
- Cover event title: centered, 20 pt, bold.
- Cover document title: centered, 28 pt, bold.
- Cover metadata lines: centered, 18 pt.
- Team/originality headings: centered, 20 pt, bold.
- The template's written submission rule is authoritative for newly authored body content:
  - Font: SimSun (`宋体`).
  - Main title: 22 pt, bold.
  - Author/metadata emphasis: 16 pt, bold where used.
  - Level 1 heading: 16 pt, bold.
  - Level 2 heading: 14 pt, bold.
  - Level 3 heading: 12 pt, bold.
  - Body: 10.5 pt.
  - Single line spacing.
- Newly added captions use 10.5 pt SimSun, centered.
- Newly added body paragraphs use first-line indent of two Chinese characters and justified alignment.

## Lists, tables, and figures

- The reference contains one 14-row, 12-grid-column team information table with merged cells.
- Preserve the table's row/column merges, border system, widths, fills, and section labels.
- Replace only the example/help text in semantic value cells. Unknown personal data remains explicitly marked `【待填写】`.
- Do not invent member, school, contact, teacher, or signature data.
- All inserted figures are inline, centered, with captions formatted `图 N  名称`.
- Figures:
  1. GuardianHub user interaction flow.
  2. Technical architecture and HarmonyOS capability mapping.
  3. Privacy Sentinel synthetic before/after example.

## Content flow and slot map

1. Cover page (`word/document.xml`, body blocks B0-B20)
   - Preserve event and template titles.
   - Rewrite school, team, work, direction, captain, and phone metadata lines.
   - Unknown personal fields remain `【待填写】`.
2. Content overview page (B21-B44)
   - Replace the generic list with a concise final-document directory.
3. Team information (`B45-B47`, table 0)
   - Fill work name and selected direction.
   - Keep team/school/member/teacher personal fields as `【待填写】`.
   - Replace team strengths with evidence-based project capability text.
4. Originality statement (`B48-B74`)
   - Replace the placeholder work name with `GuardianHub 数字安全防护平台`.
   - Preserve declaration text, signature space, dates, and note.
5. Submission instructions (`B75-B132`)
   - Remove from the final copy.
   - Replace with authored submission body:
     - Creative description (30 Chinese characters or fewer).
     - Design/technical plan with three figures and implementation notes.
     - Project introduction (800 non-whitespace characters or fewer).
     - HarmonyOS feature evidence and current validation status.

## Package preservation

- Preserve section properties, styles, numbering, theme, font table, headers, footers, document relationships, existing table geometry, and declaration content unless explicitly listed as editable above.
- Existing custom XML parts and relationships are preserve-only.
- New media relationships and document XML changes are allowed only for the three figures and authored body.
- The reference file must remain byte-for-byte unchanged.

## Fidelity gates

- Verify the reference hash immediately before building and again before delivery.
- Confirm one A4 portrait section and unchanged margin/header/footer geometry.
- Confirm the team table retains 14 rows, 12 grid columns, and all original merged-cell topology.
- Confirm declaration wording and signature areas remain intact.
- Confirm all personal placeholders are visibly marked and no personal fact was invented.
- Confirm the 30-character creative sentence is within its limit.
- Confirm the introduction body is at most 800 non-whitespace characters.
- Confirm figure captions are sequential and images are not cropped.
- Confirm page count is below 20.
- Because LibreOffice is unavailable, use package, style, section, image, font, placeholder, and XML audits. If a compatible renderer remains unavailable, disclose the visual-render limitation on delivery.
