import json
import re
import shutil
import uuid
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from PIL import Image, UnidentifiedImageError

from detector.mock_detector import detect_privacy_items
from image_processor.blur import apply_blur_mask
from image_processor.mask import apply_black_mask
from image_processor.mosaic import apply_mosaic_mask
from modules.doc_shield.completeness_checker import check_completeness
from modules.doc_shield.file_extractor import extract_file
from modules.doc_shield.format_checker import check_format
from modules.doc_shield.privacy_checker import check_privacy
from modules.doc_shield.report_generator import generate_report
from modules.doc_shield.requirement_parser import parse_requirement
from schemas.models import (
    DetectResponse,
    DocCheckResponse,
    HistoryRecord,
    LinkCheckRequest,
    LinkCheckResponse,
    MaskRequest,
    MaskResponse,
    ScamAnalyzeRequest,
    ScamAnalyzeResponse,
    TextFinding,
)


BASE_DIR = Path(__file__).resolve().parent
UPLOAD_DIR = BASE_DIR / "static" / "uploads"
PROCESSED_DIR = BASE_DIR / "static" / "processed"
HISTORY_FILE = BASE_DIR / "data" / "history.json"

for directory in [UPLOAD_DIR, PROCESSED_DIR, HISTORY_FILE.parent]:
    directory.mkdir(parents=True, exist_ok=True)
if not HISTORY_FILE.exists():
    HISTORY_FILE.write_text("[]", encoding="utf-8")

app = FastAPI(title="GuardianHub API", version="0.3.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.mount("/static", StaticFiles(directory=BASE_DIR / "static"), name="static")


def _load_history() -> list[dict]:
    try:
        return json.loads(HISTORY_FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []


def _save_history(records: list[dict]) -> None:
    HISTORY_FILE.write_text(json.dumps(records[:20], ensure_ascii=False, indent=2), encoding="utf-8")


def _append_history(record: HistoryRecord) -> None:
    records = _load_history()
    records.insert(0, record.model_dump())
    _save_history(records)


def _update_processed_history(image_id: str, processed_url: str) -> None:
    records = _load_history()
    for record in records:
        if record.get("imageId") == image_id:
            record["processedImageUrl"] = processed_url
            record["status"] = "已处理"
            break
    _save_history(records)


def _find_uploaded_image(image_id: str) -> Path:
    matches = list(UPLOAD_DIR.glob(f"{image_id}.*"))
    if not matches:
        raise HTTPException(status_code=404, detail="未找到对应图片，请先完成检测。")
    return matches[0]


def _level_from_score(score: int) -> str:
    if score >= 70:
        return "high"
    if score >= 35:
        return "medium"
    return "low"


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok", "message": "GuardianHub backend is running"}


@app.post("/api/detect", response_model=DetectResponse)
async def detect(file: UploadFile = File(...)) -> DetectResponse:
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="请上传图片文件。")

    extension = Path(file.filename or "upload.png").suffix.lower() or ".png"
    image_id = f"img_{uuid.uuid4().hex[:12]}"
    saved_path = UPLOAD_DIR / f"{image_id}{extension}"

    with saved_path.open("wb") as target:
        shutil.copyfileobj(file.file, target)

    try:
        with Image.open(saved_path) as image:
            image.verify()
    except (UnidentifiedImageError, OSError):
        saved_path.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail="图片无法识别，请更换 PNG/JPG 等常见格式。")

    original_url = f"/static/uploads/{saved_path.name}"
    result = detect_privacy_items(str(saved_path), image_id, original_url)
    _append_history(
        HistoryRecord(
            imageId=image_id,
            originalImageUrl=original_url,
            processedImageUrl=None,
            riskLevel=result.riskLevel,
            summary=result.summary,
            createdAt=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            status="待处理",
        )
    )
    return result


@app.post("/api/mask", response_model=MaskResponse)
def mask_image(request: MaskRequest) -> MaskResponse:
    if request.maskType not in {"black", "blur", "mosaic"}:
        raise HTTPException(status_code=400, detail="maskType 仅支持 black、blur、mosaic。")
    if not request.items:
        raise HTTPException(status_code=400, detail="请至少选择一个需要处理的隐私区域。")

    image_path = _find_uploaded_image(request.imageId)
    with Image.open(image_path) as image:
        if request.maskType == "black":
            output = apply_black_mask(image, request.items)
        elif request.maskType == "blur":
            output = apply_blur_mask(image, request.items)
        else:
            output = apply_mosaic_mask(image, request.items)

    processed_name = f"{request.imageId}_safe.png"
    processed_path = PROCESSED_DIR / processed_name
    output.save(processed_path, format="PNG")

    processed_url = f"/static/processed/{processed_name}"
    _update_processed_history(request.imageId, processed_url)
    return MaskResponse(processedImageUrl=processed_url, message="已完成安全处理。")


@app.get("/api/history", response_model=list[HistoryRecord])
def history() -> list[HistoryRecord]:
    return [HistoryRecord(**record) for record in _load_history()]


