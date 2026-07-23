import { Finding, ScanReport } from '../models/SecurityModels';

function scoreFor(findings: Finding[]): number {
  let deduction: number = 0;
  findings.forEach((item: Finding) => {
    if (item.riskLevel === 'high') {
      deduction += 28;
    } else if (item.riskLevel === 'medium') {
      deduction += 16;
    } else {
      deduction += 7;
    }
  });
  return Math.max(0, 100 - deduction);
}

export class LocalRuleEngine {
  static scanCode(code: string): ScanReport {
    const findings: Finding[] = [];

    if (/(api[_-]?key|secret|token|password)\s*[:=]\s*['"][^'"]{4,}/i.test(code)) {
      findings.push({
        title: '疑似硬编码凭据',
        evidence: '检测到密钥、令牌或密码直接写入代码。',
        suggestion: '改用系统安全存储或运行时配置注入。',
        riskLevel: 'high'
      });
    }
    if (/(execute|query)\s*\([^)]*\+|SELECT.+\$\{/i.test(code)) {
      findings.push({
        title: '疑似 SQL 拼接',
        evidence: '查询语句可能拼接外部输入。',
        suggestion: '使用参数化查询，并限制数据库账号权限。',
        riskLevel: 'high'
      });
    }
    if (/(exec|system|spawn)\s*\(/i.test(code)) {
      findings.push({
        title: '危险命令执行',
        evidence: '发现系统命令或子进程调用。',
        suggestion: '使用固定命令白名单，禁止拼接用户输入。',
        riskLevel: 'high'
      });
    }
    if (/console\.log\s*\([^)]*(token|password|secret)/i.test(code)) {
      findings.push({
        title: '敏感信息日志',
        evidence: '日志输出中可能包含凭据。',
        suggestion: '移除敏感字段或在输出前完成脱敏。',
        riskLevel: 'medium'
      });
    }
    if (/http:\/\//i.test(code)) {
      findings.push({
        title: '非加密网络地址',
        evidence: '代码中存在 HTTP 明文地址。',
        suggestion: '优先使用 HTTPS，并校验证书与目标域名。',
        riskLevel: 'medium'
      });
    }

    return {
      findings: findings,
      score: scoreFor(findings)
    };
  }

  static scanLink(url: string, source: string): ScanReport {
    const findings: Finding[] = [];
    const normalized: string = url.trim().toLowerCase();

    if (normalized.length === 0) {
      findings.push({
        title: '尚未输入链接',
        evidence: '链接为空，无法完成静态判断。',
        suggestion: '粘贴完整 URL 后重新检查。',
        riskLevel: 'medium'
      });
    } else {
      if (!normalized.startsWith('https://')) {
        findings.push({
          title: '未使用 HTTPS',
          evidence: '链接未通过 HTTPS 加密传输。',
          suggestion: '不要提交账号或支付信息，优先查找官方 HTTPS 入口。',
          riskLevel: 'high'
        });
      }
      if (normalized.indexOf('xn--') >= 0 || /^[a-z]+:\/\/\d+\.\d+\.\d+\.\d+/i.test(normalized)) {
        findings.push({
          title: '可疑目标域名',
          evidence: '发现 Punycode 域名或 IP 直连形式。',
          suggestion: '通过学校官网或官方 App 重新进入目标服务。',
          riskLevel: 'high'
        });
      }
      if (/(login|verify|payment|password|redirect|token)=?/i.test(normalized)) {
        findings.push({
          title: '包含敏感操作关键词',
          evidence: 'URL 中出现登录、验证、支付、跳转或令牌字段。',
          suggestion: '核对域名、来源和页面证书，不要直接输入凭据。',
          riskLevel: 'medium'
        });
      }
      if (/(bit\.ly|t\.cn|tinyurl|dwz)/i.test(normalized)) {
        findings.push({
          title: '短链接隐藏目标',
          evidence: '短链接无法直接看出最终目标地址。',
          suggestion: '联系发送者确认，或从可信入口访问。',
          riskLevel: 'medium'
        });
      }
    }

    if (/(短信|陌生|群聊|私信)/.test(source)) {
      findings.push({
        title: '来源需要额外核验',
        evidence: '链接来自容易被仿冒或转发的渠道。',
        suggestion: '通过官方通知、教务系统或电话进行二次确认。',
        riskLevel: 'medium'
      });
    }

    return {
      findings: findings,
      score: scoreFor(findings)
    };
  }

  static scanDocument(requirement: string, fileNames: string): ScanReport {
    const findings: Finding[] = [];
    const requirements: string = requirement.trim();
    const names: string = fileNames.trim();

    if (requirements.length < 10) {
      findings.push({
        title: '提交要求不完整',
        evidence: '当前要求文本过短，无法覆盖格式、命名和材料清单。',
        suggestion: '粘贴完整课程或报名提交要求。',
        riskLevel: 'medium'
      });
    }
    if (names.length === 0) {
      findings.push({
        title: '尚未登记材料',
        evidence: '没有可供检查的文件名。',
        suggestion: '逐行输入准备提交的文件名。',
        riskLevel: 'high'
      });
    } else {
      if (!/\.(pdf|docx|txt|md)(\s|$)/im.test(names)) {
        findings.push({
          title: '文件格式可能不符合要求',
          evidence: '未发现常用文档后缀。',
          suggestion: '核对要求中的文件格式并重新导出。',
          riskLevel: 'medium'
        });
      }
      if (/(身份证|手机号|phone|idcard)/i.test(names)) {
        findings.push({
          title: '文件名包含隐私信息',
          evidence: '文件名疑似直接包含证件或手机号信息。',
          suggestion: '按学号或要求命名，避免暴露不必要的个人信息。',
          riskLevel: 'high'
        });
      }
      if (/(附件|承诺书|封面|签字)/.test(requirements) &&
        !/(附件|承诺书|封面|签字)/.test(names)) {
        findings.push({
          title: '可能缺少必需材料',
          evidence: '要求中提到附件、承诺书、封面或签字，但文件名中未体现。',
          suggestion: '按提交清单逐项复核，不要只检查主文档。',
          riskLevel: 'high'
        });
      }
    }

    return {
      findings: findings,
      score: scoreFor(findings)
    };
  }
}

