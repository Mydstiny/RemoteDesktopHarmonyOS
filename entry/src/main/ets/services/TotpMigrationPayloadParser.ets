/**
 * Google Authenticator "Transfer accounts" export: otpauth-migration://offline?data=<base64 protobuf>.
 *
 * MigrationPayload {
 *   repeated OtpParameters otp_parameters = 1; int32 version = 2; int32 batch_size = 3;
 *   int32 batch_index = 4; int32 batch_id = 5;
 * }
 * OtpParameters {
 *   bytes secret = 1; string name = 2; string issuer = 3;
 *   Algorithm algorithm = 4;   // 0 unspecified, 1 SHA1, 2 SHA256, 3 SHA512, 4 MD5
 *   DigitCount digits = 5;     // 0 unspecified, 1 six, 2 eight
 *   OtpType type = 6;          // 0 unspecified, 1 HOTP, 2 TOTP
 *   int64 counter = 7;
 * }
 *
 * Pure parsing only (no platform APIs) so the decoder is host-testable.
 */
export const OTPAUTH_MIGRATION_SCHEME: string = 'otpauth-migration://';

export interface TotpMigrationAccount {
  issuer: string;
  account: string;
  /** RFC 4648 base32 without padding. */
  secret: string;
  algorithm: string; // 'SHA1' | 'SHA256' | 'SHA512'
  digits: number;
}

export interface TotpMigrationParseResult {
  ok: boolean;
  accounts: TotpMigrationAccount[];
  /** HOTP (counter based) or MD5 accounts this app cannot generate codes for. */
  skipped: number;
  batchIndex: number;
  batchSize: number;
  error: string;
}

export function isOtpAuthMigrationUri(value: string): boolean {
  return value.trim().toLowerCase().startsWith(OTPAUTH_MIGRATION_SCHEME);
}

const BASE64_ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const BASE32_ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/** Standard or URL-safe base64, padding optional; null on any invalid character. */
export function decodeMigrationBase64(text: string): Uint8Array | null {
  const cleaned: string = text.replace(/[\s]/g, '').replace(/-/g, '+').replace(/_/g, '/').replace(/=+$/, '');
  if (cleaned.length === 0 || cleaned.length % 4 === 1) { return null; }
  const out: number[] = [];
  let buffer: number = 0;
  let bits: number = 0;
  for (let i = 0; i < cleaned.length; i++) {
    const value: number = BASE64_ALPHABET.indexOf(cleaned.charAt(i));
    if (value < 0) { return null; }
    buffer = (buffer << 6) | value;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.push((buffer >> bits) & 0xFF);
    }
  }
  return new Uint8Array(out);
}

export function encodeBase32(bytes: Uint8Array): string {
  let out: string = '';
  let buffer: number = 0;
  let bits: number = 0;
  for (let i = 0; i < bytes.length; i++) {
    buffer = ((buffer << 8) | bytes[i]) & 0xFFFF;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out += BASE32_ALPHABET.charAt((buffer >> bits) & 31);
    }
  }
  if (bits > 0) { out += BASE32_ALPHABET.charAt((buffer << (5 - bits)) & 31); }
  return out;
}

