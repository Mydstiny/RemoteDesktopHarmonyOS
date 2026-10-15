/**
 * RustDeskRelayKeyPolicy — relay public-key and shared-access-key rules.
 *
 * RustDesk hbbs/hbbr `-k` is compared with the client protobuf
 * `licence_key` as text.  It is therefore not always an Ed25519 public key:
 * a server administrator may intentionally configure an arbitrary shared
 * access value.  Keep the two meanings explicit so a shared value is never
 * silently transformed into a (different) public key.
 */
import { util } from '@kit.ArkTS';

export type RustDeskRelayKeyMode = 'auto' | 'server_public_key' | 'shared_access_key';

export const RUSTDESK_RELAY_KEY_MODE_AUTO: RustDeskRelayKeyMode = 'auto';
export const RUSTDESK_RELAY_KEY_MODE_PUBLIC: RustDeskRelayKeyMode = 'server_public_key';
export const RUSTDESK_RELAY_KEY_MODE_SHARED: RustDeskRelayKeyMode = 'shared_access_key';

/** The source shape detected by the compatibility-first auto mode. */
export type RustDeskRelayKeyDetection =
  'empty' | 'public_key' | 'server_secret_key' | 'shared_access_key' |
  'server_keypair_reference' | 'invalid';

// `licence_key` is a protobuf string.  This is deliberately generous for an
// administrator supplied value while keeping a malformed paste from becoming
// an unbounded IPC/network payload.
export const RUSTDESK_SHARED_ACCESS_KEY_MAX_UTF8_BYTES: number = 4096;

const SHARED_STORAGE_PREFIX: string = 'rdsk-shared-v1:';

export interface RustDeskRelayKeyResolution {
  ok: boolean;
  mode: RustDeskRelayKeyMode;
  value: string;
  error: string;
  requiresInsecureConnectionWarning: boolean;
  detection: RustDeskRelayKeyDetection;
  /** A Base64-shaped value could still be an administrator-chosen -k text. */
  ambiguousWithSharedKey: boolean;
}

export interface RustDeskRelayStoredKey {
  key: string;
  mode: RustDeskRelayKeyMode;
}

function utf8Length(value: string): number {
  return new util.TextEncoder('utf-8').encodeInto(value).length;
}

interface PublicKeyAnalysis {
  normalized: string | null;
  detection: RustDeskRelayKeyDetection;
}

function publicKeyInput(value: string): string {
  let candidate: string = value.replace(/^\uFEFF/, '').trim();
  if ((candidate.startsWith('"') && candidate.endsWith('"')) ||
    (candidate.startsWith("'") && candidate.endsWith("'"))) {
    candidate = candidate.substring(1, candidate.length - 1).trim();
  }
  candidate = candidate.replace(/^key\s*=\s*/i, '').trim();
  if ((candidate.startsWith('"') && candidate.endsWith('"')) ||
    (candidate.startsWith("'") && candidate.endsWith("'"))) {
    candidate = candidate.substring(1, candidate.length - 1).trim();
  }
  // Some deployment scripts export an OpenSSH-style line. RustDesk's own
  // id_ed25519.pub is normally the raw Base64 value, but accepting this
  // wrapper makes a copied key file harmlessly interoperable too.
  const tokens: string[] = candidate.split(/\s+/);
  if (tokens.length >= 2 && (tokens[0] === 'ssh-ed25519' || tokens[0] === 'ed25519')) {
    candidate = tokens[1];
  }
  return candidate.replace(/[\s\u200B-\u200D]/g, '');
}

