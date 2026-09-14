/**
 * Magic-bytes (file signature) table.
 *
 * Pure data + tiny helpers, no ArkTS APIs — unit-testable in plain Node.
 * The table intentionally stores short prefixes: a signature only needs to be
 * long enough to be unambiguous, because attackers cannot change the real
 * header of a file they still want the victim's software to open.
 */

export type FileKind =
  | 'executable'
  | 'library'
  | 'archive'
  | 'document'
  | 'image'
  | 'video'
  | 'audio'
  | 'font'
  | 'database'
  | 'disk'
  | 'shortcut'
  | 'certificate'
  | 'unknown';

export interface MagicSignature {
  /** Human label, e.g. `PE 可执行文件`. */
  label: string;
  kind: FileKind;
  /** Space separated uppercase hex, e.g. `4D 5A`. `??` matches any byte. */
  hex: string;
  /** Offset of the pattern from the start of the file. */
  offset: number;
  /** Optional second pattern (RIFF container payloads such as WAVE / AVI). */
  secondaryHex?: string;
  secondaryOffset?: number;
  /** Extensions that legitimately carry this signature. */
  extensions: string[];
  /** True when the format is directly executable on desktop platforms. */
  executable: boolean;
  /** Coarse container grouping used by the archive scanner. */
  container: string;
}

/** Formats that can be executed by a desktop OS or a script host. */
export const DANGEROUS_EXTENSIONS: string[] = [
  'exe', 'dll', 'sys', 'scr', 'ocx', 'cpl', 'com', 'pif', 'msi', 'msp',
  'bat', 'cmd', 'ps1', 'psm1', 'vbs', 'vbe', 'js', 'jse', 'wsf', 'wsh',
  'hta', 'jar', 'lnk', 'reg', 'inf', 'sct', 'sh', 'run', 'apk', 'app', 'dmg'
];

/** Extensions that are only dangerous when written twice, e.g. `a.pdf.exe`. */
export const DOUBLE_EXTENSION_TARGETS: string[] = [
  'exe', 'scr', 'bat', 'cmd', 'ps1', 'vbs', 'js', 'jse', 'wsf', 'wsh',
  'hta', 'jar', 'com', 'pif', 'msi', 'lnk', 'sct', 'sh', 'run', 'apk'
];