@app.post("/api/scam/analyze", response_model=ScamAnalyzeResponse)
def analyze_scam(request: ScamAnalyzeRequest) -> ScamAnalyzeResponse:
    text = request.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="请输入需要分析的聊天文本。")

    rules = [
        ("索要验证码", r"验证码|短信码|校验码", 35, "high"),
        ("要求转账或垫付", r"转账|汇款|垫付|保证金|手续费|刷流水|解冻金", 35, "high"),
        ("中奖或补贴诱导", r"中奖|补贴|奖学金|助学金|返现|退款", 25, "medium"),
        ("制造紧迫感", r"截止|逾期|马上|立即|最后.*机会|今日.*失效", 20, "medium"),
        ("冒充身份", r"客服|老师|辅导员|学工|银行|公安|法院", 20, "medium"),
        ("可疑链接跳转", r"https?://|点击链接|扫码|二维码", 25, "medium"),
        ("刷单兼职", r"刷单|兼职|日结|佣金|拉群", 35, "high"),
        ("索要敏感资料", r"银行卡|身份证|密码|人脸|账号", 30, "high"),
    ]

    reasons: list[TextFinding] = []
    score = 0
    for label, pattern, weight, level in rules:
        match = re.search(pattern, text, flags=re.IGNORECASE)
        if match:
            score += weight
            start = max(match.start() - 12, 0)
            end = min(match.end() + 12, len(text))
            reasons.append(TextFinding(label=label, evidence=text[start:end], riskLevel=level))

    if not reasons:
        reasons.append(TextFinding(label="未命中高危话术", evidence="未发现典型诈骗关键词。", riskLevel="low"))

    risk_level = _level_from_score(score)
    suggestions = {
        "high": ["停止转账、提交验证码或填写银行卡。", "通过学校官网、辅导员或官方客服电话二次确认。", "保留聊天记录并向反诈或校园安全渠道反馈。"],
        "medium": ["不要直接点击对方发送的链接。", "核对通知来源，优先使用学校官方系统。", "涉及个人信息时先询问可信联系人。"],
        "low": ["当前未发现明显诈骗特征。", "仍建议不要在聊天中发送验证码、密码、身份证或银行卡信息。"],
    }[risk_level]

    return ScamAnalyzeResponse(riskLevel=risk_level, score=min(score, 100), reasons=reasons, suggestions=suggestions)


@app.post("/api/link/check", response_model=LinkCheckResponse)
def check_link(request: LinkCheckRequest) -> LinkCheckResponse:
    raw_url = request.url.strip()
    if not raw_url:
        raise HTTPException(status_code=400, detail="请输入需要检测的 URL。")

    normalized_url = raw_url if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", raw_url) else f"http://{raw_url}"
    parsed = urlparse(normalized_url)
    domain = parsed.hostname or ""
    checks: list[TextFinding] = []
    score = 0

    if parsed.scheme != "https":
        score += 25
        checks.append(TextFinding(label="未使用 HTTPS", evidence=parsed.scheme or "缺少协议", riskLevel="medium"))
    else:
        checks.append(TextFinding(label="HTTPS 检查通过", evidence="链接使用 HTTPS 加密传输。", riskLevel="low"))

    short_domains = {"bit.ly", "t.co", "tinyurl.com", "goo.gl", "ow.ly", "is.gd", "buff.ly", "suo.im"}
    if domain.lower() in short_domains:
        score += 35
        checks.append(TextFinding(label="短链接风险", evidence=domain, riskLevel="high"))

    suspicious_keywords = ["login", "verify", "gift", "bonus", "free", "pay", "bank", "password", "scholarship", "奖学金", "补贴"]
    hit_keywords = [keyword for keyword in suspicious_keywords if keyword.lower() in normalized_url.lower()]
    if hit_keywords:
        score += 25
        checks.append(TextFinding(label="可疑关键词", evidence="、".join(hit_keywords), riskLevel="medium"))

    is_ip = bool(re.fullmatch(r"\d{1,3}(\.\d{1,3}){3}", domain))
    has_many_hyphens = domain.count("-") >= 3
    lacks_dot = "." not in domain
    is_punycode = "xn--" in domain
    if is_ip or has_many_hyphens or lacks_dot or is_punycode:
        score += 30
        checks.append(TextFinding(label="域名异常", evidence=domain or "无法解析域名", riskLevel="high"))

    if not checks:
        checks.append(TextFinding(label="基础规则通过", evidence="未发现短链接、可疑关键词或异常域名。", riskLevel="low"))

    risk_level = _level_from_score(score)
    suggestions = {
        "high": ["不要直接打开该链接。", "使用学校或服务商官网入口重新访问。", "如来自聊天消息，先向发送者线下确认。"],
        "medium": ["打开前核对域名和页面证书。", "不要在该页面填写验证码、密码、身份证或银行卡。"],
        "low": ["当前基础规则未发现明显风险。", "仍建议确认页面来源和收件上下文。"],
    }[risk_level]

    return LinkCheckResponse(riskLevel=risk_level, normalizedUrl=normalized_url, checks=checks, suggestions=suggestions)


@app.post("/api/doc/check", response_model=DocCheckResponse)
async def check_doc(
    requirement_text: str = Form(...),
    files: list[UploadFile] = File(...),
) -> DocCheckResponse:
    requirement_text = requirement_text.strip()
    if not requirement_text:
        raise HTTPException(status_code=400, detail="请输入提交要求。")
    if not files:
        raise HTTPException(status_code=400, detail="请至少上传一个材料文件。")

    parsed_requirements = parse_requirement(requirement_text)
    extracted_files = []
    for file in files:
        content = await file.read()
        file_name = (file.filename or "未命名材料").strip()
        extracted_files.append(extract_file(file_name, file.content_type, content))

    checks = [
        *check_format(extracted_files, parsed_requirements),
        *check_completeness(extracted_files, parsed_requirements),
        *check_privacy(extracted_files),
    ]
    report = generate_report(parsed_requirements, extracted_files, checks)
    return DocCheckResponse(**report)
