#!/usr/bin/env python3
"""Generate a multi-page *visual* ERD (PDF) for the Jireta Loans Supabase schema.

Pipeline:  schema model -> per-page SVG -> one HTML document -> headless Chrome -> PDF

Usage:
    python scripts/generate_erd_pdf.py [--out <pdf path>] [--html <html path>]

Default output: ~/Desktop/jireta_loans_erd.pdf
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from datetime import date

# --------------------------------------------------------------------------------------
# Page geometry (SVG units == CSS px at 96dpi -> 1 unit = 1/96 inch)
# --------------------------------------------------------------------------------------
PAGE_W, PAGE_H = 1800, 1200
MARGIN_X, TOP, BOTTOM = 52, 96, 58
ROW_H, HDR_H, TAG_H, PAD_BOT = 15, 24, 14, 6
STACK_GAP = 54
BOX_GAP = 32
AVAIL_H = PAGE_H - TOP - BOTTOM
AVAIL_W = PAGE_W - 2 * MARGIN_X

HDD = date(2026, 10, 21).isoformat()

# --------------------------------------------------------------------------------------
# Domain styling
# --------------------------------------------------------------------------------------
GROUPS = {
    "identity": ("Identity & Access",        "#4338ca", "#eef2ff", "#c7d2fe"),
    "lookup":   ("Lookup / Reference",       "#0f766e", "#ecfdf5", "#99f6e4"),
    "borrower": ("Borrower (lender_profiles)", "#b45309", "#fffbeb", "#fde68a"),
    "rider":    ("Rider & Employee",         "#6d28d9", "#f5f3ff", "#ddd6fe"),
    "app":      ("In-office Application",    "#0e7490", "#ecfeff", "#a5f3fc"),
    "loan":     ("Loan Lifecycle",           "#be123c", "#fff1f2", "#fecdd3"),
    "ci":       ("Credit Investigation",     "#a21caf", "#fdf4ff", "#f5d0fe"),
    "collect":  ("Collections & Disbursement", "#15803d", "#f0fdf4", "#bbf7d0"),
    "payment":  ("Payments",                 "#1d4ed8", "#eff6ff", "#bfdbfe"),
    "notify":   ("Notifications & SMS",      "#c2410c", "#fff7ed", "#fed7aa"),
    "security": ("Auth / OTP / Security",    "#334155", "#f1f5f9", "#cbd5e1"),
    "admin":    ("Reporting & Admin",        "#57534e", "#fafaf9", "#d6d3d1"),
}

# --------------------------------------------------------------------------------------
# Column spec helpers
#   "name:type:FLAGS"  where FLAGS may contain PK / FK / UQ / N(nullable)
# --------------------------------------------------------------------------------------
def _parse(spec: str):
    cols = []
    for token in spec.split():
        parts = token.split(":")
        if len(parts) < 2:
            raise SystemExit(f"bad column token: {token!r}")
        name, typ = parts[0], parts[1]
        flags = parts[2] if len(parts) > 2 else ""
        cols.append({
            "name": name,
            "type": typ,
            "pk": "PK" in flags,
            "fk": "FK" in flags,
            "uq": "UQ" in flags,
            "nullable": "N" in flags.replace("PK", "").replace("FK", ""),
        })
    return cols


LOOKUP_SPEC = ("id:uuid:PK code:varchar:UQ label:varchar description:text:N "
               "is_active:bool sort_order:int4 created_at:timestamptz updated_at:timestamptz")

# (table, group, tag shown under the header, column spec)
TABLES_RAW = [
    # ---------------- lookups ----------------
    ("user_account_statuses", "lookup", "account lifecycle (active / suspended …)", LOOKUP_SPEC),
    ("account_upgrade_statuses", "lookup", "not_submitted → pending → verified → rejected", LOOKUP_SPEC),
    ("loan_statuses", "lookup", "pending / approved / active / closed …", LOOKUP_SPEC),
    ("payment_statuses", "lookup", "pending / completed / failed …", LOOKUP_SPEC),
    ("payment_methods", "lookup", "cash / gcash / bank transfer …", LOOKUP_SPEC),
    ("disbursement_methods", "lookup", "cash delivery / xendit / bank …", LOOKUP_SPEC),
    ("disbursement_statuses", "lookup", "pending / delivered / failed …", LOOKUP_SPEC),
    ("collection_assignment_statuses", "lookup", "requested / assigned / completed …", LOOKUP_SPEC),
    ("credit_investigation_statuses", "lookup", "assigned / in progress / submitted …", LOOKUP_SPEC),
    ("notification_types", "lookup", "in-app / push category", LOOKUP_SPEC),
    ("relationship_types", "lookup", "spouse / parent / sibling / friend …", LOOKUP_SPEC),
    ("payment_frequencies", "lookup", "daily / weekly / semi-monthly / monthly", LOOKUP_SPEC),
    ("address_types", "lookup", "home / work / business", LOOKUP_SPEC),
    ("document_types", "lookup", "valid ID / payslip / proof of billing …", LOOKUP_SPEC),
    ("gender_types", "lookup", "reference list", LOOKUP_SPEC),
    ("civil_statuses", "lookup", "single / married / widowed …", LOOKUP_SPEC),
    ("employment_types", "lookup", "employed / self-employed / …", LOOKUP_SPEC),
    ("vehicle_types", "lookup", "motorcycle / car / van", LOOKUP_SPEC),
    ("platform_types", "lookup", "android / ios / web", LOOKUP_SPEC),
    ("sms_statuses", "lookup", "queued / sent / failed / delivered", LOOKUP_SPEC),
    ("in_office_application_statuses", "lookup", "draft / submitted / approved …", LOOKUP_SPEC),
    ("document_review_statuses", "lookup", "per-document review: pending / verified / rejected", LOOKUP_SPEC),

    # ---------------- identity & access ----------------
    ("roles", "identity", "role catalogue — 'lender' is semantically BORROWER",
     "id:uuid:PK name:varchar:UQ description:text:N created_at:timestamptz is_archived:bool "
     "archived_at:timestamptz:N archived_by:uuid:NFK"),
    ("permissions", "identity", "module-scoped permission keys",
     "id:uuid:PK name:varchar:UQ module:varchar description:text:N created_at:timestamptz"),
    ("role_permissions", "identity", "M:N bridge roles ↔ permissions",
     "id:uuid:PK role_id:uuid:FK permission_id:uuid:FK created_at:timestamptz"),
    ("users", "identity", "single identity table for staff, borrowers and riders",
     "id:uuid:PK role_id:uuid:FK email:varchar:NUQ phone_number:varchar:NUQ first_name:varchar "
     "middle_name:varchar:N last_name:varchar suffix:varchar:N account_status:varchar "
     "fcm_token:text:N force_password_change:bool terms_accepted_at:timestamptz:N "
     "profile_photo_url:varchar:N last_login_at:timestamptz:N created_by:uuid:NFK "
     "created_at:timestamptz updated_at:timestamptz account_status_id:uuid:FK "
     "email_verified_at:timestamptz:N"),
    ("auth_logs", "identity", "login / logout / lockout trail",
     "id:uuid:PK user_id:uuid:FK event_type:varchar ip_address:inet:N user_agent:text:N "
     "failed_attempts:int4 is_locked:bool created_at:timestamptz"),
    ("terms_consent_logs", "identity", "per-device consent audit",
     "id:uuid:PK user_id:uuid:FK device_id:varchar platform:varchar app_version:varchar "
     "accepted_at:timestamptz platform_id:uuid:FK"),
    ("active_sessions", "identity", "one live session per user (UNIQUE user_id)",
     "id:uuid:PK user_id:uuid:FKUQ session_identifier:text created_at:timestamptz "
     "last_seen_at:timestamptz revoked_at:timestamptz:N"),
    ("user_devices", "identity", "authoritative FCM token store (multi-device)",
     "id:uuid:PK user_id:uuid:FK fcm_token:text platform:varchar app_version:varchar:N "
     "is_active:bool last_seen_at:timestamptz:N created_at:timestamptz updated_at:timestamptz"),
    ("user_mpins", "identity", "account-level 4-digit MPIN (server verified)",
     "user_id:uuid:PKFK mpin_hash:text failed_attempts:int4 locked_until:timestamptz:N "
     "change_window_start:timestamptz change_count:int4 created_at:timestamptz updated_at:timestamptz"),
    ("login_lockouts", "identity", "per-user failed login counter",
     "user_id:uuid:PKFK failed_attempts:int4 locked_until:timestamptz:N updated_at:timestamptz"),

    # ---------------- borrower ----------------
    ("lender_profiles", "borrower", "BORROWER profile — 1:1 users.id (PK = FK)",
     "id:uuid:PKFK gender:varchar:N civil_status:varchar:N date_of_birth:date:N "
     "employment_type:varchar:N employer_name:varchar:N monthly_income:numeric:N "
     "gcash_number:varchar:N account_upgrade_status:varchar account_upgrade_rejection_notes:text:N "
     "source_of_funds:varchar:N created_at:timestamptz updated_at:timestamptz gender_id:uuid:NFK "
     "civil_status_id:uuid:NFK employment_type_id:uuid:NFK account_upgrade_status_id:uuid:FK "
     "term_default_count:int4"),
    ("addresses", "borrower", "geo-tagged borrower addresses",
     "id:uuid:PK user_id:uuid:FK address_type:varchar street:varchar barangay:varchar city:varchar "
     "province:varchar zip_code:varchar:N latitude:numeric:N longitude:numeric:N is_primary:bool "
     "created_at:timestamptz updated_at:timestamptz address_type_id:uuid:FK region:varchar:N"),
    ("emergency_contacts", "borrower", "LEGACY per-borrower contacts — prefer loan_emergency_contacts",
     "id:uuid:PK lender_id:uuid:FK name:varchar relationship:varchar phone_number:varchar "
     "address:text:N created_at:timestamptz relationship_id:uuid:FK"),
    ("account_upgrade_documents", "borrower", "KYC docs for the upgrade to a verified account",
     "id:uuid:PK lender_id:uuid:FK document_type:varchar file_path:text file_name:varchar "
     "file_size:int4 mime_type:varchar status:varchar rejection_notes:text:N reviewed_by:uuid:NFK "
     "reviewed_at:timestamptz:N uploaded_at:timestamptz document_type_id:uuid:FK status_id:uuid:FK"),

    # ---------------- rider & employee ----------------
    ("rider_profiles", "rider", "1:1 users.id (PK = FK) — each rider is a user",
     "id:uuid:PKFK plate_number:varchar vehicle_type:varchar vehicle_brand:varchar:N "
     "drivers_license_number:varchar drivers_license_expiry:date:N is_available:bool "
     "created_at:timestamptz updated_at:timestamptz vehicle_type_id:uuid:FK address:text:N"),
    ("employee_profiles", "rider", "1:1 users.id (PK = FK) — each employee is a user",
     "id:uuid:PKFK position:varchar hired_at:date gender:varchar:N civil_status:varchar:N "
     "created_at:timestamptz updated_at:timestamptz gender_id:uuid:NFK civil_status_id:uuid:NFK "
     "date_of_birth:date:N"),
    ("rider_locations", "rider", "latest ping only — 1 row per rider (UNIQUE)",
     "id:uuid:PK rider_id:uuid:FKUQ latitude:numeric longitude:numeric accuracy:numeric:N "
     "updated_at:timestamptz speed_kmh:numeric:N"),
    ("rider_location_history", "rider", "append-only breadcrumb trail",
     "id:uuid:PK rider_id:uuid:FK latitude:numeric longitude:numeric accuracy:numeric:N "
     "recorded_at:timestamptz created_at:timestamptz"),

    # ---------------- in-office application ----------------
    ("in_office_applications", "app", "wizard container — promoted to a loan on submit",
     "id:uuid:PK lender_id:uuid:NFK created_by:uuid:FK wizard_step:int4 status:varchar "
     "borrower_signature:text:N submitted_at:timestamptz:N created_at:timestamptz "
     "updated_at:timestamptz status_id:uuid:FK"),
    ("application_personal_info", "app", "1:1 application (UNIQUE application_id)",
     "id:uuid:PK application_id:uuid:FKUQ first_name:varchar:N middle_name:varchar:N "
     "last_name:varchar:N phone_number:varchar:N gender:varchar:N civil_status:varchar:N "
     "date_of_birth:date:N gcash_number:varchar:N created_at:timestamptz updated_at:timestamptz "
     "gender_id:uuid:NFK civil_status_id:uuid:NFK email:varchar:N suffix:varchar:N"),
    ("application_employment_info", "app", "1:1 application",
     "id:uuid:PK application_id:uuid:FKUQ employment_type:varchar:N employer_name:varchar:N "
     "monthly_income:numeric:N created_at:timestamptz updated_at:timestamptz "
     "employment_type_id:uuid:NFK"),
    ("application_addresses", "app", "1:N application (draft addresses)",
     "id:uuid:PK application_id:uuid:FK address_type:varchar:N street:varchar:N barangay:varchar:N "
     "city:varchar:N province:varchar:N zip_code:varchar:N latitude:numeric:N longitude:numeric:N "
     "is_primary:bool created_at:timestamptz updated_at:timestamptz address_type_id:uuid:NFK"),
    ("application_emergency_contacts", "app", "DEPRECATED (00130) — kept for old drafts",
     "id:uuid:PK application_id:uuid:FK name:varchar:N relationship:varchar:N phone_number:varchar:N "
     "address:text:N created_at:timestamptz relationship_id:uuid:NFK"),
    ("application_loan_details", "app", "1:1 application — requested amount / term",
     "id:uuid:PK application_id:uuid:FKUQ principal_amount:numeric:N interest_rate:numeric "
     "payment_frequency:varchar:N term_days:int4:N purpose:text:N created_at:timestamptz "
     "updated_at:timestamptz term_periods:int4:N payment_frequency_id:uuid:NFK"),
    ("application_co_makers", "app", "draft co-makers (not yet loan_co_makers)",
     "id:uuid:PK application_id:uuid:FK first_name:varchar:N last_name:varchar:N "
     "relationship:varchar:N phone_number:varchar:N date_of_birth:date:N address:text:N "
     "created_at:timestamptz relationship_id:uuid:NFK"),
    ("application_documents", "app", "uploaded during the wizard",
     "id:uuid:PK application_id:uuid:FK document_type:varchar:N file_path:text:N file_name:varchar:N "
     "mime_type:varchar:N uploaded_at:timestamptz document_type_id:uuid:FK"),
    ("loan_disbursement_preferences", "app", "1:1 loan — chosen payout channel (PK = loan_id)",
     "loan_id:uuid:PKFK method:varchar account:varchar:N created_at:timestamptz "
     "updated_at:timestamptz method_id:uuid:FK"),

    # ---------------- loan lifecycle ----------------
    ("loans", "loan", "loan application / contract — lender_id is the BORROWER",
     "id:uuid:PK loan_number:varchar:UQ lender_id:uuid:FK in_office_application_id:uuid:NFK "
     "principal_amount:numeric interest_rate:numeric payment_frequency:varchar term_days:int4 "
     "term_periods:int4:N installment_amount:numeric:N purpose:text status:varchar "
     "approved_by:uuid:NFK rejected_by:uuid:NFK rejection_reason:text:N created_at:timestamptz "
     "updated_at:timestamptz payment_frequency_id:uuid:FK status_id:uuid:FK "
     "employment_type:varchar:N employment_type_id:uuid:NFK employer_name:varchar:N "
     "monthly_income:numeric:N source_of_funds:varchar:N reapply_allowed_at:timestamptz:N "
     "permanently_rejected:bool"),
    ("loan_schedules", "loan", "one row per installment — the collection unit",
     "id:uuid:PK loan_id:uuid:FK installment_number:int4 due_date:date amount_due:numeric "
     "created_at:timestamptz updated_at:timestamptz"),
    ("loan_emergency_contacts", "loan", "per-loan snapshot — source of truth for CI",
     "id:uuid:PK loan_id:uuid:FK name:varchar relationship:varchar relationship_id:uuid:NFK "
     "phone_number:varchar address:text:N created_at:timestamptz"),
    ("loan_documents", "loan", "signed contract / requirements per loan",
     "id:uuid:PK loan_id:uuid:FK document_type:varchar file_path:varchar file_name:varchar "
     "mime_type:varchar uploaded_by:uuid:FK uploaded_at:timestamptz document_type_id:uuid:FK"),
    ("co_makers", "loan", "co-maker master (shared across loans)",
     "id:uuid:PK first_name:varchar:N last_name:varchar:N phone_number:varchar:N "
     "date_of_birth:date:N address:text:N signature:text:N created_at:timestamptz "
     "updated_at:timestamptz"),
    ("co_maker_documents", "loan", "co-maker KYC attachments",
     "id:uuid:PK co_maker_id:uuid:FK document_type:varchar file_path:varchar file_name:varchar "
     "mime_type:varchar uploaded_at:timestamptz document_type_id:uuid:FK"),
    ("loan_co_makers", "loan", "M:N bridge loans ↔ co_makers",
     "id:uuid:PK loan_id:uuid:FK co_maker_id:uuid:FK relationship:varchar created_at:timestamptz "
     "relationship_id:uuid:FK"),
    ("penalty_logs", "loan", "late-payment penalty ledger",
     "id:uuid:PK loan_id:uuid:FK applied_by:uuid:NFK penalty_basis:numeric penalty_rate:numeric "
     "penalty_amount:numeric reason:text applied_at:timestamptz"),

    # ---------------- credit investigation ----------------
    ("credit_investigations", "ci", "field verification job assigned to a rider",
     "id:uuid:PK loan_id:uuid:FK rider_id:uuid:FK assigned_by:uuid:FK deadline:timestamptz:N "
     "investigation_notes:text:N status:varchar notes:text:N report_summary:text:N "
     "response_at:timestamptz:N started_at:timestamptz:N completed_at:timestamptz:N "
     "created_at:timestamptz updated_at:timestamptz status_id:uuid:FK reviewed_by:uuid:NFK "
     "reviewed_at:timestamptz:N review_notes:text:N review_decision:varchar:N"),
    ("ci_documents", "ci", "photo / geo-tagged evidence from the field",
     "id:uuid:PK ci_id:uuid:FK document_type:varchar file_path:varchar file_name:varchar "
     "mime_type:varchar latitude:numeric:N longitude:numeric:N notes:text:N uploaded_at:timestamptz "
     "document_type_id:uuid:FK"),

    # ---------------- collections & disbursement ----------------
    ("collection_assignments", "collect", "collect a single loan_schedule installment",
     "id:uuid:PK loan_schedule_id:uuid:FK rider_id:uuid:NFK assigned_by:uuid:NFK "
     "requested_by:uuid:NFK collection_type:varchar collection_schedule:timestamptz:N status:varchar "
     "amount_collected:numeric:N collection_notes:text:N proof_photo:text:N borrower_signature:text:N "
     "collection_photo:text:N response_at:timestamptz:N completed_at:timestamptz:N "
     "created_at:timestamptz updated_at:timestamptz status_id:uuid:FK requested_amount:numeric:N "
     "requested_at:timestamptz:N assigned_at:timestamptz:N reviewed_by:uuid:NFK "
     "reviewed_at:timestamptz:N rejection_reason:text:N collection_schedule_end:timestamptz:N"),
    ("disbursements", "collect", "payout of an approved loan (cash delivery / xendit)",
     "id:uuid:PK loan_id:uuid:FK authorized_by:uuid:FK method:varchar amount:numeric status:varchar "
     "xendit_id:varchar:N xendit_reference:varchar:N xendit_status:varchar:N rider_id:uuid:NFK "
     "delivery_date:timestamptz:N delivery_notes:text:N delivery_proof:text:N "
     "borrower_signature:text:N disbursed_at:timestamptz:N created_at:timestamptz "
     "updated_at:timestamptz delivered_at:timestamptz:N method_id:uuid:FK status_id:uuid:FK "
     "delivery_proof_2:text:N"),

    # ---------------- payments ----------------
    ("payments", "payment", "money received — manual, rider-collected or xendit",
     "id:uuid:PK loan_schedule_id:uuid:NFK payment_method:varchar amount:numeric status:varchar "
     "xendit_payment_id:varchar:N xendit_reference:varchar:N idempotency_key:varchar:NUQ "
     "recorded_by:uuid:NFK collection_assignment_id:uuid:NFK receipt_path:varchar:N notes:text:N "
     "paid_at:timestamptz created_at:timestamptz payment_method_id:uuid:FK status_id:uuid:FK"),
    ("payment_reversals", "payment", "1:1 reversal of a payment (UNIQUE payment_id)",
     "id:uuid:PK payment_id:uuid:FKUQ reversed_by:uuid:FK reason:text reversed_at:timestamptz"),
    ("xendit_logs", "payment", "raw gateway webhook / API audit trail",
     "id:uuid:PK loan_id:uuid:NFK payment_id:uuid:NFK disbursement_id:uuid:NFK event_type:varchar "
     "xendit_id:varchar payload:jsonb status:varchar created_at:timestamptz"),

    # ---------------- notifications & sms ----------------
    ("notifications", "notify", "in-app inbox row, optionally pushed via FCM",
     "id:uuid:PK user_id:uuid:FK triggered_by:uuid:NFK title:varchar body:text type:varchar "
     "reference_id:uuid:N reference_type:varchar:N is_read:bool read_at:timestamptz:N "
     "fcm_sent:bool sent_at:timestamptz:N created_at:timestamptz type_id:uuid:FK"),
    ("sms_logs", "notify", "outbound SMS per user / installment",
     "id:uuid:PK user_id:uuid:FK loan_schedule_id:uuid:NFK phone_number:varchar message:text "
     "status:varchar gateway_reference:varchar:N sent_at:timestamptz created_at:timestamptz "
     "status_id:uuid:FK"),
    ("sms_templates", "notify", "keyed message bodies (template_key UNIQUE)",
     "id:uuid:PK template_key:varchar:UQ title:varchar body:text is_active:bool "
     "created_at:timestamptz updated_at:timestamptz"),

    # ---------------- auth / otp / security ----------------
    ("otp_codes", "security", "phone OTP, hash only",
     "id:uuid:PK phone_number:varchar otp_hash:text attempts:int4 expires_at:timestamptz used:bool "
     "created_at:timestamptz"),
    ("otp_lockouts", "security", "PK = phone_number",
     "phone_number:varchar:PK failed_attempts:int4 locked_until:timestamptz:N updated_at:timestamptz"),
    ("email_register_otps", "security", "sign-up email verification OTP",
     "id:uuid:PK email:text otp_hash:text attempts:int4 expires_at:timestamptz used:bool verified:bool "
     "created_at:timestamptz"),
    ("email_register_lockouts", "security", "PK = email",
     "email:text:PK failed_attempts:int4 locked_until:timestamptz:N updated_at:timestamptz"),
    ("email_reset_otps", "security", "password reset OTP + reset token",
     "id:uuid:PK user_id:uuid:FK email:text otp_hash:text attempts:int4 expires_at:timestamptz "
     "used:bool verified:bool created_at:timestamptz reset_token_hash:text:N"),
    ("email_otp_lockouts", "security", "PK = email",
     "email:text:PK failed_attempts:int4 locked_until:timestamptz:N updated_at:timestamptz"),
    ("email_verifications", "security", "token-based email verification",
     "id:uuid:PK user_id:uuid:FK email:text token_hash:text expires_at:timestamptz "
     "used_at:timestamptz:N created_at:timestamptz"),
    ("password_reset_tokens", "security", "single-use reset token (UNIQUE token_hash)",
     "id:uuid:PK user_id:uuid:FK token_hash:text:UQ expires_at:timestamptz used_at:timestamptz:N "
     "created_at:timestamptz"),
    ("password_history", "security", "reuse guard for password changes",
     "id:uuid:PK user_id:uuid:FK password_hash:text created_at:timestamptz"),
    ("security_blocks", "security", "generic expiring block key",
     "id:uuid:PK key:text reason:text expires_at:timestamptz created_at:timestamptz"),
    ("security_events", "security", "security telemetry",
     "id:uuid:PK event_type:varchar key:text user_id:uuid:NFK ip_address:text:N detail:jsonb:N "
     "created_at:timestamptz"),
    ("rate_limit_logs", "security", "sliding-window rate limiting",
     "id:uuid:PK key:text created_at:timestamptz"),

    # ---------------- reporting & admin ----------------
    ("reports", "admin", "generated report artefacts (PDF / Excel)",
     "id:uuid:PK report_type:varchar title:varchar parameters:jsonb file_path_pdf:varchar:N "
     "file_path_excel:varchar:N generated_by:uuid:FK generated_at:timestamptz created_at:timestamptz "
     "data:jsonb:N"),
    ("report_templates", "admin", "parameters_schema drives the generator UI",
     "id:uuid:PK template_key:varchar:UQ title:varchar description:text:N parameters_schema:jsonb "
     "is_active:bool created_at:timestamptz"),
    ("audit_logs", "admin", "row-level before/after audit",
     "id:uuid:PK performed_by:uuid:NFK action:varchar table_name:varchar record_id:uuid "
     "old_values:jsonb:N new_values:jsonb:N ip_address:inet:N created_at:timestamptz"),
    ("system_config", "admin", "key/value runtime configuration",
     "id:uuid:PK config_key:varchar:UQ config_value:text description:text:N updated_by:uuid:NFK "
     "updated_at:timestamptz"),
]

# --------------------------------------------------------------------------------------
# Foreign keys — resolved explicitly, then verified against the schema
# --------------------------------------------------------------------------------------
STATUS_TARGET = {
    "account_upgrade_documents": "document_review_statuses",
    "loans": "loan_statuses",
    "payments": "payment_statuses",
    "disbursements": "disbursement_statuses",
    "collection_assignments": "collection_assignment_statuses",
    "credit_investigations": "credit_investigation_statuses",
    "sms_logs": "sms_statuses",
    "in_office_applications": "in_office_application_statuses",
}

BASE_TARGET = {
    "role": "roles", "permission": "permissions", "user": "users", "lender": "lender_profiles",
    "rider": "rider_profiles", "loan": "loans", "loan_schedule": "loan_schedules",
    "co_maker": "co_makers", "application": "in_office_applications",
    "in_office_application": "in_office_applications", "ci": "credit_investigations",
    "collection_assignment": "collection_assignments", "payment": "payments",
    "disbursement": "disbursements", "type": "notification_types",
    "payment_method": "payment_methods", "account_status": "user_account_statuses",
    "account_upgrade_status": "account_upgrade_statuses", "gender": "gender_types",
    "civil_status": "civil_statuses", "employment_type": "employment_types",
    "address_type": "address_types", "relationship": "relationship_types",
    "document_type": "document_types", "payment_frequency": "payment_frequencies",
    "vehicle_type": "vehicle_types", "platform": "platform_types",
    # audit / approver columns all point at users
    "created_by": "users", "updated_by": "users", "approved_by": "users", "rejected_by": "users",
    "uploaded_by": "users", "recorded_by": "users", "reversed_by": "users",
    "authorized_by": "users", "assigned_by": "users", "requested_by": "users",
    "reviewed_by": "users", "applied_by": "users", "performed_by": "users",
    "generated_by": "users", "archived_by": "users", "triggered_by": "users",
}

METHOD_TARGET = {"disbursements": "disbursement_methods",
                 "loan_disbursement_preferences": "disbursement_methods",
                 "payments": "payment_methods"}

TABLE_ORDER = [t[0] for t in TABLES_RAW]


def resolve_fk(table: str, column: str) -> str | None:
    if column == "status_id":
        return STATUS_TARGET.get(table)
    if column == "method_id":
        return METHOD_TARGET.get(table)
    if column.endswith("_by"):
        return "users"
    base = column[:-3]
    target = BASE_TARGET.get(base)
    if target and target in TABLE_ORDER:
        return target
    return None


TABLES: dict[str, dict] = {}
for name, group, tag, spec in TABLES_RAW:
    cols = _parse(spec)
    # a 1:1 child uses its own PK as the FK to the parent
    if name in ("lender_profiles", "rider_profiles", "employee_profiles", "user_mpins",
                "login_lockouts"):
        cols[0]["target"] = "users"
        cols[0]["fk"] = True
    elif name == "loan_disbursement_preferences":
        cols[0]["target"] = "loans"
        cols[0]["fk"] = True
    for c in cols:
        if c["fk"] and not c.get("target"):
            target = resolve_fk(name, c["name"])
            if target is None:
                raise SystemExit(f"unresolved FK: {name}.{c['name']}")
            c["target"] = target
    TABLES[name] = {"name": name, "group": group, "tag": tag, "cols": cols,
                    "lookup": group == "lookup"}

RELATIONS = []  # (child, child_col, parent, parent_col, one_to_one)
for tname, t in TABLES.items():
    for c in t["cols"]:
        if c.get("target"):
            RELATIONS.append((tname, c["name"], c["target"], "id", bool(c["pk"])))

# --------------------------------------------------------------------------------------
# Pages
# --------------------------------------------------------------------------------------
PAGES = [
    {"kind": "cover"},
    {"kind": "domain", "title": "Identity & Access",
     "subtitle": "users is the single identity row for every actor; profiles 1:1 onto it",
     "stacks": [
         ["roles", "permissions", "role_permissions", "user_account_statuses"],
         ["users", "auth_logs"],
         ["active_sessions", "user_devices", "user_mpins", "login_lockouts",
          "terms_consent_logs", "platform_types"],
     ]},
    {"kind": "domain", "title": "Borrower Domain",
     "subtitle": "lender_profiles is SEMANTICALLY the borrower — 1:1 child of users with PK = FK",
     "stacks": [
         ["lender_profiles", "addresses", "emergency_contacts"],
         ["account_upgrade_documents", "account_upgrade_statuses", "document_review_statuses",
          "document_types", "users"],
         ["gender_types", "civil_statuses", "employment_types", "address_types",
          "relationship_types"],
     ]},
    {"kind": "domain", "title": "Rider & Employee Domain",
     "subtitle": "rider_profiles / employee_profiles are 1:1 children of users (PK = FK)",
     "stacks": [
         ["rider_profiles", "rider_locations", "rider_location_history", "vehicle_types"],
         ["employee_profiles", "gender_types", "civil_statuses"],
         ["users", "roles"],
     ]},
    {"kind": "domain", "title": "In-Office Loan Application (wizard)",
     "subtitle": "draft graphs hang off in_office_applications and are promoted into loans",
     "stacks": [
         ["in_office_applications", "application_personal_info", "application_employment_info"],
         ["application_addresses", "application_loan_details", "application_co_makers",
          "application_emergency_contacts"],
         ["application_documents", "in_office_application_statuses", "address_types", "users"],
         ["gender_types", "civil_statuses", "document_types", "relationship_types",
          "payment_frequencies", "employment_types"],
     ]},
    {"kind": "domain", "title": "Loan Lifecycle",
     "subtitle": "loans → loan_schedules is the backbone: schedules are what riders collect",
     "stacks": [
         ["loans", "loan_schedules", "penalty_logs", "loan_disbursement_preferences"],
         ["loan_statuses", "payment_frequencies", "employment_types", "disbursement_methods",
          "lender_profiles"],
         ["loan_emergency_contacts", "loan_documents", "co_makers", "co_maker_documents"],
         ["loan_co_makers", "relationship_types", "document_types", "in_office_applications",
          "users"],
     ]},
    {"kind": "domain", "title": "Credit Investigation",
     "subtitle": "field verification of a loan before approval — rider submits, reviewer decides",
     "stacks": [
         ["credit_investigations", "ci_documents", "users"],
         ["credit_investigation_statuses", "document_types", "rider_profiles"],
         ["loans", "loan_schedules"],
     ]},
    {"kind": "domain", "title": "Collections & Disbursement",
     "subtitle": "rider work queue on loan_schedules + payout of approved loans",
     "stacks": [
         ["collection_assignments", "collection_assignment_statuses"],
         ["disbursements", "disbursement_statuses", "disbursement_methods", "users"],
         ["loan_schedules", "rider_profiles", "loans"],
     ]},
    {"kind": "domain", "title": "Payments & Reversals",
     "subtitle": "a payment lands on one schedule, optionally through a collection assignment",
     "stacks": [
         ["payments", "payment_reversals", "xendit_logs", "users"],
         ["payment_statuses", "payment_methods", "collection_assignments"],
         ["loan_schedules", "disbursements", "loans"],
     ]},
    {"kind": "domain", "title": "Notifications, SMS & Devices",
     "subtitle": "user_devices is authoritative for push; users.fcm_token is the legacy mirror",
     "stacks": [
         ["notifications", "sms_logs", "sms_templates"],
         ["notification_types", "sms_statuses", "user_devices"],
         ["users", "loan_schedules"],
     ]},
    {"kind": "domain", "title": "Auth, OTP & Security",
     "subtitle": "OTP + lockout tables are keyed by phone / email, not by user id",
     "stacks": [
         ["otp_codes", "otp_lockouts", "email_register_otps", "email_register_lockouts"],
         ["email_reset_otps", "email_otp_lockouts", "email_verifications",
          "password_reset_tokens", "password_history"],
         ["security_blocks", "security_events", "rate_limit_logs", "login_lockouts"],
         ["users"],
     ]},
    {"kind": "domain", "title": "Reporting, Audit & Configuration",
     "subtitle": "head_manager-only surfaces (reports, audit_logs, system_config, sms_templates)",
     "stacks": [
         ["reports", "report_templates", "audit_logs", "system_config"],
         ["users"],
     ]},
    {"kind": "lookups"},
    {"kind": "index"},
]


# --------------------------------------------------------------------------------------
# Measurement
# --------------------------------------------------------------------------------------
def col_text_w(text: str, size: float, mono: bool = True) -> float:
    return len(text) * (size * 0.60 if mono else size * 0.55)


def table_metrics(name: str):
    t = TABLES[name]
    cols = t["cols"]
    hidden = 0
    shown = cols
    if t["lookup"]:
        shown = cols[:3]
        hidden = len(cols) - len(shown)
    name_w = max(col_text_w(c["name"], 10.5) for c in shown)
    type_w = max(col_text_w(c["type"], 8.5) for c in shown)
    width = 12 + name_w + 30 + type_w + 14
    width = max(width, col_text_w(name, 12.5, mono=False) + 28, 240)
    height = HDR_H + TAG_H + len(shown) * ROW_H
    if hidden:
        height += ROW_H
    height += PAD_BOT
    return width, height, shown, hidden


def esc(s: str) -> str:
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


base_esc = esc


# --------------------------------------------------------------------------------------
# SVG building blocks
# --------------------------------------------------------------------------------------
class Box:
    refs = 0          # how many rows point at this table (set by the callers)

    def __init__(self, name, x, y, w, h, shown, hidden, tag):
        self.name, self.x, self.y, self.w, self.h = name, x, y, w, h
        self.shown, self.hidden, self.tag = shown, hidden, tag

    def row_y(self, colname):
        for i, c in enumerate(self.shown):
            if c["name"] == colname:
                return self.y + HDR_H + TAG_H + i * ROW_H + ROW_H / 2
        # fall back: last row (the hidden note) or header
        if self.hidden:
            return self.y + HDR_H + TAG_H + (len(self.shown) + 0.5) * ROW_H
        return self.y + HDR_H / 2


def render_box(b: Box) -> str:
    t = TABLES[b.name]
    _, stroke, fill, chip = GROUPS[t["group"]]
    out = []
    out.append(f'<g class="tbl">')
    out.append(f'<rect x="{b.x:.1f}" y="{b.y:.1f}" width="{b.w:.1f}" height="{b.h:.1f}" rx="7" '
               f'fill="#ffffff" stroke="{stroke}" stroke-width="1.6"/>')
    out.append(f'<path d="M{b.x:.1f} {b.y + HDR_H:.1f} V{b.y + 7:.1f} a7 7 0 0 1 7 -7 '
               f'H{b.x + b.w - 7:.1f} a7 7 0 0 1 7 7 V{b.y + HDR_H:.1f} Z" fill="{stroke}"/>')
    out.append(f'<text x="{b.x + 9:.1f}" y="{b.y + HDR_H / 2 + 1:.1f}" fill="#ffffff" '
               f'font-size="12.5" font-weight="700" font-family="Segoe UI,Arial" '
               f'dominant-baseline="middle">{esc(b.name)}</text>')
    if b.tag:
        out.append(f'<text x="{b.x + 9:.1f}" y="{b.y + HDR_H + TAG_H / 2 + 1:.1f}" fill="{stroke}" '
                   f'font-size="8.6" font-style="italic" font-family="Segoe UI,Arial" '
                   f'dominant-baseline="middle" opacity="0.9">{esc(trim(b.tag, b.w - 18, 8.6))}</text>')
    y0 = b.y + HDR_H + TAG_H
    for i, c in enumerate(b.shown):
        y = y0 + i * ROW_H
        if i % 2 == 1:
            out.append(f'<rect x="{b.x + 1:.1f}" y="{y:.1f}" width="{b.w - 2:.1f}" '
                       f'height="{ROW_H:.1f}" fill="{fill}" opacity="0.75"/>')
        if c["pk"] or c["fk"]:
            out.append(f'<rect x="{b.x + 1:.1f}" y="{y:.1f}" width="3" height="{ROW_H:.1f}" '
                       f'fill="{chip if c["fk"] and not c["pk"] else stroke}"/>')
        nm = c["name"] + ("" if not c["nullable"] else "")
        weight = "700" if c["pk"] else "400"
        out.append(f'<text x="{b.x + 12:.1f}" y="{y + ROW_H / 2 + 1:.1f}" fill="#111827" '
                   f'font-size="10.5" font-weight="{weight}" font-family="Cascadia Mono,Consolas,monospace" '
                   f'dominant-baseline="middle">{esc(nm)}</text>')
        flags = []
        if c["pk"]:
            flags.append("PK")
        if c["fk"]:
            flags.append("FK")
        if c["uq"]:
            flags.append("UQ")
        fx = b.x + 12 + col_text_w(max((s["name"] for s in b.shown), key=len), 10.5) + 8
        if flags:
            out.append(f'<text x="{fx:.1f}" y="{y + ROW_H / 2 + 1:.1f}" fill="{stroke}" '
                       f'font-size="7.6" font-weight="700" font-family="Segoe UI,Arial" '
                       f'dominant-baseline="middle" opacity="0.85">{"/".join(flags)}</text>')
        ty = b.x + b.w - 9
        out.append(f'<text x="{ty:.1f}" y="{y + ROW_H / 2 + 1:.1f}" fill="#6b7280" font-size="8.6" '
                   f'font-family="Cascadia Mono,Consolas,monospace" text-anchor="end" '
                   f'dominant-baseline="middle">{esc(c["type"])}</text>')
    if b.hidden:
        y = y0 + len(b.shown) * ROW_H
        note = f"+ {b.hidden} shared columns"
        if b.refs:
            note += f" · {b.refs} FK ref{'s' if b.refs != 1 else ''} →"
        else:
            note += " …"
        out.append(f'<text x="{b.x + 12:.1f}" y="{y + ROW_H / 2 + 1:.1f}" fill="#6b7280" '
                   f'font-size="9" font-style="italic" font-family="Segoe UI,Arial" '
                   f'dominant-baseline="middle">{base_esc(note)}</text>')
    out.append("</g>")
    return "".join(out)


def trim(text, maxw, size):
    if col_text_w(text, size, mono=False) <= maxw:
        return text
    n = int(maxw / (size * 0.55)) - 1
    return text[:max(4, n)] + "…"


def render_relation(cb: Box, ccol: str, pb: Box, pcol: str, one_to_one: bool,
                    stack_index: dict, rightmost: int) -> str:
    y1 = cb.row_y(ccol)
    y2 = pb.row_y(pcol)
    color = GROUPS[TABLES[pb.name]["group"]][1]
    si_c, si_p = stack_index[cb.name], stack_index[pb.name]
    if si_c == si_p:
        # self / intra-stack: bulge outwards on the side with room
        if si_c >= rightmost:
            x1, x2 = cb.x, pb.x
            c1, c2 = x1 - 55, x2 - 55
            lab1 = ("end", x1 - 6)
        else:
            x1, x2 = cb.x + cb.w, pb.x + pb.w
            c1, c2 = x1 + 55, x2 + 55
            lab1 = ("start", x1 + 6)
        d = f"M{x1:.1f},{y1:.1f} C{c1:.1f},{y1:.1f} {c2:.1f},{y2:.1f} {x2:.1f},{y2:.1f}"
    else:
        if si_p > si_c:
            x1, x2 = cb.x + cb.w, pb.x
            d = (f"M{x1:.1f},{y1:.1f} C{x1 + (x2 - x1) * 0.45:.1f},{y1:.1f} "
                 f"{x2 - (x2 - x1) * 0.45:.1f},{y2:.1f} {x2:.1f},{y2:.1f}")
            lab1 = ("start", x1 + 6)
        else:
            x1, x2 = cb.x, pb.x + pb.w
            d = (f"M{x1:.1f},{y1:.1f} C{x1 - (x1 - x2) * 0.45:.1f},{y1:.1f} "
                 f"{x2 + (x1 - x2) * 0.45:.1f},{y2:.1f} {x2:.1f},{y2:.1f}")
            lab1 = ("end", x1 - 6)
    out = [f'<path d="{d}" fill="none" stroke="#ffffff" stroke-width="3" opacity="0.9"/>',
           f'<path d="{d}" fill="none" stroke="{color}" stroke-width="1.15" opacity="0.6"/>']
    out.append(f'<circle cx="{x2:.1f}" cy="{y2:.1f}" r="2.6" fill="#ffffff" stroke="{color}" '
               f'stroke-width="1.3"/>')
    out.append(f'<circle cx="{x1:.1f}" cy="{y1:.1f}" r="2.2" fill="{color}" opacity="0.8"/>')
    out.append(f'<text x="{lab1[1]:.1f}" y="{y1 - 5:.1f}" fill="{color}" font-size="8.2" '
               f'font-weight="700" font-family="Segoe UI,Arial" text-anchor="{lab1[0]}" '
               f'opacity="0.9">{"1" if one_to_one else "N"}</text>')
    return "".join(out)


# --------------------------------------------------------------------------------------
# Page renderers
# --------------------------------------------------------------------------------------
def page_frame(title, subtitle, page_no, total, accent):
    hdr = [
        f'<rect x="0" y="0" width="{PAGE_W}" height="{PAGE_H}" fill="#ffffff"/>',
        f'<rect x="0" y="0" width="{PAGE_W}" height="{TOP - 22}" fill="#0f172a"/>',
        f'<rect x="0" y="{TOP - 26}" width="{PAGE_W}" height="4" fill="{accent}"/>',
        f'<text x="{MARGIN_X}" y="34" fill="#ffffff" font-size="21" font-weight="700" '
        f'font-family="Segoe UI,Arial">{esc(title)}</text>',
        f'<text x="{MARGIN_X}" y="58" fill="#94a3b8" font-size="11.5" '
        f'font-family="Segoe UI,Arial">{esc(subtitle)}</text>',
        f'<text x="{PAGE_W - MARGIN_X}" y="34" fill="#e2e8f0" font-size="11" text-anchor="end" '
        f'font-family="Segoe UI,Arial">Jireta Loans &amp; Credit Corp — Supabase schema</text>',
        f'<text x="{PAGE_W - MARGIN_X}" y="58" fill="#64748b" font-size="10" text-anchor="end" '
        f'font-family="Segoe UI,Arial">visual ERD · generated {HDD}</text>',
        f'<line x1="{MARGIN_X}" y1="{PAGE_H - 38}" x2="{PAGE_W - MARGIN_X}" y2="{PAGE_H - 38}" '
        f'stroke="#e2e8f0" stroke-width="1"/>',
        f'<text x="{MARGIN_X}" y="{PAGE_H - 22}" fill="#94a3b8" font-size="9.5" '
        f'font-family="Segoe UI,Arial">Legend: red bar = PK · teal bar = FK · PK/FK/UQ badges · '
        f'"1"/"N" on each end of an edge = parent / child cardinality</text>',
        f'<text x="{PAGE_W - MARGIN_X}" y="{PAGE_H - 22}" fill="#94a3b8" font-size="9.5" '
        f'text-anchor="end" font-family="Segoe UI,Arial">Page {page_no} of {total}</text>',
    ]
    return "".join(hdr)


def layout_stacks(page):
    """Return {table: Box} plus stack column geometry."""
    stacks = page["stacks"]
    metrics = {}
    for st in stacks:
        for t in st:
            metrics[t] = table_metrics(t)
    needed = [max(metrics[t][0] for t in st) for st in stacks]
    n = len(stacks)
    total_needed = sum(needed) + STACK_GAP * (n - 1)
    extra = (AVAIL_W - total_needed) / n if total_needed < AVAIL_W else 0
    extra = min(extra, 90)
    widths = [w + extra for w in needed]
    block_w = sum(widths) + STACK_GAP * (n - 1)
    x = MARGIN_X + max(0, (AVAIL_W - block_w) / 2)
    boxes = {}
    stack_index = {}
    col_x = []
    for i, (st, w) in enumerate(zip(stacks, widths)):
        col_x.append((x, w))
        y = TOP
        for t in st:
            bw, bh, shown, hidden = metrics[t]
            b = Box(t, x + (w - bw) / 2, y, bw, bh, shown, hidden, TABLES[t]["tag"])
            boxes[t] = b
            stack_index[t] = i
            y += bh + BOX_GAP
        x += w + STACK_GAP
    return boxes, stack_index, col_x


def render_domain(page, page_no, total):
    accent = GROUPS["identity"][1]
    boxes, stack_index, col_x = layout_stacks(page)
    rightmost = len(page["stacks"]) - 1
    for t in boxes:
        accent = GROUPS[TABLES[t]["group"]][1]
        break
    parts = [page_frame(page["title"], page["subtitle"], page_no, total, accent)]
    # relations first (under the boxes)
    seen = set()
    for child, ccol, parent, pcol, o2o in RELATIONS:
        if child in boxes and parent in boxes and (child, ccol) not in seen:
            seen.add((child, ccol))
            parts.append(render_relation(boxes[child], ccol, boxes[parent], pcol, o2o,
                                         stack_index, rightmost))
    for name in boxes:
        parts.append(render_box(boxes[name]))
    return "".join(parts)


def render_cover(page_no, total, toc):
    parts = [f'<rect x="0" y="0" width="{PAGE_W}" height="{PAGE_H}" fill="#ffffff"/>',
             f'<rect x="0" y="0" width="{PAGE_W}" height="470" fill="#0f172a"/>',
             f'<rect x="0" y="466" width="{PAGE_W}" height="5" fill="#be123c"/>']
    parts.append(f'<text x="90" y="150" fill="#f8fafc" font-size="52" font-weight="800" '
                 f'font-family="Segoe UI,Arial">Jireta Loans &amp; Credit Corp</text>')
    parts.append(f'<text x="90" y="205" fill="#f43f5e" font-size="34" font-weight="700" '
                 f'font-family="Segoe UI,Arial">Entity–Relationship Diagram</text>')
    parts.append(f'<text x="90" y="248" fill="#94a3b8" font-size="17" '
                 f'font-family="Segoe UI,Arial">Supabase / PostgreSQL schema · '
                 f'{len(TABLES)} tables · {len(RELATIONS)} foreign-key relationships</text>')
    parts.append(f'<text x="90" y="330" fill="#e2e8f0" font-size="14" '
                 f'font-family="Segoe UI,Arial">Visual, domain-partitioned ERD — '
                 f'one page per functional area, crow\'s-foot style cardinality,</text>')
    parts.append(f'<text x="90" y="354" fill="#e2e8f0" font-size="14" '
                 f'font-family="Segoe UI,Arial">lookup registries collapsed to their shared shape, '
                 f'plus a full table index with page numbers.</text>')
    parts.append(f'<text x="90" y="410" fill="#64748b" font-size="12" '
                 f'font-family="Segoe UI,Arial">Generated {HDD} · source of truth: '
                 f'supabase/migrations · do not edit by hand</text>')

    # legend
    lx, ly = 90, 540
    parts.append(f'<text x="{lx}" y="{ly}" fill="#0f172a" font-size="16" font-weight="700" '
                 f'font-family="Segoe UI,Arial">How to read this diagram</text>')
    rows = [
        ("PK", "Primary key — red bar on the row, bold name"),
        ("FK", "Foreign key — teal bar; the edge is drawn to the parent row"),
        ("UQ", "Unique constraint"),
        ("1 / N", "Cardinality: circle at the parent end is 1, dot at the child end is N"),
        ("1:1", "Child PK is also FK (lender_profiles, rider_profiles, employee_profiles …)"),
        ("lookup", "22 reference tables share id / code / label / description / is_active / sort_order"),
    ]
    yy = ly + 30
    for k, v in rows:
        parts.append(f'<text x="{lx}" y="{yy}" fill="#be123c" font-size="12.5" font-weight="700" '
                     f'font-family="Cascadia Mono,Consolas,monospace">{esc(k)}</text>')
        parts.append(f'<text x="{lx + 110}" y="{yy}" fill="#334155" font-size="12.5" '
                     f'font-family="Segoe UI,Arial">{esc(v)}</text>')
        yy += 28

    # domain swatches
    sx, sy = 900, 540
    parts.append(f'<text x="{sx}" y="{sy}" fill="#0f172a" font-size="16" font-weight="700" '
                 f'font-family="Segoe UI,Arial">Domains</text>')
    yy = sy + 30
    for key, (label, stroke, fill, chip) in GROUPS.items():
        parts.append(f'<rect x="{sx}" y="{yy - 10}" width="16" height="12" rx="3" fill="{stroke}"/>')
        parts.append(f'<text x="{sx + 26}" y="{yy}" fill="#334155" font-size="12.5" '
                     f'font-family="Segoe UI,Arial">{esc(label)}</text>')
        yy += 26

    # TOC
    tx, ty = 90, 790
    parts.append(f'<text x="{tx}" y="{ty}" fill="#0f172a" font-size="16" font-weight="700" '
                 f'font-family="Segoe UI,Arial">Contents</text>')
    yy = ty + 30
    for label, pno in toc:
        x = tx
        parts.append(f'<text x="{x}" y="{yy}" fill="#334155" font-size="12" '
                     f'font-family="Segoe UI,Arial">{esc(label)}</text>')
        parts.append(f'<line x1="{x + 300}" y1="{yy - 4}" x2="{x + 540}" y2="{yy - 4}" '
                     f'stroke="#e2e8f0" stroke-dasharray="2 3"/>')
        parts.append(f'<text x="{x + 580}" y="{yy}" fill="#be123c" font-size="12" text-anchor="end" '
                     f'font-family="Segoe UI,Arial" font-weight="700">{pno}</text>')
        yy += 24

    parts.append(f'<line x1="{MARGIN_X}" y1="{PAGE_H - 38}" x2="{PAGE_W - MARGIN_X}" '
                 f'y2="{PAGE_H - 38}" stroke="#e2e8f0"/>')
    parts.append(f'<text x="{MARGIN_X}" y="{PAGE_H - 22}" fill="#94a3b8" font-size="9.5" '
                 f'font-family="Segoe UI,Arial">Relationships are derived from the '
                 f'*_id / *_by conventions documented in supabase/migrations (00109, 00110, 00128, 00130).</text>')
    parts.append(f'<text x="{PAGE_W - MARGIN_X}" y="{PAGE_H - 22}" fill="#94a3b8" font-size="9.5" '
                 f'text-anchor="end" font-family="Segoe UI,Arial">Page {page_no} of {total}</text>')
    return "".join(parts)


def render_lookups(page_no, total):
    names = [t for t in TABLE_ORDER if TABLES[t]["lookup"]]
    parts = [page_frame("Lookup / Reference Registry",
                        f"{len(names)} reference tables — identical shape, differing only in the seeded rows",
                        page_no, total, GROUPS["lookup"][1])]
    n_stack = 5
    per = -(-len(names) // n_stack)
    stacks = [names[i * per:(i + 1) * per] for i in range(n_stack)]
    stacks = [s for s in stacks if s]
    page = {"stacks": stacks}
    boxes, stack_index, _ = layout_stacks(page)
    rl = RELATIONS
    seen = set()
    for child, ccol, parent, pcol, o2o in rl:
        if child in boxes and parent in boxes and (child, ccol) not in seen:
            seen.add((child, ccol))
            parts.append(render_relation(boxes[child], ccol, boxes[parent], pcol, o2o,
                                         stack_index, len(stacks) - 1))
    refs = _ref_counts()
    for nm in boxes:
        boxes[nm].refs = refs.get(nm, 0)
        parts.append(render_box(boxes[nm]))
    # shape note
    ny = PAGE_H - 76
    parts.append(f'<rect x="{MARGIN_X}" y="{ny - 22}" width="{PAGE_W - 2 * MARGIN_X}" height="40" '
                 f'rx="6" fill="{GROUPS["lookup"][2]}" stroke="{GROUPS["lookup"][3]}"/>')
    parts.append(f'<text x="{MARGIN_X + 14}" y="{ny + 3}" fill="#0f766e" font-size="11.5" '
                 f'font-family="Segoe UI,Arial">Every table above declares: '
                 f'id uuid PK · code varchar UNIQUE · label varchar · description text NULL · '
                 f'is_active bool · sort_order int4 · created_at / updated_at timestamptz. '
                 f'Each is the parent of a *_id column on an operational table; '
                 f'the varchar twins (status, gender, …) are deprecated aliases kept for compatibility.</text>')
    return "".join(parts)


def _ref_counts():
    counts = {}
    for _child, _ccol, parent in ((c, cc, p) for c, cc, p, _pc, _o in RELATIONS):
        counts[parent] = counts.get(parent, 0) + 1
    return counts


def render_index(page_no, total):
    parts = [page_frame("Table Index",
                        f"{len(TABLES)} tables — column count, FK count and the page where the table is drawn",
                        page_no, total, "#0f172a")]
    pg = table_page_map()
    rows = []
    for name in TABLE_ORDER:
        t = TABLES[name]
        cols = len(t["cols"])
        fks = sum(1 for c in t["cols"] if c.get("target"))
        rows.append((name, GROUPS[t["group"]][0], cols, fks, pg.get(name, "—")))
    half = -(-len(rows) // 2)
    colw = (AVAIL_W - 40) / 2
    for idx, chunk in enumerate([rows[:half], rows[half:]]):
        x0 = MARGIN_X + idx * (colw + 40)
        y = TOP + 6
        parts.append(f'<text x="{x0}" y="{y}" fill="#64748b" font-size="9.5" font-weight="700" '
                     f'font-family="Segoe UI,Arial">TABLE</text>')
        parts.append(f'<text x="{x0 + colw - 210}" y="{y}" fill="#64748b" font-size="9.5" '
                     f'font-weight="700" text-anchor="end" font-family="Segoe UI,Arial">DOMAIN</text>')
        parts.append(f'<text x="{x0 + colw - 120}" y="{y}" fill="#64748b" font-size="9.5" '
                     f'font-weight="700" text-anchor="end" font-family="Segoe UI,Arial">COLS</text>')
        parts.append(f'<text x="{x0 + colw - 78}" y="{y}" fill="#64748b" font-size="9.5" '
                     f'font-weight="700" text-anchor="end" font-family="Segoe UI,Arial">FK</text>')
        parts.append(f'<text x="{x0 + colw}" y="{y}" fill="#64748b" font-size="9.5" '
                     f'font-weight="700" text-anchor="end" font-family="Segoe UI,Arial">PAGE</text>')
        y += 8
        parts.append(f'<line x1="{x0}" y1="{y}" x2="{x0 + colw}" y2="{y}" stroke="#e2e8f0"/>')
        y += 16
        for name, group, cols, fks, pno in chunk:
            parts.append(f'<text x="{x0}" y="{y}" fill="#111827" font-size="11" '
                         f'font-family="Cascadia Mono,Consolas,monospace">{esc(name)}</text>')
            parts.append(f'<text x="{x0 + colw - 210}" y="{y}" fill="#64748b" font-size="9.5" '
                         f'text-anchor="end" font-family="Segoe UI,Arial">{esc(group)}</text>')
            parts.append(f'<text x="{x0 + colw - 120}" y="{y}" fill="#334155" font-size="10" '
                         f'text-anchor="end" font-family="Segoe UI,Arial">{cols}</text>')
            parts.append(f'<text x="{x0 + colw - 78}" y="{y}" fill="#334155" font-size="10" '
                         f'text-anchor="end" font-family="Segoe UI,Arial">{fks}</text>')
            parts.append(f'<text x="{x0 + colw}" y="{y}" fill="#be123c" font-size="10.5" '
                         f'font-weight="700" text-anchor="end" font-family="Segoe UI,Arial">{pno}</text>')
            y += 19
    return "".join(parts)


TABLE_PAGE: dict[str, int] = {}


def table_page_map():
    if TABLE_PAGE:
        return TABLE_PAGE
    for i, page in enumerate(PAGES, start=1):
        for st in page.get("stacks", []):
            for t in st:
                TABLE_PAGE.setdefault(t, i)
        if page["kind"] == "lookups":
            for t in TABLE_ORDER:
                if TABLES[t]["lookup"]:
                    TABLE_PAGE.setdefault(t, i)
    return TABLE_PAGE


# --------------------------------------------------------------------------------------
# Orchestration
# --------------------------------------------------------------------------------------
def build_html(total):
    toc = []
    for i, page in enumerate(PAGES, start=1):
        if page["kind"] == "domain":
            toc.append((page["title"], i))
        elif page["kind"] == "lookups":
            toc.append(("Lookup / Reference Registry", i))
        elif page["kind"] == "index":
            toc.append(("Table Index", i))
    pages_svg = []
    for i, page in enumerate(PAGES, start=1):
        if page["kind"] == "cover":
            body = render_cover(i, total, toc)
        elif page["kind"] == "lookups":
            body = render_lookups(i, total)
        elif page["kind"] == "index":
            body = render_index(i, total)
        else:
            body = render_domain(page, i, total)
        pages_svg.append(
            f'<section class="page"><svg xmlns="http://www.w3.org/2000/svg" '
            f'width="{PAGE_W}" height="{PAGE_H}" viewBox="0 0 {PAGE_W} {PAGE_H}">{body}</svg></section>')

    css = """