export const MAGIC_SIGNATURES: MagicSignature[] = [
  // ---------------------------------------------------------------- executables
  {
    label: 'PE 可执行文件（Windows）',
    kind: 'executable',
    hex: '4D 5A',
    offset: 0,
    extensions: ['exe', 'dll', 'sys', 'scr', 'ocx', 'cpl', 'com', 'pif'],
    executable: true,
    container: 'pe'
  },
  {
    label: 'ELF 可执行文件（Linux / 鸿蒙原生）',
    kind: 'executable',
    hex: '7F 45 4C 46',
    offset: 0,
    extensions: ['so', 'bin', 'elf', 'o', 'ko'],
    executable: true,
    container: 'elf'
  },
  {
    label: 'Mach-O 可执行文件（macOS 64 位）',
    kind: 'executable',
    hex: 'CF FA ED FE',
    offset: 0,
    extensions: ['macho', 'dylib', 'bundle'],
    executable: true,
    container: 'macho'
  },
  {
    label: 'Mach-O 可执行文件（macOS 32 位）',
    kind: 'executable',
    hex: 'CE FA ED FE',
    offset: 0,
    extensions: ['macho', 'dylib'],
    executable: true,
    container: 'macho'
  },
  {
    label: 'Mach-O 通用二进制 / Java class',
    kind: 'executable',
    hex: 'CA FE BA BE',
    offset: 0,
    extensions: ['class', 'macho', 'jar'],
    executable: true,
    container: 'macho'
  },
  {
    label: 'Windows 快捷方式',
    kind: 'shortcut',
    hex: '4C 00 00 00 01 14 02 00',
    offset: 0,
    extensions: ['lnk'],
    executable: true,
    container: 'lnk'
  },
  {
    label: '微软安装包 / OLE 复合文档',
    kind: 'document',
    hex: 'D0 CF 11 E0 A1 B1 1A E1',
    offset: 0,
    extensions: ['msi', 'msp', 'doc', 'xls', 'ppt', 'msg', 'vsd', 'mdb', 'one'],
    executable: false,
    container: 'ole'
  },
  {
    label: 'Debian 软件包',
    kind: 'archive',
    hex: '21 3C 61 72 63 68 3E',
    offset: 0,
    extensions: ['deb', 'ar'],
    executable: false,
    container: 'ar'
  },
  {
    label: 'RPM 软件包',
    kind: 'archive',
    hex: 'ED AB EE DB',
    offset: 0,
    extensions: ['rpm'],
    executable: false,
    container: 'rpm'
  },

  // ------------------------------------------------------------------- archives
  {
    label: 'ZIP 压缩包 / OOXML 文档',
    kind: 'archive',
    hex: '50 4B 03 04',
    offset: 0,
    extensions: [
      'zip', 'docx', 'docm', 'dotx', 'dotm', 'xlsx', 'xlsm', 'xltx', 'xltm',
      'xlam', 'pptx', 'pptm', 'potx', 'potm', 'ppam', 'sldx', 'sldm',
      'jar', 'apk', 'odt', 'ods', 'odp', 'epub', 'xpi', 'vsdx', 'kmz', 'ipa'
    ],
    executable: false,
    container: 'zip'
  },
  {
    label: 'ZIP 压缩包（空）',
    kind: 'archive',
    hex: '50 4B 05 06',
    offset: 0,
    extensions: [
      'zip', 'docx', 'docm', 'dotx', 'dotm', 'xlsx', 'xlsm', 'xltx', 'xltm',
      'xlam', 'pptx', 'pptm', 'potx', 'potm', 'ppam', 'jar', 'apk', 'odt', 'ods'
    ],
    executable: false,
    container: 'zip'
  },
  {
    label: 'GZIP 压缩流',
    kind: 'archive',
    hex: '1F 8B',
    offset: 0,
    extensions: ['gz', 'tgz'],
    executable: false,
    container: 'gzip'
  },
  {
    label: 'BZIP2 压缩流',
    kind: 'archive',
    hex: '42 5A 68',
    offset: 0,
    extensions: ['bz2', 'tbz2'],
    executable: false,
    container: 'bzip2'
  },
  {
    label: 'XZ 压缩流',
    kind: 'archive',
    hex: 'FD 37 7A 58 5A 00',
    offset: 0,
    extensions: ['xz', 'txz'],
    executable: false,
    container: 'xz'
  },
  {
    label: '7-Zip 压缩包',
    kind: 'archive',
    hex: '37 7A BC AF 27 1C',
    offset: 0,
    extensions: ['7z'],
    executable: false,
    container: '7z'
  },
  {
    label: 'RAR 压缩包（v4）',
    kind: 'archive',
    hex: '52 61 72 21 1A 07 00',
    offset: 0,
    extensions: ['rar'],
    executable: false,
    container: 'rar'
  },
  {
    label: 'RAR 压缩包（v5）',
    kind: 'archive',
    hex: '52 61 72 21 1A 07 01 00',
    offset: 0,
    extensions: ['rar'],
    executable: false,
    container: 'rar'
  },
  {
    label: 'Zstandard 压缩流',
    kind: 'archive',
    hex: '28 B5 2F FD',
    offset: 0,
    extensions: ['zst', 'tzst'],
    executable: false,
    container: 'zstd'
  },
  {
    label: 'LZ4 压缩流',
    kind: 'archive',
    hex: '04 22 4D 18',
    offset: 0,
    extensions: ['lz4'],
    executable: false,
    container: 'lz4'
  },
  {
    label: 'POSIX TAR 归档',
    kind: 'archive',
    hex: '75 73 74 61 72',
    offset: 257,
    extensions: ['tar'],
    executable: false,
    container: 'tar'
  },
  {
    label: 'CAB 安装包',
    kind: 'archive',
    hex: '4D 53 43 46',
    offset: 0,
    extensions: ['cab'],
    executable: false,
    container: 'cab'
  },
  {
    label: 'ARJ 归档',
    kind: 'archive',
    hex: '60 EA',
    offset: 0,
    extensions: ['arj'],
    executable: false,
    container: 'arj'
  },

  // ------------------------------------------------------------------ documents
  {
    label: 'PDF 文档',
    kind: 'document',
    hex: '25 50 44 46 2D',
    offset: 0,
    extensions: ['pdf'],
    executable: false,
    container: 'pdf'
  },
  {
    label: 'RTF 文档',
    kind: 'document',
    hex: '7B 5C 72 74 66 31',
    offset: 0,
    extensions: ['rtf'],
    executable: false,
    container: 'rtf'
  },
  {
    label: '帮助文档',
    kind: 'document',
    hex: '3F 5F 03 00',
    offset: 0,
    extensions: ['hlp'],
    executable: false,
    container: 'hlp'
  },

  // --------------------------------------------------------------------- images
  {
    label: 'PNG 图片',
    kind: 'image',
    hex: '89 50 4E 47 0D 0A 1A 0A',
    offset: 0,
    extensions: ['png'],
    executable: false,
    container: 'png'
  },
  {
    label: 'JPEG 图片',
    kind: 'image',
    hex: 'FF D8 FF',
    offset: 0,
    extensions: ['jpg', 'jpeg', 'jpe', 'jfif'],
    executable: false,
    container: 'jpeg'
  },
  {
    label: 'GIF 图片',
    kind: 'image',
    hex: '47 49 46 38',
    offset: 0,
    extensions: ['gif'],
    executable: false,
    container: 'gif'
  },
  {
    label: 'BMP 位图',
    kind: 'image',
    hex: '42 4D',
    offset: 0,
    extensions: ['bmp', 'dib'],
    executable: false,
    container: 'bmp'
  },
  {
    label: 'TIFF 图片（小端）',
    kind: 'image',
    hex: '49 49 2A 00',
    offset: 0,
    extensions: ['tif', 'tiff'],
    executable: false,
    container: 'tiff'
  },
  {
    label: 'TIFF 图片（大端）',
    kind: 'image',
    hex: '4D 4D 00 2A',
    offset: 0,
    extensions: ['tif', 'tiff'],
    executable: false,
    container: 'tiff'
  },
  {
    label: 'WebP 图片',
    kind: 'image',
    hex: '52 49 46 46',
    offset: 0,
    secondaryHex: '57 45 42 50',
    secondaryOffset: 8,
    extensions: ['webp'],
    executable: false,
    container: 'webp'
  },
  {
    label: 'ICO 图标',
    kind: 'image',
    hex: '00 00 01 00',
    offset: 0,
    extensions: ['ico', 'cur'],
    executable: false,
    container: 'ico'
  },
  {
    label: 'Photoshop 文档',
    kind: 'image',
    hex: '38 42 50 53',
    offset: 0,
    extensions: ['psd'],
    executable: false,
    container: 'psd'
  },
  {
    label: 'HEIC / MP4 容器',
    kind: 'video',
    hex: '66 74 79 70',
    offset: 4,
    extensions: ['mp4', 'm4v', 'mov', 'heic', 'heif', '3gp'],
    executable: false,
    container: 'isobmff'
  },

  // ---------------------------------------------------------------------- media
  {
    label: 'MP3 音频（ID3 标签）',
    kind: 'audio',
    hex: '49 44 33',
    offset: 0,
    extensions: ['mp3'],
    executable: false,
    container: 'mp3'
  },
  {
    label: 'FLAC 无损音频',
    kind: 'audio',
    hex: '66 4C 61 43',
    offset: 0,
    extensions: ['flac'],
    executable: false,
    container: 'flac'
  },
  {
    label: 'OGG 媒体容器',
    kind: 'audio',
    hex: '4F 67 67 53',
    offset: 0,
    extensions: ['ogg', 'oga', 'ogv'],
    executable: false,
    container: 'ogg'
  },
  {
    label: 'WAV 音频',
    kind: 'audio',
    hex: '52 49 46 46',
    offset: 0,
    secondaryHex: '57 41 56 45',
    secondaryOffset: 8,
    extensions: ['wav'],
    executable: false,
    container: 'wav'
  },
  {
    label: 'AVI 视频',
    kind: 'video',
    hex: '52 49 46 46',
    offset: 0,
    secondaryHex: '41 56 49 20',
    secondaryOffset: 8,
    extensions: ['avi'],
    executable: false,
    container: 'avi'
  },
  {
    label: 'Matroska / WebM 视频',
    kind: 'video',
    hex: '1A 45 DF A3',
    offset: 0,
    extensions: ['mkv', 'webm', 'mka'],
    executable: false,
    container: 'matroska'
  },
  {
    label: 'MIDI 音乐',
    kind: 'audio',
    hex: '4D 54 68 64',
    offset: 0,
    extensions: ['mid', 'midi'],
    executable: false,
    container: 'midi'
  },

  // ---------------------------------------------------------------------- fonts
  {
    label: 'TrueType 字体',
    kind: 'font',
    hex: '00 01 00 00',
    offset: 0,
    extensions: ['ttf', 'ttc'],
    executable: false,
    container: 'truetype'
  },
  {
    label: 'OpenType 字体',
    kind: 'font',
    hex: '4F 54 54 4F',
    offset: 0,
    extensions: ['otf'],
    executable: false,
    container: 'opentype'
  },
  {
    label: 'WOFF 网页字体',
    kind: 'font',
    hex: '77 4F 46 46',
    offset: 0,
    extensions: ['woff'],
    executable: false,
    container: 'woff'
  },
  {
    label: 'WOFF2 网页字体',
    kind: 'font',
    hex: '77 4F 46 32',
    offset: 0,
    extensions: ['woff2'],
    executable: false,
    container: 'woff2'
  },

  // ------------------------------------------------------------------ databases
  {
    label: 'SQLite 数据库',
    kind: 'database',
    hex: '53 51 4C 69 74 65 20 66 6F 72 6D 61 74 20 33 00',
    offset: 0,
    extensions: ['sqlite', 'db', 'sqlite3'],
    executable: false,
    container: 'sqlite'
  },

  // ---------------------------------------------------------------- disk images
  {
    label: 'VMware 虚拟磁盘',
    kind: 'disk',
    hex: '4B 44 4D',
    offset: 0,
    extensions: ['vmdk'],
    executable: false,
    container: 'vmdk'
  },
  {
    label: 'Hyper-V 虚拟磁盘',
    kind: 'disk',
    hex: '63 6F 6E 65 63 74 69 78',
    offset: 0,
    extensions: ['vhd', 'vhdx'],
    executable: false,
    container: 'vhd'
  },
  {
    label: 'QCOW 虚拟磁盘',
    kind: 'disk',
    hex: '51 46 49 FB',
    offset: 0,
    extensions: ['qcow', 'qcow2'],
    executable: false,
    container: 'qcow'
  },
  {
    label: 'Windows 注册表导出',
    kind: 'database',
    hex: '72 65 67 66',
    offset: 0,
    extensions: ['reg'],
    executable: false,
    container: 'regf'
  }
];