function analyzePublicKey(value: string): PublicKeyAnalysis {
  const compact: string = publicKeyInput(value);
  if (compact.length === 0) {
    return { normalized: '', detection: 'empty' };
  }
  // `-k -` and `-k _` are server-side instructions to load/generate the
  // keypair. They are not values a client can send as licence_key.
  if (compact === '-' || compact === '_') {
    return { normalized: null, detection: 'server_keypair_reference' };
  }
  if (!/^[A-Za-z0-9+/_-]+={0,2}$/.test(compact)) {
    return { normalized: null, detection: 'invalid' };
  }
  const firstPadding: number = compact.indexOf('=');
  if (firstPadding >= 0 && firstPadding < compact.length - (compact.endsWith('==') ? 2 : 1)) {
    return { normalized: null, detection: 'invalid' };
  }
  if (compact.length % 4 === 1 || (firstPadding >= 0 && compact.length % 4 !== 0)) {
    return { normalized: null, detection: 'invalid' };
  }
  const base64: string = compact.replace(/-/g, '+').replace(/_/g, '/');
  const padded: string = base64 + '='.repeat((4 - base64.length % 4) % 4);
  try {
    const bytes: Uint8Array = new util.Base64Helper().decodeSync(padded);
    if (bytes.length !== 32 && bytes.length !== 64) {
      return { normalized: null, detection: 'invalid' };
    }
    // rustdesk-server's get_server_sk() accepts a 64-byte Base64 secret and
    // uses its final 32 bytes as the public key sent to clients. Mirror that
    // exact rule so a pasted KEY value remains compatible with hbbs/hbbr.
    const publicBytes: Uint8Array = bytes.length === 32 ? bytes : bytes.slice(32, 64);
    return {
      normalized: new util.Base64Helper().encodeToStringSync(publicBytes),
      detection: bytes.length === 64 ? 'server_secret_key' : 'public_key'
    };
  } catch (_err) {
    return { normalized: null, detection: 'invalid' };
  }
}

/** Normalize only an explicit Ed25519 public key. */
export function normalizeRustDeskServerPublicKey(value: string): string | null {
  return analyzePublicKey(value).normalized;
}

function sharedAccessKeyError(value: string, required: boolean): string {
  if (value.length === 0) {
    return required ? '自定义共享准入 Key 不能为空' : '';
  }
  if (value.indexOf('\0') >= 0) {
    return '自定义共享准入 Key 不能包含 NUL 字符';
  }
  if (utf8Length(value) > RUSTDESK_SHARED_ACCESS_KEY_MAX_UTF8_BYTES) {
    return '自定义共享准入 Key 超过 4 KB 协议限制';
  }
  return '';
}

/**
 * Resolve the value used by the RustDesk protocol.  Shared mode deliberately
 * does not trim, decode, pad, or otherwise rewrite the input.
 */
export function resolveRustDeskRelayKey(value: string, requestedMode: RustDeskRelayKeyMode =
  RUSTDESK_RELAY_KEY_MODE_AUTO, required: boolean = false): RustDeskRelayKeyResolution {
  const raw: string = value;
  if (requestedMode === RUSTDESK_RELAY_KEY_MODE_SHARED) {
    const error: string = sharedAccessKeyError(raw, true);
    return {
      ok: error === '', mode: RUSTDESK_RELAY_KEY_MODE_SHARED, value: raw, error,
      requiresInsecureConnectionWarning: error === '', detection: 'shared_access_key',
      ambiguousWithSharedKey: false
    };
  }

  const analysis: PublicKeyAnalysis = analyzePublicKey(raw);
  const normalized: string | null = analysis.normalized;
  if (requestedMode === RUSTDESK_RELAY_KEY_MODE_PUBLIC) {
    if (normalized === null) {
      const keyPairError: string = analysis.detection === 'server_keypair_reference'
        ? 'RustDesk 的 -k - 或 -k _ 只是服务器加载密钥对的标记，请粘贴 id_ed25519.pub 中的公钥'
        : 'RustDesk 中继服务器公钥格式无效，应为 Base64 编码的 32 字节 Ed25519 公钥或服务器生成的 64 字节密钥材料';
      return {
        ok: false, mode: RUSTDESK_RELAY_KEY_MODE_PUBLIC, value: '',
        error: keyPairError, requiresInsecureConnectionWarning: false,
        detection: analysis.detection, ambiguousWithSharedKey: false
      };
    }
    if (normalized.length === 0 && required) {
      return {
        ok: false, mode: RUSTDESK_RELAY_KEY_MODE_PUBLIC, value: '', error: 'Server Pro 中继缺少服务器密钥',
        requiresInsecureConnectionWarning: false, detection: analysis.detection,
        ambiguousWithSharedKey: false
      };
    }
    return {
      ok: true, mode: RUSTDESK_RELAY_KEY_MODE_PUBLIC, value: normalized, error: '',
      requiresInsecureConnectionWarning: false, detection: analysis.detection,
      ambiguousWithSharedKey: analysis.detection === 'public_key' ||
        analysis.detection === 'server_secret_key'
    };
  }

  // Legacy/auto entries preserve old OSS behaviour for an empty value, use a
  // canonical public key where unambiguous, and otherwise act as a shared
  // access key. An imported raw `1:` value is not storage ciphertext: only
  // the encrypted storage reader has that context. New UI flows make this
  // selection explicit before saving.
  if (normalized !== null) {
    if (normalized.length === 0 && required) {
      return {
        ok: false, mode: RUSTDESK_RELAY_KEY_MODE_PUBLIC, value: '', error: 'Server Pro 中继缺少服务器密钥',
        requiresInsecureConnectionWarning: false, detection: analysis.detection,
        ambiguousWithSharedKey: false
      };
    }
    return {
      ok: true, mode: RUSTDESK_RELAY_KEY_MODE_PUBLIC, value: normalized, error: '',
      requiresInsecureConnectionWarning: false, detection: analysis.detection,
      ambiguousWithSharedKey: analysis.detection === 'public_key' ||
        analysis.detection === 'server_secret_key'
    };
  }
  if (analysis.detection === 'server_keypair_reference') {
    return {
      ok: false, mode: RUSTDESK_RELAY_KEY_MODE_PUBLIC, value: '',
      error: 'RustDesk 的 -k - 或 -k _ 只是服务器加载密钥对的标记，请粘贴 id_ed25519.pub 中的公钥',
      requiresInsecureConnectionWarning: false, detection: analysis.detection,
      ambiguousWithSharedKey: false
    };
  }
  const sharedError: string = sharedAccessKeyError(raw, required);
  return {
    ok: sharedError === '', mode: RUSTDESK_RELAY_KEY_MODE_SHARED, value: raw, error: sharedError,
    requiresInsecureConnectionWarning: sharedError === '', detection: 'shared_access_key',
    ambiguousWithSharedKey: false
  };
}

