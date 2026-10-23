// supabase/functions/_shared/kyc_docs.test.ts
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  MAX_DOCUMENT_BYTES,
  MAX_VALID_ID_BYTES,
  REQUIRED_ACCOUNT_UPGRADE_DOCS,
  extensionOf,
  maxBytesForDocumentType,
  validateDocumentMeta,
  validateDocumentSet,
  validateDocumentSize,
} from "./kyc_docs.ts";

const MB = 1024 * 1024;

Deno.test("Valid ID (front at back) ang 10MB; iba 5MB", () => {
  assertEquals(maxBytesForDocumentType("valid_id"), MAX_VALID_ID_BYTES);
  assertEquals(maxBytesForDocumentType("valid_id_back"), MAX_VALID_ID_BYTES);
  assertEquals(maxBytesForDocumentType("selfie"), MAX_DOCUMENT_BYTES);
  assertEquals(maxBytesForDocumentType("mayors_permit"), MAX_DOCUMENT_BYTES);
  assertEquals(
    maxBytesForDocumentType("face_recognition"),
    MAX_DOCUMENT_BYTES,
  );
});

Deno.test("validateDocumentSize: hangganan ng Valid ID ay 10MB", () => {
  assertEquals(validateDocumentSize("valid_id", 9 * MB), null);
  assertEquals(validateDocumentSize("valid_id", 10 * MB), null);
  const tooBig = validateDocumentSize("valid_id", 10 * MB + 1);
  assertEquals(typeof tooBig, "string");
  assertEquals(tooBig?.includes("10MB"), true);
});

Deno.test("validateDocumentSize: ang ibang docs ay 5MB lang", () => {
  assertEquals(validateDocumentSize("selfie", 5 * MB), null);
  const tooBig = validateDocumentSize("selfie", 5 * MB + 1);
  assertEquals(typeof tooBig, "string");
  assertEquals(tooBig?.includes("5MB"), true);
  assertEquals(typeof validateDocumentSize("mayors_permit", 6 * MB), "string");
});

Deno.test("validateDocumentSize: blangko / negatibong laki ay invalid", () => {
  assertEquals(typeof validateDocumentSize("selfie", 0), "string");
  assertEquals(typeof validateDocumentSize("selfie", -5), "string");
  assertEquals(typeof validateDocumentSize("selfie", Number.NaN), "string");
});

Deno.test("extensionOf: kinukuha ang huling extension", () => {
  assertEquals(extensionOf("id.front.JPG"), "jpg");
  assertEquals(extensionOf("scan.pdf"), "pdf");
  assertEquals(extensionOf("no-extension"), "");
  assertEquals(extensionOf("trailing."), "");
  assertEquals(extensionOf(null), "");
});

Deno.test("validateDocumentMeta: extension at mime type", () => {
  assertEquals(
    validateDocumentMeta({ document_type: "selfie", file_name: "a.jpg" }),
    null,
  );
  assertEquals(
    validateDocumentMeta({
      document_type: "selfie",
      file_name: "a.jpg",
      mime_type: "image/jpeg",
    }),
    null,
  );
  assertEquals(
    typeof validateDocumentMeta({
      document_type: "selfie",
      file_name: "malware.exe",
    }),
    "string",
  );
  assertEquals(
    typeof validateDocumentMeta({
      document_type: "selfie",
      file_name: "a.jpg",
      mime_type: "application/zip",
    }),
    "string",
  );
});

const FULL_SET = [
  "valid_id",
  "valid_id_back",
  "selfie",
  "mayors_permit",
  "face_recognition",
];

Deno.test("validateDocumentSet: REQUIRED ang Valid ID at ang iba pang docs", () => {
  assertEquals(validateDocumentSet(FULL_SET), null);

  for (const missing of REQUIRED_ACCOUNT_UPGRADE_DOCS) {
    const set = FULL_SET.filter((t) => t !== missing);
    const error = validateDocumentSet(set);
    assertEquals(typeof error, "string");
    assertEquals(error?.includes(missing), true);
  }
});

Deno.test("validateDocumentSet: tinatanggihan ang duplicate", () => {
  const duplicate = validateDocumentSet([
    ...FULL_SET,
    "selfie",
  ]);
  assertEquals(typeof duplicate, "string");
  assertEquals(duplicate?.toLowerCase().includes("duplicate"), true);
});

Deno.test("validateDocumentSet: blangko at sobrang dami ay tinatanggihan", () => {
  assertEquals(typeof validateDocumentSet([]), "string");
  assertEquals(typeof validateDocumentSet(["", ...FULL_SET]), "string");

  const tooMany = new Array(11).fill(0).map((_, i) => `doc_${i}`);
  const error = validateDocumentSet(tooMany);
  assertEquals(typeof error, "string");
  assertEquals(error?.includes("Too many"), true);
});