const HEX_ALPHABET: string = '0123456789ABCDEF';

/** Decode a `4D ?? 5A` style pattern into byte values, -1 marking a wildcard. */
export function decodeHexPattern(hex: string): number[] {
  const parts: string[] = hex.trim().split(' ');
  const out: number[] = [];
  for (let i = 0; i < parts.length; i++) {
    const token: string = parts[i];
    if (token.length === 0) {
      continue;
    }
    if (token === '??') {
      out.push(-1);
      continue;
    }
    const high: number = HEX_ALPHABET.indexOf(token.charAt(0).toUpperCase());
    const low: number = HEX_ALPHABET.indexOf(token.charAt(1).toUpperCase());
    if (high < 0 || low < 0) {
      continue;
    }
    out.push(high * 16 + low);
  }
  return out;
}

/** True when `data` matches the signature at its declared offset. */
export function matchesSignature(signature: MagicSignature, data: Uint8Array): boolean {
  const pattern: number[] = decodeHexPattern(signature.hex);
  if (!matchesAt(pattern, signature.offset, data)) {
    return false;
  }
  if (signature.secondaryHex !== undefined) {
    const secondary: number[] = decodeHexPattern(signature.secondaryHex);
    const secondaryOffset: number =
      signature.secondaryOffset !== undefined ? signature.secondaryOffset : 0;
    return matchesAt(secondary, secondaryOffset, data);
  }
  return true;
}