/** C ABI values consumed by rustdesk_ffi (0=legacy/auto, 1=public, 2=shared). */
export function rustDeskRelayKeyModeForFfi(value: string, mode: RustDeskRelayKeyMode): number {
  // Do not promote a legacy auto record that still looks like DataCrypto to
  // shared mode. New shared `1:` values are enveloped and carry explicit mode.
  if (mode === RUSTDESK_RELAY_KEY_MODE_AUTO && value.trimStart().startsWith('1:')) { return 1; }
  const resolved: RustDeskRelayKeyResolution = resolveRustDeskRelayKey(value, mode, false);
  return resolved.mode === RUSTDESK_RELAY_KEY_MODE_SHARED ? 2 : 1;
}

/**
 * Store shared text in an unambiguous envelope before DataCrypto encrypts the
 * relay column.  In particular, a genuine shared key beginning with `1:`
 * must never be mistaken for locked ciphertext after it is decrypted.
 */
export function rustDeskRelayKeyForStorage(value: string, mode: RustDeskRelayKeyMode): string {
  if (mode !== RUSTDESK_RELAY_KEY_MODE_SHARED) { return value; }
  const base64: string = new util.Base64Helper().encodeToStringSync(
    new util.TextEncoder('utf-8').encodeInto(value));
  return SHARED_STORAGE_PREFIX + base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

export function rustDeskRelayKeyFromStorage(value: string, fallbackMode: RustDeskRelayKeyMode =
  RUSTDESK_RELAY_KEY_MODE_AUTO): RustDeskRelayStoredKey {
  if (!value.startsWith(SHARED_STORAGE_PREFIX)) {
    return { key: value, mode: fallbackMode };
  }
  const payload: string = value.substring(SHARED_STORAGE_PREFIX.length);
  if (payload.length === 0 || !/^[A-Za-z0-9_-]+$/.test(payload)) {
    // Keep the stored value visible for recovery rather than silently turning
    // a damaged record into an empty credential.
    return { key: value, mode: fallbackMode };
  }
  const padded: string = payload.replace(/-/g, '+').replace(/_/g, '/') +
    '='.repeat((4 - payload.length % 4) % 4);
  try {
    const key: string = new util.TextDecoder('utf-8').decodeToString(
      new util.Base64Helper().decodeSync(padded));
    return { key, mode: RUSTDESK_RELAY_KEY_MODE_SHARED };
  } catch (_err) {
    return { key: value, mode: fallbackMode };
  }
}
