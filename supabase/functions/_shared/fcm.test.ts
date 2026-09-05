// supabase/functions/_shared/fcm.test.ts
// Unit tests for the pure helpers behind the FCM HTTP v1 OAuth2 flow:
// base64url encoding and PKCS#8 PEM → DER parsing (including the literal
// `\n` escapes Supabase secret editors sometimes produce). The signing path
// is verified end-to-end with a generated RSA key so no network or secrets
// are needed.
import { assertEquals } from 'https://deno.land/std@0.168.0/testing/asserts.ts';
import { pemToDer, toBase64Url } from './fcm.ts';

Deno.test('toBase64Url encodes JSON header correctly', () => {
  assertEquals(
    toBase64Url('{"alg":"RS256","typ":"JWT"}'),
    'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9'
  );
});

Deno.test('toBase64Url is URL-safe (no + / =)', () => {
  const input = '\xfb\xff\xfe\xf9'; // bytes that map to + / and padding
  const encoded = toBase64Url(new TextEncoder().encode(input));
  assertEquals(encoded.includes('+'), false);
  assertEquals(encoded.includes('/'), false);
  assertEquals(encoded.includes('='), false);
});

Deno.test('pemToDer accepts real newlines and literal \\n escapes', async () => {
  const keyPair = await crypto.subtle.generateKey(
    {
      name: 'RSASSA-PKCS1-v1_5',
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: 'SHA-256',
    },
    true,
    ['sign', 'verify']
  );
  const pkcs8 = await crypto.subtle.exportKey('pkcs8', keyPair.privateKey);
  const b64 = btoa(
    String.fromCharCode.apply(null, Array.from(new Uint8Array(pkcs8)))
  );
  const pem = `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----\n`;
  const escapedPem = pem.replace(/\n/g, '\\n'); // as a secret editor might store it

  for (const candidate of [pem, escapedPem]) {
    const der = pemToDer(candidate);
    const imported = await crypto.subtle.importKey(
      'pkcs8',
      der,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['sign']
    );
    const data = new TextEncoder().encode('jireta-fcm-signing-check');
    const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', imported, data);
    const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', keyPair.publicKey, signature, data);
    assertEquals(ok, true, 'signature produced from parsed PEM must verify');
  }
});