function matchesAt(pattern: number[], offset: number, data: Uint8Array): boolean {
  if (pattern.length === 0) {
    return false;
  }
  if (offset < 0 || offset + pattern.length > data.length) {
    return false;
  }
  for (let i = 0; i < pattern.length; i++) {
    const expected: number = pattern[i];
    if (expected === -1) {
      continue;
    }
    if (data[offset + i] !== expected) {
      return false;
    }
  }
  return true;
}

/**
 * Signature lookup order matters: the first table entry that matches wins.
 * Executable signatures are listed first so an `.exe` renamed to `.pdf` still
 * resolves to the PE entry instead of the PDF one.
 */
export function detectSignature(data: Uint8Array): MagicSignature | undefined {
  for (let i = 0; i < MAGIC_SIGNATURES.length; i++) {
    const candidate: MagicSignature = MAGIC_SIGNATURES[i];
    if (matchesSignature(candidate, data)) {
      return candidate;
    }
  }
  return undefined;
}

/** Lower-case extension without the leading dot; `''` when there is none. */
export function extensionOf(fileName: string): string {
  const dot: number = fileName.lastIndexOf('.');
  if (dot < 0 || dot === fileName.length - 1) {
    return '';
  }
  return fileName.substring(dot + 1).toLowerCase();
}

/** All trailing extensions, e.g. `a.tar.gz` -> `['tar','gz']`. */
export function trailingExtensions(fileName: string): string[] {
  const normalized: string = fileName.toLowerCase();
  const parts: string[] = normalized.split('.');
  if (parts.length <= 1) {
    return [];
  }
  const out: string[] = [];
  for (let i = 1; i < parts.length; i++) {
    if (parts[i].length > 0) {
      out.push(parts[i]);
    }
  }
  return out;
}

export function labelForKind(kind: FileKind): string {
  if (kind === 'executable') {
    return '可执行程序';
  }
  if (kind === 'library') {
    return '动态库';
  }
  if (kind === 'archive') {
    return '压缩归档';
  }
  if (kind === 'document') {
    return '文档';
  }
  if (kind === 'image') {
    return '图片';
  }
  if (kind === 'video') {
    return '视频';
  }
  if (kind === 'audio') {
    return '音频';
  }
  if (kind === 'font') {
    return '字体';
  }
  if (kind === 'database') {
    return '数据库';
  }
  if (kind === 'disk') {
    return '磁盘镜像';
  }
  if (kind === 'shortcut') {
    return '快捷方式';
  }
  if (kind === 'certificate') {
    return '证书';
  }
  return '未知类型';
}
