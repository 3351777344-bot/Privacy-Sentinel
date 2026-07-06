import { DetectResult, HistoryRecord, MaskMode } from '../models/PrivacyModels';

export const mockDetectResult: DetectResult = {
  id: 'detect-20260706-001',
  imageName: 'order_share_preview.png',
  scene: '订单页面截图',
  riskLevel: 'high',
  score: 86,
  summary: '检测到手机号、收货地址、订单编号等高风险隐私信息，建议处理后再分享。',
  detectedAt: '2026-07-06 09:40',
  privacyItems: [
    {
      id: 'item-phone',
      type: 'phone',
      label: '手机号',
      valuePreview: '138****2796',
      riskLevel: 'high',
      suggestion: '建议完整打码，避免被反查身份。',
      rect: { x: 40, y: 138, width: 210, height: 34 }
    },
    {
      id: 'item-address',
      type: 'address',
      label: '收货地址',
      valuePreview: '上海市浦东新区***',
      riskLevel: 'high',
      suggestion: '建议隐藏街道、门牌号等精确位置。',
      rect: { x: 40, y: 186, width: 250, height: 58 }
    },
    {
      id: 'item-order',
      type: 'order',
      label: '订单编号',
      valuePreview: 'OD2026********1188',
      riskLevel: 'medium',
      suggestion: '建议打码中间字段，保留必要凭证信息。',
      rect: { x: 40, y: 300, width: 236, height: 32 }
    },
    {
      id: 'item-name',
      type: 'name',
      label: '收件人姓名',
      valuePreview: '李*',
      riskLevel: 'medium',
      suggestion: '建议保留姓氏或全部隐藏。',
      rect: { x: 40, y: 96, width: 92, height: 32 }
    }
  ]
};

export const maskModes: MaskMode[] = [
  {
    id: 'black',
    name: '黑条',
    description: '适合证件号、手机号、地址等强隐私信息'
  },
  {
    id: 'blur',
    name: '模糊',
    description: '适合聊天记录、头像、昵称等上下文信息'
  },
  {
    id: 'mosaic',
    name: '马赛克',
    description: '适合图片局部内容和复杂背景'
  }
];

export const historyRecords: HistoryRecord[] = [
  {
    id: 'history-001',
    title: '订单截图分享',
    scene: '订单页面',
    riskLevel: 'high',
    itemCount: 4,
    createdAt: '今天 09:40'
  },
  {
    id: 'history-002',
    title: '快递单照片',
    scene: '快递单',
    riskLevel: 'high',
    itemCount: 5,
    createdAt: '昨天 18:12'
  },
  {
    id: 'history-003',
    title: '聊天记录截图',
    scene: '聊天记录',
    riskLevel: 'medium',
    itemCount: 3,
    createdAt: '07-04 21:08'
  },
  {
    id: 'history-004',
    title: '旅游照片',
    scene: '照片',
    riskLevel: 'low',
    itemCount: 1,
    createdAt: '07-02 14:30'
  }
];

