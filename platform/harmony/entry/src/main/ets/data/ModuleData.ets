import { ModuleDefinition } from '../models/SecurityModels';

export const MODULES: ModuleDefinition[] = [
  {
    id: 'privacy',
    icon: '◉',
    eyebrow: 'Privacy Sentinel',
    title: '隐私哨兵',
    moment: '分享前',
    description: '识别图片敏感信息，确认处理后再分享。',
    route: 'pages/PrivacyPage',
    accent: '#2563EB',
    tint: '#EAF2FF'
  },
  {
    id: 'code',
    icon: '</>',
    eyebrow: 'Code Guardian',
    title: '代码卫士',
    moment: '提交前',
    description: '检查代码片段或选择项目 ZIP，输出文件级风险报告。',
    route: 'pages/CodePage',
    accent: '#7C3AED',
    tint: '#F1EAFE'
  },
  {
    id: 'link',
    icon: '↗',
    eyebrow: 'Link Guard',
    title: '链接卫士',
    moment: '点击前',
    description: '静态判断协议、域名、参数与来源风险。',
    route: 'pages/LinkPage',
    accent: '#0F9F8F',
    tint: '#E7F8F5'
  },
  {
    id: 'doc',
    icon: '✓',
    eyebrow: 'Doc Shield',
    title: '提交护盾',
    moment: '上传前',
    description: '检查材料完整性、命名、格式和隐私。',
    route: 'pages/DocPage',
    accent: '#EA7C24',
    tint: '#FFF2E7'
  }
];