@page { size: 18.75in 12.5in; margin: 0; }
html, body { margin: 0; padding: 0; background: #fff; }
.page { width: 1800px; height: 1200px; overflow: hidden; page-break-after: always;
        break-after: page; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
.page:last-child { page-break-after: auto; break-after: auto; }
svg { display: block; }
    """
    return ("<!doctype html><html><head><meta charset='utf-8'>"
            "<title>Jireta Loans — Visual ERD</title><style>" + css + "</style></head><body>"
            + "".join(pages_svg) + "</body></html>")


def validate():
    problems = []
    counts = {}
    for i, page in enumerate(PAGES, start=1):
        if "stacks" not in page:
            continue
        boxes, _, _ = layout_stacks(page)
        for t in page["stacks"]:
            for c in t:
                counts[c] = counts.get(c, 0) + 1
        for a in boxes.values():
            if a.y + a.h > PAGE_H - BOTTOM + 1:
                problems.append(f"p{i}: {a.name} overflows bottom by "
                                f"{a.y + a.h - (PAGE_H - BOTTOM):.0f}px")
            if a.x + a.w > PAGE_W - MARGIN_X + 1 or a.x < MARGIN_X - 1:
                problems.append(f"p{i}: {a.name} overflows horizontally")
        names = list(boxes)
        for j in range(len(names)):
            for k in range(j + 1, len(names)):
                a, b = boxes[names[j]], boxes[names[k]]
                if (a.x < b.x + b.w - 0.5 and b.x < a.x + a.w - 0.5 and
                        a.y < b.y + b.h - 0.5 and b.y < a.y + a.h - 0.5):
                    problems.append(f"p{i}: overlap {a.name} / {b.name}")
    missing = [t for t in TABLE_ORDER if t not in counts]
    if missing:
        problems.append("tables never drawn: " + ", ".join(missing))
    print(f"tables={len(TABLES)} relations={len(RELATIONS)} pages={len(PAGES)}")
    if problems:
        print("\n".join("  ! " + p for p in problems))
    else:
        print("layout OK: no overflow, no overlap, every table drawn at least once")
    return problems


def find_chrome():
    candidates = [
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        os.path.join(os.environ.get("LOCALAPPDATA", ""), "Google/Chrome/Application/chrome.exe"),
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    ]
    for c in candidates:
        if c and os.path.exists(c):
            return c
    raise SystemExit("Chrome/Edge not found — cannot print the PDF")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.expanduser("~"), "Desktop",
                                                 "jireta_loans_erd.pdf"))
    ap.add_argument("--html", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                  "..", "build", "erd", "erd.html"))
    args = ap.parse_args()

    problems = validate()
    if problems:
        print("refusing to print with layout problems", file=sys.stderr)
        return 2

    html = build_html(len(PAGES))
    html_path = os.path.abspath(args.html)
    os.makedirs(os.path.dirname(html_path), exist_ok=True)
    with open(html_path, "w", encoding="utf-8") as fh:
        fh.write(html)
    print("html:", html_path)

    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if os.path.exists(out):
        os.remove(out)

    chrome = find_chrome()
    url = "file:///" + html_path.replace("\\", "/")
    cmd = [chrome, "--headless=new", "--disable-gpu", "--no-sandbox",
           "--no-pdf-header-footer", "--run-all-compositor-stages-before-draw",
           "--virtual-time-budget=8000",
           f"--print-to-pdf={out}", url]
    print("printing ->", out)
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0 or not os.path.exists(out):
        print(res.stdout[-3000:], res.stderr[-3000:], sep="\n", file=sys.stderr)
        return 1
    print(f"pdf: {out} ({os.path.getsize(out) / 1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
