-- 00149: Face Recognition document for the Account Upgrade flow.
-- A clear frontal face capture (required, below the Birth Certificate) used
-- for identity verification and visible to head manager / employee reviewers
-- like any other Account Upgrade document.

INSERT INTO document_types (code, label, sort_order)
VALUES ('face_recognition', 'Face Recognition', 18)
ON CONFLICT (code) DO NOTHING;