function decodeUtf8(bytes: Uint8Array): string {
  let out: string = '';
  let i: number = 0;
  while (i < bytes.length) {
    const b0: number = bytes[i];
    let code: number = 0xFFFD;
    let size: number = 1;
    if (b0 < 0x80) { code = b0; }
    else if ((b0 & 0xE0) === 0xC0 && i + 1 < bytes.length) {
      code = ((b0 & 0x1F) << 6) | (bytes[i + 1] & 0x3F); size = 2;
    } else if ((b0 & 0xF0) === 0xE0 && i + 2 < bytes.length) {
      code = ((b0 & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F); size = 3;
    } else if ((b0 & 0xF8) === 0xF0 && i + 3 < bytes.length) {
      code = ((b0 & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) | ((bytes[i + 2] & 0x3F) << 6) |
        (bytes[i + 3] & 0x3F);
      size = 4;
    }
    out += String.fromCodePoint(code);
    i += size;
  }
  return out;
}

class ProtoReader {
  private bytes: Uint8Array;
  private pos: number;
  private end: number;

  constructor(bytes: Uint8Array, start: number, end: number) {
    this.bytes = bytes;
    this.pos = start;
    this.end = end;
  }

  done(): boolean { return this.pos >= this.end; }

  /** Varints beyond 2^53 lose precision; no field used here needs them. */
  varint(): number {
    let result: number = 0;
    let multiplier: number = 1;
    for (let i = 0; i < 10; i++) {
      if (this.pos >= this.end) { throw new Error('truncated varint'); }
      const b: number = this.bytes[this.pos++];
      result += (b & 0x7F) * multiplier;
      if ((b & 0x80) === 0) { return result; }
      multiplier *= 128;
    }
    throw new Error('varint too long');
  }

  /** Returns [start, end) of a length-delimited field. */
  lengthDelimited(): number[] {
    const length: number = this.varint();
    const start: number = this.pos;
    if (length < 0 || start + length > this.end) { throw new Error('truncated field'); }
    this.pos = start + length;
    return [start, start + length];
  }

  skip(wireType: number): void {
    if (wireType === 0) { this.varint(); }
    else if (wireType === 1) { this.advance(8); }
    else if (wireType === 2) { this.lengthDelimited(); }
    else if (wireType === 5) { this.advance(4); }
    else { throw new Error('unsupported wire type ' + wireType.toString()); }
  }

  private advance(count: number): void {
    if (this.pos + count > this.end) { throw new Error('truncated field'); }
    this.pos += count;
  }
}

interface RawOtpParameters {
  secret: Uint8Array;
  name: string;
  issuer: string;
  algorithm: number;
  digits: number;
  type: number;
}

function parseOtpParameters(bytes: Uint8Array, start: number, end: number): RawOtpParameters {
  const reader: ProtoReader = new ProtoReader(bytes, start, end);
  const raw: RawOtpParameters = { secret: new Uint8Array(0), name: '', issuer: '', algorithm: 0, digits: 0, type: 0 };
  while (!reader.done()) {
    const key: number = reader.varint();
    const field: number = Math.floor(key / 8);
    const wireType: number = key % 8;
    if (wireType === 2 && (field === 1 || field === 2 || field === 3)) {
      const range: number[] = reader.lengthDelimited();
      const slice: Uint8Array = bytes.slice(range[0], range[1]);
      if (field === 1) { raw.secret = slice; }
      else if (field === 2) { raw.name = decodeUtf8(slice); }
      else { raw.issuer = decodeUtf8(slice); }
    } else if (wireType === 0 && field >= 4 && field <= 7) {
      const value: number = reader.varint();
      if (field === 4) { raw.algorithm = value; }
      else if (field === 5) { raw.digits = value; }
      else if (field === 6) { raw.type = value; }
    } else {
      reader.skip(wireType);
    }
  }
  return raw;
}

function failure(error: string): TotpMigrationParseResult {
  return { ok: false, accounts: [], skipped: 0, batchIndex: 0, batchSize: 1, error };
}

/** Parse the decoded MigrationPayload bytes. */
export function parseMigrationPayload(bytes: Uint8Array): TotpMigrationParseResult {
  const accounts: TotpMigrationAccount[] = [];
  let skipped: number = 0;
  let batchIndex: number = 0;
  let batchSize: number = 1;
  try {
    const reader: ProtoReader = new ProtoReader(bytes, 0, bytes.length);
    while (!reader.done()) {
      const key: number = reader.varint();
      const field: number = Math.floor(key / 8);
      const wireType: number = key % 8;
      if (field === 1 && wireType === 2) {
        const range: number[] = reader.lengthDelimited();
        const raw: RawOtpParameters = parseOtpParameters(bytes, range[0], range[1]);
        // HOTP needs a counter this app does not keep; MD5 is not a supported TOTP algorithm.
        if (raw.type === 1 || raw.algorithm === 4 || raw.secret.length === 0) { skipped++; continue; }
        let issuer: string = raw.issuer.trim();
        let account: string = raw.name.trim();
        const colon: number = account.indexOf(':');
        if (colon > 0) {
          const prefix: string = account.substring(0, colon).trim();
          if (issuer.length === 0 || issuer === prefix) {
            issuer = issuer.length === 0 ? prefix : issuer;
            account = account.substring(colon + 1).trim();
          }
        }
        accounts.push({
          issuer,
          account,
          secret: encodeBase32(raw.secret),
          algorithm: raw.algorithm === 2 ? 'SHA256' : (raw.algorithm === 3 ? 'SHA512' : 'SHA1'),
          digits: raw.digits === 2 ? 8 : 6
        });
      } else if (wireType === 0 && (field === 3 || field === 4)) {
        const value: number = reader.varint();
        if (field === 3) { batchSize = Math.max(1, value); } else { batchIndex = value; }
      } else {
        reader.skip(wireType);
      }
    }
  } catch (_error) {
    return failure('Google 验证器迁移码数据损坏，请重新导出');
  }
  if (accounts.length === 0) {
    return { ok: false, accounts, skipped, batchIndex, batchSize,
      error: skipped > 0 ? '迁移码里只有计数器型（HOTP）账户，暂不支持' : '迁移码里没有账户' };
  }
  return { ok: true, accounts, skipped, batchIndex, batchSize, error: '' };
}

/** Parse an otpauth-migration://offline?data=... URI (from a QR code or pasted text). */
export function parseOtpAuthMigrationUri(uri: string): TotpMigrationParseResult {
  const value: string = uri.trim();
  if (!isOtpAuthMigrationUri(value)) { return failure('不是 Google 验证器迁移码'); }
  const query: number = value.indexOf('?');
  if (query < 0) { return failure('迁移码缺少数据'); }
  let data: string = '';
  const pairs: string[] = value.substring(query + 1).split('&');
  for (let i = 0; i < pairs.length; i++) {
    const eq: number = pairs[i].indexOf('=');
    if (eq > 0 && pairs[i].substring(0, eq) === 'data') { data = pairs[i].substring(eq + 1); }
  }
  if (data.length === 0) { return failure('迁移码缺少数据'); }
  try { data = decodeURIComponent(data); } catch (_error) { return failure('迁移码编码无效'); }
  // A pasted URI may have had its '+' turned into spaces (form/URL decoding); base64 has no spaces.
  data = data.trim().replace(/ /g, '+');
  const bytes: Uint8Array | null = decodeMigrationBase64(data);
  if (bytes === null) { return failure('迁移码编码无效'); }
  return parseMigrationPayload(bytes);
}
