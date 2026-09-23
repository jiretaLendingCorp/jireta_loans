-- 00175: Rename the `mayors_permit` document type label to "Business Permit".
--
-- Ang code (`mayors_permit`) ay hindi binabago — naka-reference ito sa
-- account_upgrade_documents / application_documents / loan_documents at sa mga
-- allowlist ng kyc-submit / in-office-create / in-office-view. Ang LABEL lang
-- ang inaayos para "Business Permit" ang nakikita sa mga reviewer screen.
UPDATE document_types
SET label = 'Business Permit'
WHERE code = 'mayors_permit';

-- Face Recognition: nananatili ang document type (pwede pa ring i-submit),
-- pero OPTIONAL na ito sa Account Upgrade — nasa Flutter checklist / submit
-- screen ang required/optional flags, hindi sa DB.
