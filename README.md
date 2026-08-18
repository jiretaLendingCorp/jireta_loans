Analyze first this entire BACKEND AND FORNTEND and must connected first base of
this MD, SUPABASE, POSTGRESQL,FLUTTER DART, DENO TYPESCRIPT, RESTFUL API,
THIRDPARTY API, ALL SENSITIVE OPERATIONS, BUSINESS RULES, BUSINESS LOGIC,
COMPUTATION ETC.. MUST IN BACKEND before u code the entire codebase do not
comments in code except the file path for this Multi Platform Lending Management
system and fix first plan before you code front end enterprise design modern
design interactive and backend must connected then code the entire flutter
project system the name of company is Jireta Loans & Credit Corp 1966 and gumawa
ka ng folder kapag magcocode ka na head manager, Employee, Rider, Lender give
the advance code so the out will fine backend and frontend dapat connected sila
BACKEND MUNA I CODE MO BEFORE THE FRONTEND, code it in localhost muna at dapat i
expose kung anong laman ng env sa code

dapat visible ung mga text nila sa front end design ahh fix the layout
responsive

Make a file path para alam ko kung san ko ilalagay ung code sa flutter project,
dapat connected ang front end and backend

dapat walang loan products only money in this system

Do not expose any key in frontend must in env high security dapat wlang makitang
key ilagay sila sa .env gamit ang flutter_dotenv., Dapat meron din features
screen para makita ni lender kung nasaan na ung na assign na Rider. At meron din
screen para makita ni Rider kung saan location ni lender Wag na wag mong
ilalagay ung name na admin, manager, borrower, pero ganun parin capabilities
nila every role

dapat ganun name nila 4 roles Head manager Employee Rider Lender

Dapat ganto flow ng system na ito, super secure for lending management system
All Sensitive operations, business logic and rules must un backend

Rule: Flutter is a thin client. All business logic, permission enforcement,
database mutations, interest calculations, loan processing, payment processing,
user management etc.., and sensitive operations must live inside Supabase Edge
Functions (Deno TypeScript). Flutter should handle UI, local state, input
validation, secure storage etc.., and calling REST APIs or Edge Functions.
Requirements: Flutter must NOT directly to PostgreSQL tables except where
Supabase Auth officially requires it. Flutter must NOT contain business rules.
Flutter must NOT perform role validation, permission checks, approval logic,
loan calculations, payment logic, Account Upgrade decisions, or account state
changes. Flutter must call Edge Functions through Dio/REST for all sensitive
operations. Only Edge Functions may update the users, loans, payments,
collections, account_upgrade, notifications, and other business tables. Flutter
may only use Supabase Auth SDK for: signIn signOut refreshSession currentUser
OAuth OTP password reset Everything else must go through Edge Functions. Review
every generated file against these rules before returning the code. If any
violation exists, move that logic into the appropriate Edge Function and modify
the Flutter code so it only consumes the API.

┌──────────────────────────┐ │ Flutter │ │ (Frontend UI) │
└─────────────┬────────────┘ │ ▼ ┌──────────────────────────┐ │ RESTful API │
└─────────────┬────────────┘ │ ▼ ┌──────────────────────────┐ │ Edge Functions
(Deno) │ │ Business Logic │ └───────┬──────────┬───────┘ │ │ ▼ ▼
┌──────────────┐ ┌──────────────────┐ │ PostgreSQL │ │ Third-Party APIs │ │
(Supabase) │ │ │ │ │ │ │ │ │ │ └──────────────┘ └──────────────────┘

The system must be scalable, secure, modular, production-ready, and follow
enterprise FinTech standards. --- # TECHNOLOGY STACK Frontend * Flutter (Single
Codebase) * Flutter Web * Flutter Mobile * Dart Backend * Supabase *
PostgreSQL * Supabase Auth * Supabase Storage * Supabase Realtime * Supabase
Edge Functions (Deno TypeScript) * REST API * Dio Communication Layer
Architecture * Clean Architecture * Feature-first Folder Structure * Repository
Pattern * Service Layer * Dependency Injection * Riverpod State Management *
Secure API Layer * RBAC (Role-Based Access Control) --- # USER ROLES The system
contains four user roles: 1. Head Manager (Admin) 2. Employee (Manager) 3.
Rider 4. Lender (Borrower) Every role must have its own dedicated dashboard,
navigation, permissions, features, analytics, and management modules. No role
may access another role's protected resources unless explicitly permitted
through RBAC. --- # DASHBOARD DESIGN REQUIREMENTS Design every dashboard as a
complete enterprise workspace instead of only showing KPI cards. Do NOT design
dashboards that only contain charts or summary cards. Each dashboard must
function as a real management workspace. Every dashboard must contain: *
Lifetime Statistics * Pending Requests * Notifications * Recent Activities *
Complete Management Tables * Search * Advanced Filters * Sorting * Pagination *
Quick Actions * Export PDF * Export Excel * View Details * Activity Timeline *
Status History Never hide critical information behind summary cards. Every
important record must have a dedicated **View Details** page or modal before
users can perform any action. Approval actions must never appear directly inside
table rows. Users must first review complete information before approving or
rejecting. --- # HEAD MANAGER (ADMIN) Purpose Provide complete administrative
control over the Lending Management System. Lifetime Statistics * Total
Employees * Total Riders * Total Borrowers * Total Registered Users * Total Loan
Applications * Total Approved Loans * Total Rejected Loans * Total Pending
Loans * Total Active Loans * Total Completed Loans * Total Cancelled Loans *
Total Overdue Loans * Total Loan Amount Released * Total Loan Amount Collected *
Total Outstanding Balance * Total Interest Earned * Total Penalties Collected *
Total Revenue * Total Collection Transactions Modules Dashboard * View Lifetime
Statistics * Notifications * Recent Activities Employee Management * Create *
View * View Details * Edit * Suspend * Activate * Archive Rider Management *
Create * View * View Details * Edit * Suspend * Activate * Archive Borrower
Management * View * View Details * Edit * Suspend * Activate * Archive Loan
Management * View Applications * Review Applications * Approve * Reject *
Request Additional Documents * Release Loan * Cancel Loan * Active Loans *
Completed Loans * Overdue Loans * Loan History Account Upgrade Management *
Review Account Upgrade * View Details * Approve * Reject * Request Additional
Documents Payment Management * View Payments * View Payment Details * Verify
Payments * Reverse Payment (Authorized Only) Collection Management * Assign
Rider * Reassign Rider * Monitor Collection Status * View Collection Details
Reports * Generate Reports * Export PDF * Export Excel Audit * Audit Logs *
Activity Logs Notification Management * Send Notifications * View Notifications
System * Roles * Permissions * Settings Profile * View Profile * Edit Profile *
Change Password --- # EMPLOYEE (MANAGER) Purpose Manage loan applications,
borrowers, collections, and daily operations. Lifetime Statistics * Total
Borrowers Managed * Total Loan Applications Processed * Total Approved Loans *
Total Rejected Loans * Total Active Loans * Total Completed Loans * Total
Collections Managed Modules Dashboard * Lifetime Statistics * Notifications *
Recent Activities Borrowers * Register * View * View Details * Edit Loans *
Review Applications * Verify Requirements * Request Documents * Recommend
Approval * Recommend Rejection * View Loan Details Account Upgrade * Review *
Verify * Recommend Approval * Recommend Rejection Collections * Assign Rider *
Monitor Collections Payments * View * View Details Reports * Generate * Export
Profile * View * Edit * Change Password --- # RIDER Purpose Manage assigned
borrower collections. Lifetime Statistics * Total Assigned Collections * Total
Completed Collections * Total Failed Collections * Total Amount Collected
Modules Dashboard * Lifetime Statistics * Notifications Collections * Assigned
Collections * View Collection Details * Update Status * Collect Payment * Upload
Proof * Add Notes Borrowers * View Borrower Information * View Address * View
Loan Details * Contact Borrower Payments * View Payment Information Profile *
View * Edit * Change Password --- # LENDER (BORROWER) Purpose Manage loans,
payments, and personal account. Lifetime Statistics * Total Loan Applications *
Total Approved Loans * Total Rejected Loans * Total Active Loans * Total
Completed Loans * Total Amount Borrowed * Total Amount Paid * Total Remaining
Balance * Total Interest Paid * Total Penalties Paid Modules Authentication *
Register * Login * Logout * Forgot Password * Reset Password Profile * View *
Edit * Upload Photo Account Upgrade * Submit * Update * View Status Loans *
Apply Loan * View Application * View Loan Details * Cancel Pending Loan * Loan
History Payments * Payment Schedule * Payment Details * Payment History *
Download Receipt Collections * Collection History Documents * Upload
Requirements * View Uploaded Documents Notifications * View Notifications --- #
VIEW DETAILS REQUIREMENTS Every entity must have a complete View Details page.
Borrower Details * Personal Information * Contact Information * Address *
Government IDs * Selfie Verification * Uploaded Documents * Account Upgrade
Status * Active Loan * Loan History * Payment History * Collection History *
Account Status * Notes * Timeline Loan Details * Loan Number * Borrower
Information * Loan Amount * Interest * Total Payable * Loan Term * Remaining
Balance * Payment Schedule * Payment History * Collection History * Assigned
Employee * Assigned Rider * Approval History * Status Timeline Payment Details *
Payment Number * Borrower * Loan * Amount * Remaining Balance * Payment Method *
Receipt * Payment Status Collection Details * Collection Number * Rider *
Borrower * Loan * Amount Collected * Proof of Collection * Collection Notes *
Collection Status Employee Details * Employee Information * Assigned Borrowers *
Assigned Riders * Loan Processing History * Activity History Rider Details *
Rider Information * Assigned Collections * Collection History * Uploaded
Proofs * Activity History Account Upgrade Details * Borrower Information *
Uploaded IDs * Selfie Verification * Supporting Documents * Verification Notes *
Status Timeline --- # SYSTEM REQUIREMENTS Every management table must support: *
Search * Advanced Filters * Sorting * Pagination * View Details * Export PDF *
Export Excel All approval processes must require the reviewer to open the
complete View Details page before approving or rejecting. No approved, rejected,
cancelled, completed, or historical record may ever disappear from the database.
Every record must remain permanently accessible according to system retention
policies. All modules must enforce Role-Based Access Control (RBAC). The
application must follow enterprise-level security, modular architecture,
maintainability, scalability, and production-ready coding standards. #
ADDITIONAL ENTERPRISE WORKFLOW REQUIREMENTS ## CREDIT INVESTIGATION ASSIGNMENT
WORKFLOW Before any loan application can be approved, the borrower must first
complete Account Upgrade submission. Once the borrower submits the Account
Upgrade requirements, the application shall immediately become visible to both
the **Head Manager (Admin)** and **Employee (Manager)**. Both roles are
authorized to review the complete borrower profile before taking any action. The
review page must include: * Personal Information * Contact Information * Present
Address * Permanent Address * Government IDs * Selfie Verification * Uploaded
Documents * Employment Information * Source of Income * Emergency Contacts *
Loan Request Information * Previous Loan History * Payment History * Credit
Investigation Status * Activity Timeline Neither the Head Manager nor the
Employee may approve a loan immediately after Account Upgrade submission. The
first required action is to assign a Rider for Credit Investigation. Both the
Head Manager and the Employee are authorized to assign a Rider. The assignment
record must store: * Assigned Rider * Assigned By (Authenticated User) *
Assigned Date and Time * Investigation Deadline * Investigation Notes *
Assignment Status Only the authenticated user who performed the assignment shall
appear as the "Assigned By" user. If the Head Manager assigned the Rider, the
assignment record must display the Head Manager's identity. If the Employee
assigned the Rider, the assignment record must display the Employee's identity.
Immediately after assignment: * The assigned Rider shall receive a push
notification. * The Head Manager or Employee who performed the assignment shall
receive confirmation. * The assignment shall appear inside the Rider dashboard.
The Rider must have the ability to: * Accept Assignment * Decline Assignment *
View Complete Borrower Information * Navigate to Borrower Address * Perform
Credit Investigation * Upload Investigation Photos * Upload Supporting
Evidence * Add Investigation Notes * Submit Investigation Report The submitted
investigation report shall automatically become visible to both the Head Manager
and the Employee. Only after the investigation report has been submitted may the
loan proceed to the approval stage. --- # COLLECTION ASSIGNMENT WORKFLOW When a
borrower has an active loan, payment collection shall support three payment
channels. ## GCash Payment The borrower may pay directly using GCash. Payment
processing shall be integrated with the Xendit API. Development environment
shall use Xendit Sandbox APIs only. Production environment shall use Xendit Live
APIs. After successful payment: * Payment Record * Receipt * Transaction
Reference * Collection History * Loan Balance must automatically update. --- ##
Office Payment The borrower may visit the office to pay directly. The employee
shall verify the borrower's identity by reviewing previously submitted Account
Upgrade documents before accepting payment. The employee shall record: * Payment
Amount * Payment Method * Receipt Number * Remaining Balance * Payment Notes ---
## Cash Collection by Rider The Head Manager or Employee may assign a Rider to
collect payment from the borrower. The assignment shall contain: * Assigned
Rider * Assigned By * Assignment Date * Collection Schedule * Collection Notes
The authenticated user who assigned the Rider must always be recorded. The Rider
shall receive a notification immediately after assignment. The Rider shall be
able to: * View Collection Assignment * Collect Cash Payment * Upload Payment
Proof * Upload Borrower Signature * Upload Collection Photo * Add Collection
Notes * Complete Collection After completion: * Borrower * Assigned Employee or
Head Manager * Audit Logs shall all receive notifications. --- # DISBURSEMENT
WORKFLOW Loan release shall support three disbursement methods. ## GCash
Disbursement Funds shall be transferred through Xendit API integration.
Development must use Sandbox APIs. Production must use Live APIs. Every transfer
must record: * Transaction Reference * Amount * Status * Timestamp * Audit Log
--- ## Office Cash Release Borrowers may claim loan proceeds at the office.
Before releasing funds, the employee shall review all submitted Account Upgrade
documents. The employee shall verify: * Government IDs * Selfie Verification *
Approved Loan * Borrower Identity Only after successful verification may funds
be released. --- ## Rider Cash Delivery The Head Manager or Employee may assign
a Rider to deliver loan proceeds. The assignment record shall include: *
Assigned Rider * Assigned By * Delivery Date * Delivery Notes * Delivery Status
The authenticated user who assigned the Rider must always be recorded. The Rider
shall: * Accept Delivery Assignment * Deliver Cash * Upload Borrower Signature *
Upload Delivery Photo * Upload Proof of Release * Complete Delivery All
activities must be recorded inside the Audit Log. --- # REPORT MANAGEMENT Only
the Head Manager (Admin) may access the complete Reports Library. Reports shall
not be generated from scratch every time. Instead, the system shall maintain a
centralized Report Template Library. The library shall contain professionally
designed templates for: * Loan Reports * Collection Reports * Payment Reports *
Borrower Reports * Rider Reports * Employee Reports * Financial Reports *
Revenue Reports * Interest Reports * Penalty Reports * Overdue Loan Reports *
Audit Reports * Activity Reports * Credit Investigation Reports * Disbursement
Reports Every report template shall support: * PDF Export * Excel Export The
Head Manager shall be able to: * Preview Reports * Select Report Templates *
Filter Data * Generate Reports * Download PDF * Download Excel * Print Reports *
Save Report History Generated reports shall be archived and remain available for
future viewing and downloading.

modal for CRUID

MUST REALTIME AND

remove mo ung name

the role user is 1.Head manager full access - website 2.Employee - website 3.
Rider - mobile 4.Lender - mobile

all third party api;

1. xendit disbursment and collection
2. push notification
3. sms para ma notify si lender before 2 days due date payment
4. ung sa register dapat ang nakalagay ung is number lang kasi si lender lang
   mag register at may mag send sa kanya ng otp para makalogin

RESTFUL API, 3RD NF

at dapat kapag nag create ng users si head manager ng mga user dapat mag force
change password ung mga na create na account sa mga user na nacreate, then sa
Employee naman and ma create niya lang na user is Rider and Lender lang ganun
din force change password kapag head manager and Employee ung gumawa

dapat may rate limiting ahh, pati ung SQL Injection Prevention – The system
prevents SQL injection attacks by using parameterized database queries,
server-side input validation, and secure database access through Supabase Edge
Functions. These measures ensure that user input is treated as data rather than
executable SQL commands, protecting the database from unauthorized manipulation.

at kapag may walk in or gustong mag apply sa kanila ung Head Manager or Employee
na ung gagawa ibibigay lang ni lender ung need para makapag apply

Use Dart async and await for all asynchronous operations. Use Future for
one-time data retrieval. Use Stream for continuous real-time data updates.
Ensure every Create, Read, Update, and Delete (CRUD) operation immediately
updates the user interface without requiring a page reload or application
restart.

list all of the security integrate all high security for back end and front end
that system lending management system

at dun sa login page ng mobile ay dapat may google sign in depende nalang kung
google sign in or register pipiliin ni lender

at dapat ma reset at nakadefault lahat ng password sa 12345678 kapag si head
manager or Employee and gumawa ng account sa lahat ng role daapat naka default
sa 12345678

at dapat si head manager nag add ng user dapat hindi lang email ung na aad niya
dapat may mga provided pa na mga details example kung sa mag create ng account
si head manager sa rider dapat lalabas ung mga important details na i aad like
email, number, drivers license etc... ganun din sa employee at lender ung mga
important

pagkabukas ng mobile app dapat ang makikita ay ung terms and codition and
privacy policy ba ung at kapag di nila na na accept un di sila makakapag proceed
asa login page ng mobile

tas wag kang maglalagay ng todays collections etc.. sa frontend dapat static
life metric din hindi lang sa backend

ito naman und erd ng system baguhin mo dito ung iba base dyan sa sinabi kong
capabilities nila ahh, dapat connected si front end and back end ang
capabilities, ayusin mo nalang ung erd base dyan sa capabilities every role na
nasabi dyan

INTERACTIVE UI/UX DESIGN Design the application as a highly interactive
enterprise financial system. Every screen and component must provide smooth and
intuitive user interactions.

Here's the system documentation with the Flutter file paths removed:

---

# 1. HEAD MANAGER (HM) — WEB

**Platform:** Flutter Web | **Login:** Email + Password | **Color:** Navy + Gold
Sidebar

Full system access. 19 KPI stat cards on dashboard. Collapsible sidebar
navigation. All CRUD via modals. Approvals only accessible from full View
Details screen — never from the list.

## 1.1 KPI Dashboard Cards (19 metrics)

| KPI Metric                    | Description                                                    |
| ----------------------------- | -------------------------------------------------------------- |
| Total Employees               | Lifetime count of all employee accounts (active + archived).   |
| Total Riders                  | Lifetime count of all rider accounts.                          |
| Total Lenders                 | Lifetime count of all lender (borrower) accounts.              |
| Total Loan Applications       | All loan applications ever submitted (all statuses).           |
| Total Approved Loans          | All-time approved loan count.                                  |
| Total Rejected Loans          | All-time rejected loan count.                                  |
| Total Active Loans            | Currently active (disbursed, not yet completed) loans.         |
| Total Completed Loans         | Fully paid-off loans.                                          |
| Total Overdue Loans           | Loans flagged as overdue (1+ month delay).                     |
| Total Loan Amount Released    | Cumulative disbursed amount (₱).                               |
| Total Amount Collected        | Cumulative cash + GCash collected (₱).                         |
| Total Outstanding Balance     | Sum of all remaining loan balances (₱).                        |
| Total Interest Earned         | Sum of interest component of all active + completed loans (₱). |
| Total Penalties Collected     | Sum of all applied penalties (₱).                              |
| Total Revenue                 | Interest + Penalties + Charges collected (₱).                  |
| Total Collection Transactions | Count of all collection records (cash + GCash + rider).        |
| Total CI Assignments          | All credit investigation assignments ever created.             |
| Total Report Exports          | Count of generated/exported reports.                           |
| Total Pending Account Upgrade | Account Upgrade submissions currently awaiting review.         |

## 1.2 All Screens & Capabilities

| Screen / Feature                              | Capability                                                                                                                                                                                                   |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Web Login                                     | Email + password login. Redirects to dashboard on success.                                                                                                                                                   |
| Force Change Password                         | Shown on first login when force_password_change=TRUE. Blocks all other routes until completed.                                                                                                               |
| Forgot Password                               | Sends reset link to email.                                                                                                                                                                                   |
| Reset Password                                | Token-based password reset via email link.                                                                                                                                                                   |
| Dashboard                                     | Displays 19 animated KPI stat cards + realtime activity feed. Charts: monthly disbursements, collections, active loans by status.                                                                            |
| Dashboard — KPI Provider                      | Fetches all 19 KPI metrics from Edge Function. Realtime Supabase subscription updates counters live.                                                                                                         |
| Dashboard — KPI Card Grid                     | Grid widget rendering all 19 KPI cards with count-up animation.                                                                                                                                              |
| Dashboard — Activity Feed                     | Real-time scrollable feed of recent loan, Account Upgrade, payment, and CI events.                                                                                                                           |
| In-Office Application — List                  | Shows all in-office applications with status (draft/submitted/converted). Search + filter by status + date.                                                                                                  |
| In-Office Application — Wizard                | 5-step wizard container. Manages step navigation, back/next buttons, step indicator bar, draft auto-save.                                                                                                    |
| In-Office Application — Provider              | Holds wizard state, calls all in-office/* Edge Functions.                                                                                                                                                    |
| In-Office — Step 1: Identify Borrower         | Live search existing lender by phone/name. Shows match card. If not found: inline create form (name, phone, gender, civil status, DOB, employment, income, GCash).                                           |
| In-Office — Step 2: Address & Contacts        | Home/work/provincial address forms with GPS coordinate fields. Emergency contacts (name, relationship, phone). Add multiple contacts.                                                                        |
| In-Office — Step 3: Loan Details              | Amount input (₱3,000–₱500,000), payment frequency selector (daily/weekly/monthly), purpose field. Calls loans/get-schedule-preview Edge Function — displays installment table live. No Dart math.            |
| In-Office — Step 4: Co-Maker                  | Co-maker form: name, relationship, birthday, contact, address. Co-maker document upload. Note displayed: "Co-maker is NOT subjected to CI."                                                                  |
| In-Office — Step 5: Docs + Signature + Submit | Document uploader (valid ID, proof of income, barangay clearance, pay slip). Signature pad widget (borrower signs). Summary review card. Confirm + Submit.                                                   |
| Employee List                                 | Enterprise table: search, filter (status/department), sort, paginate, bulk select, export CSV. Row actions: view details, edit, suspend, activate, archive.                                                  |
| Employee Details                              | Full profile view: personal info, contact, department, position, hired date, account status, activity log.                                                                                                   |
| Employee Provider                             | Fetches/mutates employee data via users/* Edge Functions.                                                                                                                                                    |
| Create Employee Modal                         | Form: first/middle/last name, suffix, gender, civil status, DOB, email, department, position, hired_at. Submits to users/create-employee. Default password 12345678.                                         |
| Edit Employee Modal                           | Same fields as create. Pre-populated. Submits to users/update-profile.                                                                                                                                       |
| Rider List                                    | Enterprise table with search, filter (status/vehicle type), sort, paginate. Row actions: view, edit, suspend, activate, archive.                                                                             |
| Rider Details                                 | Profile: name, plate, vehicle type, drivers license, status (available/on_duty/off), total collected lifetime, is_active, assignment history.                                                                |
| Rider Provider                                | Fetches/mutates rider data.                                                                                                                                                                                  |
| Create Rider Modal                            | Form: first/middle/last name, phone, vehicle type, plate number, drivers license. Default password 12345678.                                                                                                 |
| Edit Rider Modal                              | Same fields as create. Pre-populated.                                                                                                                                                                        |
| Lender List                                   | Enterprise table. Columns: name, phone, GCash, Account Upgrade status, active loan, blacklist status, account status. Row actions: view, edit, suspend, activate, archive, blacklist.                        |
| Lender Details                                | Full profile: personal info, addresses, emergency contacts, documents, Account Upgrade submissions, loans history, payment history, blacklist history.                                                       |
| Lender Provider                               | Fetches/mutates lender profile, Account Upgrade, and status.                                                                                                                                                 |
| Create Lender Modal (Walk-in)                 | Form: name, phone, gender, civil status, DOB, employment, monthly income, GCash number. Submits to users/create-lender.                                                                                      |
| Blacklist Modal                               | Reason input. Confirm dialog. Submits to blacklist/add or blacklist/remove.                                                                                                                                  |
| Loan Applications List                        | Enterprise table. Tabs: All / Pending / Under Review / CI Required. Columns: loan#, lender, amount, date, status. Filter by status, date, amount range.                                                      |
| Loan Application Details                      | Full review: lender profile, Account Upgrade status, co-maker info, documents, requested amount, purpose. Action buttons: Approve, Reject, Request CI, Cancel. Buttons appear only on details — not on list. |
| Loan List                                     | Tabs: Active / Completed / Overdue / History. Search, filter, sort, paginate.                                                                                                                                |
| Loan Details                                  | Full loan view: loan#, lender info, amounts, schedule, payment history, disbursement info, penalty history, collections.                                                                                     |
| Loan Schedule                                 | Period-by-period payment schedule table. Due date, amount due, amount paid, status per row.                                                                                                                  |
| Loan Provider                                 | All loan CRUD: approve, reject, cancel, penalty. Calls loans/* Edge Functions.                                                                                                                               |
| Approve / Reject Modal                        | Confirm dialog with summary. Reject shows reason textarea. Submits to loans/approve or loans/reject.                                                                                                         |
| Penalty Modal                                 | Confirms penalty amount (20% of total_payable — fetched from server preview). Reason field. Submits to loans/apply-penalty.                                                                                  |
| Account Upgrade List                          | Enterprise table. Columns: lender name, doc type, submitted date, status. Filter by status/date.                                                                                                             |
| Account Upgrade Details                       | Shows uploaded document with signed URL viewer. Verification buttons: Verified / Rejected. Remarks textarea. Submits to kyc-view?fn=verify.                                                                  |
| Account Upgrade Provider                      | Fetches account upgrade list and handles verify/reject calls.                                                                                                                                                |
| CI List                                       | Enterprise table. Columns: loan#, lender, rider assigned, status, deadline, assigned by. Filter by status/rider/date.                                                                                        |
| CI Details                                    | Full CI view: borrower address, assigned rider, CI notes, rider notes, documents gallery (photos + evidence with GPS coordinates), completion status.                                                        |
| CI Provider                                   | Handles CI assign and monitor calls.                                                                                                                                                                         |
| CI Assign Modal                               | Rider picker dropdown (available riders only). Investigation notes. Deadline picker. Submits to ci/assign.                                                                                                   |
| Collection List                               | Enterprise table. Columns: loan#, lender, rider, schedule, status. Filter by rider/status/date.                                                                                                              |
| Collection Details                            | Assignment details: borrower info, rider info, collection status, proof photos, signature, GPS coordinates of collection, amount collected.                                                                  |
| Collection Provider                           | Handles assign, reassign, monitor.                                                                                                                                                                           |
| Assign Rider Modal (Collection)               | Rider picker. Collection schedule datetime picker. Notes field. Submits to collections/assign.                                                                                                               |
| Disbursement List                             | Enterprise table. Columns: loan#, lender, method (GCash/Cash/Rider), amount, status, date.                                                                                                                   |
| Disbursement Details                          | Method-specific details: GCash shows Xendit reference; Cash shows office notes; Rider shows delivery proof + signature.                                                                                      |
| Disbursement Provider                         | Handles all three disbursement methods.                                                                                                                                                                      |
| Disburse Modal                                | Three-tab modal: GCash (Xendit), Office Cash (identity confirm), Rider Delivery (rider picker). Submits to correct disbursements/* Edge Function.                                                            |
| Payment List                                  | Enterprise table. Columns: payment#, loan#, lender, amount, method, date, status. Filter by method/date/status.                                                                                              |
| Payment Details                               | Payment info: reference#, Xendit ID, amount, method, date, recorded by, remaining balance after payment.                                                                                                     |
| Payment Provider                              | Fetches payments. Handles verify/reverse.                                                                                                                                                                    |
| Penalty List                                  | All penalties. Columns: loan#, lender, base amount, rate, penalty amount, applied by, date.                                                                                                                  |
| Penalty Provider                              | Fetches penalty history.                                                                                                                                                                                     |
| Blacklist Management                          | List of all blacklisted lenders. Add/remove blacklist buttons. Reason display. History of who blacklisted/removed.                                                                                           |
| Blacklist Provider                            | Calls blacklist/add, blacklist/remove, blacklist/get-list.                                                                                                                                                   |
| Report Library                                | Grid of all 13 report templates with type, PDF/Excel support, description. "Generate" button opens filter modal.                                                                                             |
| Generate Report                               | Date range picker, filter options (by status/role/rider etc.), preview table, Export PDF, Export Excel, Print buttons. Calls reports/generate.                                                               |
| Report History                                | Archived generated reports with download links (signed URL). Filter by date/type.                                                                                                                            |
| Report Provider                               | Manages report generation and download.                                                                                                                                                                      |
| Audit Logs                                    | Full audit trail table. Columns: action, performed by, table, record ID, old/new values (JSON diff view), IP, datetime. Export.                                                                              |
| Audit Provider                                | Fetches audit logs with pagination and filters.                                                                                                                                                              |
| Notification Center                           | List of all notifications sent. Send push notification modal (recipient, title, message). SMS logs tab.                                                                                                      |
| HM Notification Provider                      | Handles list, send, SMS logs.                                                                                                                                                                                |
| System Settings                               | Roles list, Permissions matrix, SMS Templates editor, Report Templates manager, System config values.                                                                                                        |
| HM Profile                                    | View/edit: name, gender, civil status, DOB, profile photo. Change password form.                                                                                                                             |
| HM Profile Provider                           | Fetches and updates HM profile.                                                                                                                                                                              |

---

# 2. EMPLOYEE — WEB

**Platform:** Flutter Web | **Login:** Email + Password | **Same portal as HM —
RBAC enforced server-side**

Processes loan applications, verifies Account Upgrades, assigns riders for CI
and collections, records office payments. Cannot access: reports, audit logs,
blacklist management, system settings. Employee-created In-Office drafts are
only visible to own account (HM sees all).

## 2.1 Dashboard KPI Cards (7 metrics)

| KPI Metric                   | Description                                           |
| ---------------------------- | ----------------------------------------------------- |
| Total Lenders Managed        | Count of lenders created or managed by this employee. |
| Total Applications Processed | Loan applications the employee reviewed/recommended.  |
| Total Approved Loans         | Approved through employee recommendation.             |
| Total Rejected Loans         | Rejected through employee recommendation.             |
| Total Active Loans           | Loans currently active that the employee processed.   |
| Total Completed Loans        | Fully paid loans that the employee processed.         |
| Total Collections Managed    | Collection assignments the employee created.          |

## 2.2 All Screens & Capabilities

| Screen / Feature               | Capability                                                                                                                         |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| Web Login                      | Email + password. Same portal as HM — RBAC enforced server-side.                                                                   |
| Force Change Password          | Same screen as HM.                                                                                                                 |
| Dashboard                      | KPI stat cards (7 metrics) + activity feed for own processed applications.                                                         |
| Emp Dashboard Provider         | Fetches employee-scoped KPIs.                                                                                                      |
| In-Office Application — List   | Same wizard as HM. Employee-created drafts only visible to own account (HM sees all).                                              |
| In-Office Application — Wizard | Re-uses all 5 step widgets. Wizard wrapper specific to employee routes.                                                            |
| Emp In-Office Provider         | Employee-scoped calls to in-office/* Edge Functions.                                                                               |
| Lender List (Managed)          | Table of lenders. Employee can view, register walk-in, edit. Cannot suspend/archive/blacklist.                                     |
| Lender Details                 | Full profile view. Read-only for blacklist/archive — those buttons hidden for Employee role.                                       |
| Emp Lender Provider            | Lender CRUD limited to employee permissions.                                                                                       |
| Rider List                     | Table. Employee can create, view, edit riders.                                                                                     |
| Rider Details                  | Rider profile, assignment history, total collected.                                                                                |
| Emp Rider Provider             | Rider CRUD for employee.                                                                                                           |
| Loan Applications              | Table of loan applications. Employee can review, verify requirements, request docs, recommend approve/reject.                      |
| Loan Details                   | Full loan view with employee-allowed actions: verify, recommend, request docs, authorize disbursement.                             |
| Emp Loan Provider              | Handles employee-scoped loan actions.                                                                                              |
| Account Upgrade Review List    | Pending Account Upgrade list. Employee can verify or recommend reject.                                                             |
| Account Upgrade Details        | Document viewer + verify/reject action. Remarks textarea.                                                                          |
| Emp Account Upgrade Provider   | Account Upgrade verify calls for employee.                                                                                         |
| CI List                        | CI assignments for monitoring. Employee can assign rider, view status, view report.                                                |
| CI Details                     | CI report viewer, document gallery, rider notes.                                                                                   |
| Emp CI Provider                | CI assign + monitor for employee.                                                                                                  |
| Collection List                | Employee can assign rider, reassign, monitor status.                                                                               |
| Collection Details             | Assignment details, proof, collection status.                                                                                      |
| Emp Collection Provider        | Collection assign + monitor.                                                                                                       |
| Payment List                   | All payments. Employee can record office cash payments.                                                                            |
| Record Office Payment          | Form: loan selector, amount, payment date, notes. Idempotency key generated client-side (UUID). Submits to payments/record-office. |
| Emp Payment Provider           | Handles payment record + list for employee.                                                                                        |
| Notifications                  | View notification list. Send push notification to specific lender or rider.                                                        |
| Employee Profile               | View/edit own profile. Change password.                                                                                            |

---

# 3. RIDER — MOBILE

**Platform:** Flutter Mobile (iOS + Android) | **Login:** Phone + OTP | **Bottom
Nav:** Green accent

Field agent. Receives collection and CI assignments via push notifications.
Shares GPS location with lender during active assignments. Uploads proof photos,
borrower signatures, and CI documents — all with GPS coordinates. Does NOT
access any financial data beyond what is needed for assigned tasks.

## 3.1 Dashboard KPI Cards (6 metrics)

| KPI Metric                  | Description                                  |
| --------------------------- | -------------------------------------------- |
| Total Assigned Collections  | All collection assignments ever received.    |
| Total Completed Collections | Successfully completed collections.          |
| Total Failed Collections    | Collections where rider could not collect.   |
| Total Amount Collected      | Lifetime cumulative cash collected (₱).      |
| Total CI Assignments        | All CI assignments ever received.            |
| Total CI Completed          | Successfully completed CI reports submitted. |

## 3.2 All Screens & Capabilities

| Screen / Feature                  | Capability                                                                                                                               |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Splash                            | Checks auth state. If valid → dashboard. First run → T&C.                                                                                |
| Terms & Conditions                | One-time acceptance on first install. Must accept to continue.                                                                           |
| Mobile Login (Rider)              | Phone number + OTP. No register option.                                                                                                  |
| OTP Verify                        | 6-digit OTP input with 60s resend timer.                                                                                                 |
| Force Change Password             | Mandatory on first login.                                                                                                                |
| Dashboard                         | Stats: total assigned, completed, failed, amount collected, CI total. List of today's assigned tasks (collections + CI).                 |
| Rider Dashboard Provider          | Fetches rider-scoped stats and active assignments.                                                                                       |
| Collection List                   | List of all collection assignments. Tabs: Pending / Accepted / Completed / Failed.                                                       |
| Collection Details                | Assignment info: borrower name, loan#, amount due, schedule, notes. Accept / Decline buttons.                                            |
| Borrower Info (Collection)        | Full borrower profile: name, phone, addresses. Call/message shortcuts.                                                                   |
| Navigate to Borrower (Collection) | Google Maps screen showing route from rider current location to borrower home address.                                                   |
| Record Collection                 | Amount collected input. Payment method. Notes. GPS auto-captured. Submits to collections/record.                                         |
| Upload Collection Proof           | Camera/gallery picker for: payment proof photo, borrower signature pad, scene photo. Submits to collections/upload-proof.                |
| Rider Collection Provider         | Handles accept, decline, record, proof upload, GPS posting.                                                                              |
| CI List                           | CI assignments. Tabs: Pending / Accepted / In Progress / Completed.                                                                      |
| CI Details                        | CI assignment: borrower to investigate, deadline, notes from assigning officer. Accept / Decline.                                        |
| Borrower Info (CI)                | Borrower profile + addresses for CI visit.                                                                                               |
| Navigate to Borrower (CI)         | Google Maps route to borrower address for CI visit.                                                                                      |
| Upload CI Documents               | Camera/gallery picker. Caption input per photo. GPS auto-tagged. Photo types: site photo, neighbor interview, proof of residence, other. |
| Submit CI Report                  | Rider writes investigation notes/report. Reviews all uploaded documents. Submit button triggers ci/submit-report.                        |
| Rider CI Provider                 | CI accept, decline, upload, submit.                                                                                                      |
| Location Service                  | Background GPS posting every 30s during active assignment. Calls location/update-rider Edge Function.                                    |
| Rider Location Provider           | Manages location permission, tracking state, GPS stream.                                                                                 |
| Notifications (Rider)             | List of push notifications. Mark read. Assignment notifications deep-link to relevant screen.                                            |
| Rider Notification Provider       | Fetches and marks notifications. FCM foreground listener.                                                                                |
| Rider Profile                     | View/edit: name, profile photo, plate, vehicle, drivers license. Change password.                                                        |
| Rider Profile Provider            | Fetches and updates rider profile.                                                                                                       |

---

# 4. LENDER — MOBILE

**Platform:** Flutter Mobile (iOS + Android) | **Login:** Phone + OTP or Google
Sign-In | **Bottom Nav:** Purple accent | **NO SELF-REGISTRATION**

The borrower role. Account is always created by HM or Employee — either
standalone (Create Lender modal) or during In-Office Application wizard Step 1.
The Lender mobile app has NO register screen, NO "Create Account" button, and NO
/register route. The first screen after Terms & Conditions is the Login page.

Lender can: submit Account Upgrade, apply for a loan (if Account Upgrade
verified + no active loan + not blacklisted), pay via GCash (Xendit), view their
assigned rider's real-time location on a map, and download payment receipts.

## 4.1 Dashboard KPI Cards (10 metrics)

| KPI Metric           | Description                                                  |
| -------------------- | ------------------------------------------------------------ |
| Total Applications   | All loan applications submitted by this lender.              |
| Total Approved       | Applications that were approved.                             |
| Total Rejected       | Applications that were rejected.                             |
| Total Active         | Currently active (disbursed) loans.                          |
| Total Completed      | Fully paid off loans.                                        |
| Total Borrowed       | Cumulative approved loan amounts (₱).                        |
| Total Paid           | Total amount paid across all loans (₱).                      |
| Remaining Balance    | Outstanding balance on active loan (₱). 0 if no active loan. |
| Total Interest Paid  | Cumulative interest portion paid (₱).                        |
| Total Penalties Paid | Cumulative penalties paid (₱).                               |

## 4.2 All Screens & Capabilities

| Screen / Feature                | Capability                                                                                                                                                                             |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Splash                          | Checks auth state. If logged in → dashboard. If no session → T&C → Login.                                                                                                              |
| Terms & Conditions              | One-time acceptance. Cannot proceed without accepting. Logs to terms_consent_logs.                                                                                                     |
| Login (NO REGISTER)             | Phone + OTP or Google Sign-In. Zero register/create-account link. Static text: "Don't have an account? Contact our office."                                                            |
| OTP Verify                      | 6-digit OTP. Resend after 60s. Rate-limited 3/5min server-side.                                                                                                                        |
| Google Sign-In                  | OAuth via google_sign_in + Supabase. Handled in mobile_login_screen.                                                                                                                   |
| Force Change Password           | Mandatory on first login (force_password_change=TRUE). Blocks all other routes.                                                                                                        |
| Dashboard                       | KPI cards: total applications, approved, active, completed, total borrowed, total paid, remaining balance. Quick action buttons: Apply for Loan, Pay Now, View Schedule.               |
| Lender Dashboard Provider       | Fetches lender-scoped KPIs.                                                                                                                                                            |
| Account Upgrade Submission      | Upload required documents (valid ID, selfie, proof of billing, etc.). Progress indicator. Resubmit on rejection.                                                                       |
| Account Upgrade Status          | Shows current Account Upgrade status with timeline. Rejection notes visible. Option to resubmit.                                                                                       |
| Lender Account Upgrade Provider | Account Upgrade submit + status fetch.                                                                                                                                                 |
| Apply for Loan                  | Amount slider (₱3,000–₱500,000). Payment frequency selector. Purpose field. Live schedule preview from API. Blocked if: Account Upgrade not verified, active loan exists, blacklisted. |
| Loan Application Status         | Timeline showing current stage: Applied → Account Upgrade Verified → CI Done → Approved / Rejected. Rejection reason shown.                                                            |
| Loan Details                    | Loan number, amount, total payable, interest, installment, frequency, term, due date, outstanding balance, disbursement info.                                                          |
| Payment Schedule                | Period-by-period table. Due date, amount due, amount paid, status per row. Download schedule button.                                                                                   |
| Lender Loan Provider            | Apply, cancel pending, fetch list and details.                                                                                                                                         |
| Pay via GCash (Xendit)          | Generates Xendit payment link for current installment. Redirects to GCash. Webhook auto-records payment. Shows pending → confirmed state.                                              |
| Payment History                 | List of all payments made. Date, amount, method, status, reference#.                                                                                                                   |
| Payment Receipt                 | PDF viewer of auto-generated receipt. Download + share buttons.                                                                                                                        |
| Lender Payment Provider         | Xendit link generation + payment history + receipt download.                                                                                                                           |
| Collection History              | List of rider collection visits. Date, rider name, amount collected, status.                                                                                                           |
| Collection Details              | Details of one collection: rider name, collection date, amount, proof photo, status. "Track Rider" button.                                                                             |
| Track Rider (Map)               | Google Maps showing rider's real-time GPS location. Updates every 30s via location/get-rider Edge Function.                                                                            |
| Lender Collection Provider      | Collection history + rider location polling.                                                                                                                                           |
| Documents View                  | List of all uploaded documents (Account Upgrade + loan attachments). Type, upload date, status. Signed URL viewer.                                                                     |
| Upload Documents                | Document type picker, file picker (image/PDF), upload progress. Calls document upload endpoint.                                                                                        |
| Lender Documents Provider       | Document list + upload.                                                                                                                                                                |
| Lender Location Provider        | Receives and caches rider location for map display.                                                                                                                                    |
| Notifications (Lender)          | All push notifications: loan status, payment due, disbursement, collection. Mark read. Badge count on bottom nav.                                                                      |
| Lender Notification Provider    | Fetches, marks read. FCM foreground listener.                                                                                                                                          |
| Lender Profile                  | View: name, phone, GCash, employment, income. Upload profile photo.                                                                                                                    |
| Edit Profile                    | Edit all personal details. Save calls users/update-profile.                                                                                                                            |
| Lender Profile Provider         | Fetch + update lender profile.                                                                                                                                                         |

ito naman ung sa dapat ui design ng frontend dapat may kabilang dito use lucide
icons

Micro Interactions

- Hover effects
- Click animations
- Press effects
- Ripple animations
- Focus states
- Active states
- Selected states
- Disabled states
- Success feedback
- Error feedback
- Loading feedback Navigation Experience

- Smooth page transitions
- Animated route transitions
- Animated sidebar expansion/collapse
- Animated bottom navigation
- Animated dialogs
- Animated bottom sheets
- Animated menus
- Breadcrumb transitions Interactive Components

- Expandable Cards
- Collapsible Panels
- Interactive Charts
- Sortable Tables
- Filterable Data Grid
- Search Suggestions
- Live Search
- Multi-select Components
- Drag-and-drop Upload
- Date Range Picker
- Calendar Interactions
- Interactive Maps
- QR Scanner Interface
- Camera Preview
- Signature Pad Dashboard Experience Dashboards should feel alive with:

- Animated KPI Counters
- Live Statistics
- Real-time Data Updates
- Interactive Charts
- Expandable Analytics Cards
- Timeline Animations
- Notification Animations
- Activity Feed Updates Form Experience Forms must provide:

- Floating Labels
- Real-time Validation
- Inline Error Messages
- Success Indicators
- Password Visibility Toggle
- Auto Formatting
- Auto Focus
- Keyboard Navigation
- Smooth Input Animations
- Progress Indicators
- Confirmation Dialogs Table Experience Enterprise tables should support:

- Sticky Headers
- Sticky Columns
- Resizable Columns
- Sort Animations
- Filter Animations
- Search Highlighting
- Pagination Controls
- Row Hover Effects
- Expandable Rows
- Context Menus
- Bulk Selection
- Quick Actions Loading Experience Provide professional loading states using:

- Skeleton Loaders
- Shimmer Effects
- Circular Progress Indicators
- Linear Progress Bars
- Lazy Loading
- Infinite Scrolling
- Pull-to-Refresh (Mobile) Notification Experience Support:

- Toast Messages
- Snackbars
- Alert Dialogs
- Confirmation Dialogs
- Success Popups
- Error Popups
- Warning Dialogs
- In-app Notifications
- Notification Center Animation Guidelines Use smooth and professional
  animations. Include:

- Fade
- Scale
- Slide
- Hero Animation
- Shared Element Transition
- Expand/Collapse
- Page Transition
- Card Animation
- FAB Animation
- Dialog Transition
- List Item Animation
- Stagger Animation Animations should enhance usability and performance without
  being excessive. Responsive Interaction The UI must adapt interactions based
  on the platform: Desktop

- Hover Effects
- Right-click Context Menu
- Keyboard Shortcuts
- Mouse Wheel Support
- Drag-and-drop
- Multi-window Friendly Mobile

- Swipe Gestures
- Pull-to-Refresh
- Long Press Actions
- Haptic Feedback
- Bottom Sheet Interactions
- Native Touch Experience Accessibility Support:

- Keyboard Navigation
- Focus Indicators
- Screen Reader Compatibility
- High Contrast Mode
- Adjustable Text Scaling
- Accessible Touch Targets
- Semantic Labels

The company offers loan amounts starting from a minimum of ₱3,000 up to a
maximum of ₱500,000 with an interest rate of 20%, depending on the approved loan
amount and repayment terms. Borrowers are provided with different payment
schedules such as daily, weekly, and monthly installments based on their
financial capacity. For instance, a ₱5,000 loan is payable at ₱6,000 within 40
days, while a ₱10,000 loan is payable at ₱12,000 within 60 days. Larger loan
amounts, such as ₱50,000 and ₱100,000, are also offered with corresponding
repayment deadlines and installment arrangements. The due date for monthly
payments is scheduled at the end of every month. In cases where borrowers are
delayed for only a few days or weeks, the company does not impose any penalty.
However, if the payment delay reaches one month, an additional 20% penalty is
charged based on the total payable amount. For example, a ₱5,000 loan with a
total payable amount of ₱6,000 will incur an additional ₱1,200 penalty after one
month of delay, resulting in a total balance of ₱7,200. Similarly, a ₱10,000
loan with a total payable amount of ₱12,000 will incur a ₱2,400 penalty,
increasing the total balance to ₱14,400. Furthermore, the company requires
borrowers to provide a co-maker during the loan application process; however,
the co-maker is not subjected to a Credit Investigation (CI).

1050 weekly 10,000 with 20% interest = 12,000php deadline on 60days terms 200php
daily, 1,400php weekly, and 6,000 monthly 50,000php with 20% interest =
60,000php deadline on 80days terms 750php daily, 5,250php weekly, and 20,000php
monthly 100,000 with 20% interest= 120,000 deadline on 120days terms 1,000php
daily, 7,000php weekly, and 30,000 monthly etc..

dapat makakapili ng anong term niya gustong bayaran ung inutang ni lender at
makikita ni head manager and employee un mga details ng inutang ni lender pati
mga inutang niya

all sensitive operations business rules and business logic must in backend no
hardcoded in this system

ito naman ung anon public
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxjZWx6cnZwcXdsYmVjY3J3cGtwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQwMjgyMTAsImV4cCI6MjA5OTYwNDIxMH0.kSBD9jB8CFy1Oo5nTwtIslp-112dEP6bo1XszOuiPUU

ito naman ung api url https://lcelzrvpqwlbeccrwpkp.supabase.co/rest/v1/

dapat connectado sila backend and front end

THAT IS SECURITY OF THE SYSTEM

1. Authentication Security

Applicable Roles:

✅ Head Manager (Admin) ✅ Employee (Manager) ✅ Rider ✅ Lender (Borrower)
Security Controls

✅ Email & Password Authentication

✅ Google Sign-In (OAuth 2.0)

✅ OpenID Connect (OIDC)

✅ PKCE (Proof Key for Code Exchange)

✅ OTP Verification (Email)

✅ Email Verification

✅ JWT Authentication

✅ JWT Validation

✅ Refresh Token Rotation

✅ Session Expiration

✅ Multi-device Session Management

✅ Remember Me (Secure)

✅ Secure Logout

✅ Password Reset with Time-Limited Token

✅ Password Complexity Rules

✅ Password History

✅ Password Expiration (Optional)

✅ Account Lockout after Failed Logins

✅ Login Rate Limiting

✅ CAPTCHA after Multiple Failed Logins

✅ Forced Re-authentication for Sensitive Actions

2. Authorization (Role-Based Access Control) System Roles

✅ Head Manager (Admin)

✅ Employee (Manager)

✅ Rider

✅ Lender (Borrower)

Security Controls

✅ Role-Based Access Control (RBAC)

✅ Least Privilege Access

✅ Role Validation

✅ Permission Validation

✅ Route/Page Authorization

✅ API Authorization

✅ Database Authorization (Row Level Security)

✅ JWT Role Verification

✅ Resource Ownership Validation

✅ Server-Side Permission Enforcement

✅ Unauthorized Access Prevention

✅ Privilege Escalation Prevention

✅ Access Denied Handling

3. Database Security (PostgreSQL)

✅ UUID Primary Keys

✅ Foreign Keys

✅ Constraints

✅ Check Constraints

✅ NOT NULL Constraints

✅ Unique Constraints

✅ Database Indexes

✅ Views

✅ Stored Procedures

✅ Database Triggers

✅ Soft Delete

✅ Transactions

✅ Optimistic Locking

✅ Row Level Security (RLS)

✅ Least Privilege Database Roles

✅ Backup Strategy

✅ Database Encryption at Rest

4. Supabase Security

✅ Row Level Security (RLS)

✅ Policies for Every Table

✅ JWT Validation

✅ Service Role Key Only in Edge Functions

✅ Anonymous Key Only in Client

✅ Secure Storage Buckets

✅ Storage Policies

✅ Signed URLs

✅ Edge Function Authorization

✅ Secrets in Environment Variables

✅ Secure API Integration

5. API Security

✅ RESTful API Security

✅ HTTPS Only

✅ TLS Encryption

✅ OAuth 2.0 Authentication

✅ OpenID Connect (OIDC)

✅ PKCE

✅ JWT Authentication

✅ JWT Validation

✅ API Authentication Middleware

✅ API Authorization

✅ API Gateway Protection

✅ Backend Service Authentication

✅ Secure Third-Party API Integration

✅ API Rate Limiting

✅ Request Validation

✅ Response Validation

✅ Request Integrity Validation

✅ Response Integrity Validation

✅ Input Sanitization

✅ CORS Restrictions

✅ Content Security Policy (CSP)

✅ Security Headers

✅ API Logging

✅ API Monitoring

✅ API Observability

✅ API Versioning

✅ API Timeout

✅ Secure Data Exchange

✅ Idempotency Keys for Payments

6. Input Validation

Prevent:

✅ SQL Injection

✅ Cross-Site Scripting (XSS)

✅ HTML Injection

✅ Script Injection

✅ Command Injection

✅ Invalid Numbers

✅ Invalid Dates

✅ Invalid Loan Amounts

✅ Invalid Interest

✅ Invalid IDs

✅ Duplicate Requests

✅ Document Authentication Validation

7. File Upload Security Borrower Documents

✅ Government ID

✅ Proof of Billing

✅ Selfie

✅ Proof of Income

Security Controls

✅ Allowed File Types

✅ MIME Type Validation

✅ Maximum File Size

✅ Virus Scanning (Optional)

✅ Image Validation

✅ Metadata Removal

✅ Random File Names

✅ Private Storage

✅ Signed URLs

8. Payment Security

✅ HTTPS Payment Communication

✅ Webhook Signature Verification

✅ Secure Callback Validation

✅ Payment Status Verification

✅ Payment Audit Trail

✅ Duplicate Payment Prevention

✅ Amount Verification

✅ Transaction Verification

✅ Idempotency Keys

9. Loan Approval Security

✅ Account Upgrade Verification

✅ e-Account Upgrade Verification (Optional)

✅ Borrower Identity Verification

✅ Borrower Consent Validation

✅ Credit Score Validation (If Implemented)

✅ Duplicate Loan Check

✅ Existing Active Loan Check

✅ Overdue Check

✅ Anti cyber attack

✅ Maximum Loan Limit

✅ Interest Validation

✅ Loan Policy Validation

10. Business Rules Security

Prevent:

✅ Negative Payments

✅ Overpayment

✅ Loan Before Approval

✅ Double Approval

✅ Double Rejection

✅ Editing Paid Loans

✅ Editing Closed Loans

✅ Deleting Payments

✅ Editing Audit Logs

✅ Unauthorized Loan Processing

✅ Duplicate Borrower Records

✅ Invalid Borrower Status

11. Audit Logging

Log:

✅ Login

✅ Logout

✅ Loan Creation

✅ Loan Approval

✅ Loan Rejection

✅ Payment

✅ User Creation

✅ Password Change

✅ Settings Change

✅ Interest Change

✅ Rider Assignment

✅ Report Export

✅ Profile Update

✅ API Access

✅ Authentication Events

Include:

✅ User ID

✅ User Role

✅ IP Address

✅ Browser

✅ Device

✅ Timestamp

✅ Action

✅ Old Value

✅ New Value

12. Fraud Detection

✅ Multiple Login Attempts

✅ Device Fingerprinting

✅ Impossible Travel Detection

✅ GPS Validation for Riders

✅ GPS Spoof Detection

✅ Duplicate Accounts

✅ Identity Verification Checks

✅ Fake Documents Detection (Manual Review or AI-Assisted)

✅ Document Authenticity Verification

✅ Rapid Loan Applications

✅ Suspicious Payment Patterns

13. Notification Security

✅ Secure Push Notifications

✅ Secure Notification Authentication

✅ No Sensitive Data in Notifications

✅ Notification Preferences

✅ Expiring Notification Links

14. Logging & Monitoring

✅ Error Logs

✅ Security Logs

✅ API Logs

✅ Database Logs

✅ Failed Login Logs

✅ Payment Logs

✅ Edge Function Logs

✅ Performance Monitoring

15. Encryption

✅ HTTPS/TLS

✅ Password Hashing (Argon2/bcrypt)

✅ JWT Signing

✅ AES-256 Encryption

✅ Encryption at Rest

✅ Encryption in Transit

✅ Secure Secret Management

16. Backup & Recovery

✅ Automatic Database Backups

✅ Point-in-Time Recovery

✅ Disaster Recovery Plan

✅ Backup Verification

✅ Restore Testing

17. Mobile Security

✅ Secure Token Storage

✅ Secure API Communication

✅ SSL Certificate Validation

✅ Prevent Token Exposure

✅ App Integrity Checks

✅ Disable Debug Features in Production

✅ Screen Security for Sensitive Pages (Optional)

✅ Session Timeout

18. Web Security

✅ Content Security Policy (CSP)

✅ X-Frame-Options

✅ X-Content-Type-Options

✅ Referrer Policy

✅ Secure Cookies (If Used)

✅ SameSite Cookies

✅ CSRF Protection (If Using Cookie-Based Authentication)

19. Administrative Security

✅ Role-Based Access Control

✅ Permission Validation

✅ Activity Monitoring

✅ Forced Re-authentication for Sensitive Actions

✅ Read-only Audit Logs

✅ Two-Person Approval for Critical Settings (Optional)

20. Compliance & Privacy

✅ Data Privacy Consent

✅ Privacy Policy

✅ Terms & Conditions

✅ Data Retention Policy

✅ Account Deactivation

✅ Secure Data Deletion

✅ Consent Logging

✅ Borrower Consent Management

21. Security Headers

✅ Strict-Transport-Security (HSTS)

✅ Content-Security-Policy (CSP)

✅ X-Frame-Options

✅ X-Content-Type-Options

✅ Referrer-Policy

✅ Permissions-Policy

✅ Cross-Origin-Resource-Policy

22. API & System Integration Security

✅ Secure API Integration

✅ RESTful API Security

✅ API Gateway Protection

✅ Secure Data Exchange

✅ OAuth 2.0 Authentication

✅ OpenID Connect (OIDC)

✅ PKCE (Proof Key for Code Exchange)

✅ JWT Authentication

✅ API Token Validation

✅ Backend Service Authentication

✅ API Versioning

✅ API Monitoring

✅ API Observability

✅ Request Integrity Validation

✅ Response Integrity Validation

✅ Inter-Service Authentication

✅ Secure Third-Party API Integration

Ito ay isang enterprise-grade security checklist na akma sa iyong Flutter Web +
Flutter Mobile + Supabase + PostgreSQL Lending Management System na may apat na
roles: Head Manager (Admin), Employee (Manager), Rider, at Lender (Borrower).
Ito rin ay nakaayon sa mga security concepts na nabanggit sa thesis document
(OAuth 2.0, OIDC, PKCE, JWT, AES-256, KYC, secure API integration, API gateway,
secure data exchange, at RBAC) habang iniiwasan ang mga duplicate.

kun may security sa backend pano naman sa design ng front base dyan

Magandang tanong. Ang security na nilista mo ay backend at system security. Sa
frontend (Flutter Web at Flutter Mobile), may sarili ring security at secure
UI/UX practices. Hindi nito pinapalitan ang backend security, kundi dinadagdagan
ito.

Narito ang Frontend Security na maaari mong idagdag.

23. Frontend Security (Flutter Web & Flutter Mobile) UI Security

✅ Hide Sensitive Information

✅ Mask Password Fields

✅ Mask OTP Input

✅ Show Password Toggle

✅ Disable Password Auto-Complete (Sensitive Forms)

✅ Disable Copy/Paste for Password Fields (Optional)

✅ Auto-clear Sensitive Fields After Logout

Form Security

✅ Client-side Input Validation

✅ Required Field Validation

✅ Email Format Validation

✅ Phone Number Validation

✅ Loan Amount Validation

✅ File Type Validation Before Upload

✅ File Size Validation Before Upload

✅ Prevent Multiple Form Submission

✅ Debounce Search Inputs

Navigation Security

✅ Protected Routes

✅ Authentication Guard

✅ Redirect Unauthorized Users

✅ Redirect Expired Sessions to Login

✅ Prevent Direct Access to Restricted Screens

✅ Role-based Navigation

Session UI Security

✅ Auto Logout on Session Expiration

✅ Lock Sensitive Pages After Inactivity

✅ Session Expired Warning Dialog

✅ Prevent Multiple Login Prompts

Screen Protection

✅ Hide Sensitive Information Until Loaded

✅ Blur Sensitive Data While Loading

✅ Hide Loan Information Until Authentication Completes

✅ Prevent Viewing Restricted Widgets

Secure Local Storage

✅ Store Only Access Tokens Securely

✅ Never Store Passwords

✅ Clear Cached User Data on Logout

✅ Clear Temporary Files

File Upload UI Security

✅ Preview Uploaded Documents

✅ Validate Image Before Upload

✅ Prevent Multiple Uploads

✅ Display Upload Progress

✅ Reject Unsupported Files

Error Handling

✅ Generic Error Messages

✅ Hide Stack Traces

✅ Hide Internal Server Errors

✅ Friendly Validation Messages

API Communication

✅ Never Expose API Secrets

✅ Never Expose Service Role Key

✅ Never Hardcode Tokens

✅ Secure API Calls

✅ Retry Failed Requests Securely

State Management Security

✅ Clear User State After Logout

✅ Dispose Sensitive Controllers

✅ Prevent Data Leakage Between Users

Web Browser Security

✅ Disable Developer Features in Production Build

✅ Prevent Sensitive Data in URL

✅ Avoid Local Storage for Sensitive Data

✅ Prevent Browser Cache of Sensitive Pages

Mobile Security

❌ Prevent Screenshots (Sensitive Pages) — disabled to allow screenshots

✅ Secure Clipboard Usage

✅ Hide Sensitive Data in App Switcher

✅ Detect Root/Jailbreak (Optional)

User Experience Security

✅ Confirm Before Critical Actions

Delete Approve Loan Reject Loan Change Interest Reset Password

✅ Double Confirmation for High-Risk Actions

Privacy

✅ Mask Personal Information

Example:

Juan Dela Cruz ↓

Juan D**** C**** 09123456789 ↓

0912****789 GCash Number

09********8 24. Frontend Design Security (UX)

Ito naman ang design side ng security.

Authentication Pages

✅ Password Strength Indicator

✅ Password Requirements

✅ Forgot Password Link

✅ Login Attempt Warning

✅ Session Expired Notice

✅ Email Verification Reminder

Dashboard

✅ Show Only Authorized Modules

Admin

Users Reports Settings

Employee

Loans Borrowers

Rider

Collections

Borrower

My Loan Payments Loan Pages

✅ Disable Approve Button if Unauthorized

✅ Disable Delete Button

✅ Disable Edit Paid Loan

✅ Disable Closed Loan Actions

Payment Pages

✅ Disable Pay Button if Already Paid

✅ Prevent Duplicate Payment Click

✅ Loading Indicator During Payment

Forms

✅ Disable Submit While Loading

✅ Prevent Double Click

✅ Show Validation Errors

Tables

✅ Hide Restricted Columns

Example

Admin

Interest Profit System Logs

Borrower

Loan Balance Payment Schedule Reports

✅ Disable Export for Unauthorized Roles

✅ Watermark Sensitive Reports (Optional)

Profile

✅ Require Password Before Changing Email

✅ Require OTP Before Password Change

jireta_lms/ ├── .env # Flutter client env (git-ignored) ├── .env.example # Safe
template ├── .gitignore ├── analysis_options.yaml ├── pubspec.yaml ├──
pubspec.lock ├── README.md │ ├── android/ # Android native config │ ├── app/ │ │
├── google-services.json # Firebase (FCM) — git-ignored │ │ └── src/main/ │ │
├── AndroidManifest.xml │ │ └── res/ │ │ └── values/ │ │ └── strings.xml #
Google Maps API key injection │ └── build.gradle │ ├── ios/ # iOS native config
│ ├── Runner/ │ │ ├── GoogleService-Info.plist # Firebase (FCM) — git-ignored │
│ ├── Info.plist │ │ └── AppDelegate.swift │ └── Podfile │ ├── web/ # Flutter
Web config │ ├── index.html # CSP headers + Maps script │ ├── manifest.json │
└── favicon.ico │ ├── assets/ │ ├── env/ │ │ └── .env # Copied from root .env at
build │ ├── fonts/ │ │ ├── Inter/ # Primary body typeface │ │ │ ├──
Inter-Regular.ttf │ │ │ ├── Inter-Medium.ttf │ │ │ ├── Inter-SemiBold.ttf │ │ │
└── Inter-Bold.ttf │ │ └── Playfair_Display/ # Display / brand headings │ │ ├──
PlayfairDisplay-Regular.ttf │ │ └── PlayfairDisplay-Bold.ttf │ ├── images/ │ │
├── jireta_logo.png │ │ ├── jireta_logo_white.png │ │ ├── jireta_logo_gold.png │
│ ├── splash_background.png │ │ └── empty_state.svg │ └── icons/ │ └──
app_icon.png │ ├── supabase/ # ─── BACKEND ─────────────────────── │ ├──
config.toml │ ├── .env # Backend secrets (git-ignored) │ │ │ ├── migrations/ #
39 sequential SQL migration files │ │ ├── 00001_initial_schema │ │ ├──
00002_rls_policies.sql │ │ ├── 00003_indexes_triggers_functions.sql │ │ ├──
00004_seed_data.sql │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │
│ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │
│ │ │ └── functions/ # 74 Edge Functions (flat, Deno TypeScript) │ │ │ │ # ──
Shared utilities (imported by Edge Functions) ───────────────── │ ├── _shared/ │
│ ├── cors.ts # CORS headers for all functions │ │ ├── auth.ts # JWT
validation + role extraction │ │ ├── rbac.ts # Permission enforcement helper │ │
├── db.ts # Supabase admin client (service role) │ │ ├── validators.ts # Input
sanitization + schema validators │ │ ├── audit.ts # Audit log writer helper │ │
├── notifications.ts # FCM push notification helper │ │ ├── sms.ts # Semaphore
SMS helper │ │ ├── xendit.ts # Xendit API wrapper helper │ │ ├── rate_limiter.ts
# Rate limiting helper │ │ ├── errors.ts # Standard error response builder │ │
└── types.ts # Shared TypeScript interfaces │ │ │ │ # ── Authentication (8
functions) ────────────────────────────────── │ ├── auth-login/index.ts │ │ #
POST: Email+password login for HM/Employee (web). │ │ # Enforces:
account_status, failed_attempts, lockout, force_password_change. │ │ # Returns:
JWT access token, role, force_change_password flag. │ │ # Writes: auth_logs
event. │ │ │ ├── auth-send-otp/index.ts │ │ # POST: Send OTP to phone number for
Rider/Lender (mobile). │ │ # Enforces: OTP rate limit (3 per 5 min), active
account check. │ │ # Uses: Semaphore SMS for OTP delivery. │ │ # Writes:
auth_logs(otp_sent). │ │ │ ├── auth-verify-otp/index.ts │ │ # POST: Verify OTP
submitted by Rider/Lender. │ │ # Enforces: OTP expiry, attempt limit, account
status. │ │ # Returns: JWT access token, role, force_change_password flag. │ │ #
Writes: auth_logs event. │ │ │ ├── auth-force-change-password/index.ts │ │ #
POST: Replace default password (12345678). │ │ # Enforces: complexity rules,
password history (last 5). │ │ # Sets: force_password_change = FALSE. │ │ #
Writes: audit_log(password_changed). │ │ │ ├── auth-forgot-password/index.ts │ │
# POST: Send password reset link to email (HM/Employee). │ │ # Enforces:
time-limited token (1 hour). │ │ # Writes: auth_logs(password_reset_requested).
│ │ │ ├── auth-reset-password/index.ts │ │ # POST: Token-based password reset
from email link. │ │ # Enforces: token validity, complexity rules. │ │ # Writes:
audit_log(password_changed). │ │ │ ├── auth-logout/index.ts │ │ # POST:
Invalidate session, clear FCM token. │ │ # Writes: auth_logs(logout). │ │ │ ├──
auth-refresh-session/index.ts │ │ # POST: Rotate refresh token, return new
access token. │ │ # Enforces: account_status check on refresh. │ │ │ │ # ──
Users (8 functions) ─────────────────────────────────────────── │ ├──
users-create-employee/index.ts │ │ # POST: HM only. Create Employee account. │ │
# Fields: first_name, middle_name, last_name, suffix, gender, │ │ #
civil_status, dob, email, phone, department, position, hired_at. │ │ # Sets:
default password=12345678 (hashed), force_password_change=TRUE. │ │ # Writes:
users, employee_profiles, audit_log, notification(to HM). │ │ │ ├──
users-create-rider/index.ts │ │ # POST: HM or Employee. Create Rider account. │
│ # Fields: first_name, last_name, phone, vehicle_type, plate_number, │ │ #
drivers_license_number, drivers_license_expiry, vehicle_brand. │ │ # Sets:
default password=12345678 (hashed), force_password_change=TRUE. │ │ # Writes:
users, rider_profiles, audit_log. │ │ │ ├── users-create-lender/index.ts │ │ #
POST: HM or Employee. Create Lender (walk-in) account. │ │ # Fields: first_name,
last_name, phone, gender, civil_status, dob, │ │ # employment_type,
employer_name, monthly_income, gcash_number. │ │ # Sets: default
password=12345678 (hashed), force_password_change=TRUE. │ │ # Writes: users,
lender_profiles, audit_log. │ │ │ ├── users-update-profile/index.ts │ │ # PATCH:
Authenticated user updates own profile fields. │ │ # Enforces: cannot update
role, cannot update another user's profile. │ │ # Writes: users, role-specific
profile table, audit_log. │ │ │ ├── users-get-profile/index.ts │ │ # GET: Fetch
own or target user profile (RBAC-filtered). │ │ # HM: any user. Employee:
lenders + riders. Rider/Lender: self only. │ │ │ ├── users-get-list/index.ts │ │
# GET: Paginated user list with search, filter, sort. │ │ # RBAC: HM=all roles;
Employee=lenders+riders; Rider/Lender=forbidden. │ │ # Supports: search, status
filter, role filter, date range, pagination. │ │ │ ├──
users-suspend-activate/index.ts │ │ # PATCH: HM only. Toggle account_status
between active/suspended. │ │ # Enforces: cannot suspend HM account. │ │ #
Writes: audit_log, notification(to affected user). │ │ │ ├──
users-archive/index.ts │ │ # PATCH: HM only. Soft-delete (archive) a user
account. │ │ # Enforces: cannot archive user with active loans. │ │ # Writes:
audit_log. │ │ │ │ # ── Account Upgrade (KYC module, 2 deployable functions)
───────────── │ ├── kyc-submit/index.ts │ │ # POST: Lender submits Account
Upgrade documents. │ │ # Validates: file type (JPEG/PNG/PDF), MIME, max size
5MB. │ │ # Stores: signed private URLs in Supabase Storage
(account-upgrade-documents bucket). │ │ # Sets:
lender_profiles.account_upgrade_status = 'submitted'. │ │ # Writes:
account_upgrade_documents, audit_log. │ │ # Triggers: notification to HM + all
Employees. │ │ │ ├── kyc-view/index.ts (routes by ?fn=) │ │ # kyc-verify →
?fn=verify │ │ # PATCH: HM or Employee. Verify or Reject an Account Upgrade
document. │ │ # Body: { account_upgrade_doc_id, action: 'verified'|'rejected',
rejection_notes? }. │ │ # Enforces: all docs verified before status flips to
'verified'. │ │ # Writes: account_upgrade_documents.status,
lender_profiles.account_upgrade_status, audit_log. │ │ # Triggers: notification
to Lender. │ │ # kyc-get-list → ?fn=get-list │ │ # GET: Paginated Account
Upgrade list. RBAC: HM/Employee only. │ │ # Filters: status, date_range,
lender_name. │ │ # kyc-get-status → ?fn=get-status │ │ # GET: Lender fetches own
Account Upgrade status + document list with signed URLs. │ │ # kyc-get-details →
?fn=get-details │ │ # GET: HM/Employee fetch a lender's Account Upgrade
submission details with signed URLs. │ │ │ │ # ── Loans (9 functions)
─────────────────────────────────────────── │ ├── loans-apply/index.ts │ │ #
POST: Lender applies for a loan. │ │ # Enforces:
account_upgrade_status=verified, no active loan, not blacklisted, │ │ # amount
₱3,000–₱500,000, valid frequency (daily/weekly/monthly). │ │ # Computes:
interest_rate=20%, total_payable=principal_1.20, term_days, │ │ # installment
schedule — ALL server-side, no Dart math. │ │ # Generates: loan_number
(LN-YYYY-XXXXXX), loan_schedules rows. │ │ # Writes: loans, loan_schedules,
audit_log. │ │ # Triggers: notification to HM + Employees. │ │ │ ├──
loans-approve/index.ts │ │ # PATCH: HM or Employee. Approve a loan application.
│ │ # Enforces: status must be 'ci_completed', CI report submitted, │ │ # lender
Account Upgrade verified, not blacklisted. │ │ # Sets: loans.status =
'approved'. │ │ # Writes: audit_log. Triggers: notification to Lender. │ │ │ ├──
loans-reject/index.ts │ │ # PATCH: HM or Employee. Reject a loan application. │
│ # Body: { loan_id, rejection_reason }. │ │ # Enforces: loan must not be
active/completed. │ │ # Sets: loans.status = 'rejected', rejected_by,
rejection_reason. │ │ # Writes: audit_log. Triggers: notification to Lender. │ │
│ ├── loans-cancel/index.ts │ │ # PATCH: Lender cancels own pending loan, or
HM/Employee cancels any. │ │ # Enforces: only 'pending' or 'under_review' status
can be cancelled. │ │ # Writes: audit_log. Triggers: notification. │ │ │ ├──
loans-get-list/index.ts │ │ # GET: Paginated loan list. │ │ # RBAC: HM=all;
Employee=processed by self; Lender=own loans. │ │ # Filters: status, date_range,
amount_range, lender_name. │ │ │ ├── loans-get-details/index.ts │ │ # GET: Full
loan record with schedule, payments, CI, collections. │ │ # RBAC: Lender=own
loans only; HM/Employee=any loan. │ │ │ ├── loans-get-schedule-preview/index.ts
│ │ # POST: Compute installment schedule without persisting. │ │ # Body: {
principal, frequency: daily|weekly|monthly }. │ │ # Returns: total_payable,
interest, installment_amount, term_days, │ │ # due_dates[], amounts[] — pure
server computation. │ │ # RBAC: HM, Employee, authenticated Lender. │ │ │ ├──
loans-apply-penalty/index.ts │ │ # POST: HM or Employee. Apply overdue penalty.
│ │ # Enforces: loan.status='overdue', penalty not already applied. │ │ #
Computes: penalty = total_payable * 0.20. │ │ # Updates:
loans.outstanding_balance, loans.penalty_applied=TRUE. │ │ # Writes:
penalty_logs, audit_log. Triggers: notification to Lender. │ │ │ ├──
loans-request-ci/index.ts │ │ # PATCH: HM or Employee. Move loan to
'ci_required' status. │ │ # Enforces: loan.status='under_review'. │ │ # Writes:
audit_log. Triggers: notification to Lender. │ │ │ │ # ── Credit Investigation
(6 functions) ──────────────────────────── │ ├── ci-assign/index.ts │ │ # POST:
HM or Employee assigns a Rider for credit investigation. │ │ # Body: { loan_id,
rider_id, investigation_notes, deadline }. │ │ # Enforces:
rider.is_available=true, loan.status in valid CI states. │ │ # Sets:
loans.status='ci_assigned', assigned_by=authenticated_user. │ │ # Writes:
credit_investigations, audit_log. │ │ # Triggers: FCM push to Rider,
confirmation to assigning user. │ │ │ ├── ci-accept/index.ts │ │ # PATCH: Rider
accepts a CI assignment. │ │ # Sets: credit_investigations.status='accepted',
response_at. │ │ # Writes: audit_log. Triggers: notification to assigning
HM/Employee. │ │ │ ├── ci-decline/index.ts │ │ # PATCH: Rider declines a CI
assignment. │ │ # Sets: credit_investigations.status='declined'. │ │ # Resets:
loans.status back to 'ci_required'. │ │ # Writes: audit_log. Triggers:
notification to assigning HM/Employee. │ │ │ ├── ci-upload-documents/index.ts │
│ # POST: Rider uploads CI evidence photos. │ │ # Validates: JPEG/PNG, max 10MB,
GPS coordinates required. │ │ # Detects: GPS spoof (compares upload location vs
borrower address). │ │ # Stores: ci-documents Supabase Storage bucket. │ │ #
Writes: ci_documents (with lat/long), audit_log. │ │ │ ├──
ci-submit-report/index.ts │ │ # POST: Rider submits final CI investigation
report. │ │ # Enforces: at least 1 ci_document uploaded. │ │ # Sets:
credit_investigations.status='completed', loans.status='ci_completed'. │ │ #
Writes: credit_investigations.report_summary, audit_log. │ │ # Triggers:
notification to HM + Employees. │ │ │ ├── ci-get-list/index.ts │ │ # GET:
Paginated CI list. │ │ # RBAC: HM/Employee=all; Rider=own assigned only. │ │ #
Filters: status, rider_id, date_range. │ │ │ │ # ── Collections (6 functions)
───────────────────────────────────── │ ├── collections-assign/index.ts │ │ #
POST: HM or Employee assigns Rider for cash collection. │ │ # Body: {
loan_schedule_id, rider_id, collection_schedule, notes }. │ │ # Enforces:
loan.status='active', rider available. │ │ # Sets:
assigned_by=authenticated_user. │ │ # Writes: collection_assignments, audit_log.
│ │ # Triggers: FCM push to Rider. │ │ │ ├── collections-accept/index.ts │ │ #
PATCH: Rider accepts collection assignment. │ │ # Sets: status='accepted',
response_at. │ │ # Writes: audit_log. Triggers: notification to assigning user.
│ │ │ ├── collections-decline/index.ts │ │ # PATCH: Rider declines collection
assignment. │ │ # Sets: status='declined'. │ │ # Writes: audit_log. Triggers:
notification to assigning user. │ │ │ ├── collections-record/index.ts │ │ #
POST: Rider records a cash payment collection. │ │ # Body: { assignment_id,
amount_collected, notes }. │ │ # Enforces: no negative amounts, not already
completed. │ │ # Updates: payments, loan_schedules, loans.outstanding_balance. │
│ # Generates: idempotency_key duplicate check. │ │ # Writes: payments,
audit_log. │ │ # Triggers: notification to Lender, assigning HM/Employee. │ │ │
├── collections-upload-proof/index.ts │ │ # POST: Rider uploads payment proof,
signature, scene photo. │ │ # Validates: JPEG/PNG, GPS required. │ │ # Stores:
collection-proofs Supabase Storage bucket. │ │ # Writes:
collection_assignments.proof_photo, borrower_signature, │ │ # collection_photo.
Sets: status='completed'. │ │ │ ├── collections-get-list/index.ts │ │ # GET:
Paginated collection list. │ │ # RBAC: HM/Employee=all; Rider=own; Lender=own
loans' collections. │ │ # Filters: status, rider_id, date_range. │ │ │ │ # ──
Payments (6 functions) ──────────────────────────────────────── │ ├──
payments-record-office/index.ts │ │ # POST: Employee or HM records walk-in
office payment. │ │ # Body: { loan_id, loan_schedule_id, amount, notes,
idempotency_key }. │ │ # Enforces: idempotency_key unique check, no overpayment,
│ │ # Account Upgrade identity verified before recording. │ │ # Updates:
loan_schedules, loans.outstanding_balance. │ │ # Writes: payments, audit_log.
Triggers: notification to Lender. │ │ │ ├──
payments-generate-xendit-link/index.ts │ │ # POST: Lender requests GCash payment
link. │ │ # Body: { loan_id, loan_schedule_id }. │ │ # Enforces: installment not
already paid, loan active. │ │ # Calls: Xendit Create Invoice API (sandbox or
live per ENV). │ │ # Returns: xendit_invoice_url, xendit_payment_id. │ │ #
Writes: payments(status=pending), xendit_logs. │ │ │ ├──
payments-xendit-webhook/index.ts │ │ # POST: Xendit payment webhook receiver. │
│ # Verifies: webhook signature header (X-CALLBACK-TOKEN). │ │ # Updates:
payments.status='verified', loan_schedules, outstanding_balance. │ │ #
Generates: receipt PDF (stored in receipts bucket). │ │ # Writes: xendit_logs,
audit_log. Triggers: notification to Lender. │ │ │ ├── payments-reverse/index.ts
│ │ # PATCH: HM only. Reverse a verified payment. │ │ # Enforces: HM role only,
payment exists and is 'verified'. │ │ # Restores: loan_schedules,
outstanding_balance. │ │ # Writes: payment_reversals, audit_log. Triggers:
notification to Lender. │ │ │ ├── payments-get-receipt/index.ts │ │ # GET:
Generate or fetch signed receipt URL. │ │ # RBAC: Lender=own payments;
HM/Employee=any. │ │ # Returns: signed Supabase Storage URL (expires 1 hour). │
│ │ ├── payments-get-list/index.ts │ │ # GET: Paginated payment list. │ │ #
RBAC: HM=all; Employee=all; Lender=own. │ │ # Filters: method, status,
date_range. │ │ │ │ # ── Disbursements (4 functions)
─────────────────────────────────── │ ├── disbursements-gcash/index.ts │ │ #
POST: HM or Employee initiates GCash disbursement via Xendit. │ │ # Body: {
loan_id, gcash_number }. │ │ # Enforces: loan.status='approved', not already
disbursed. │ │ # Calls: Xendit Disbursement API. │ │ # Sets:
loans.status='active', disbursed_at, disbursement_method='gcash'. │ │ # Writes:
disbursements, xendit_logs, audit_log. │ │ # Triggers: notification to Lender. │
│ │ ├── disbursements-office-cash/index.ts │ │ # POST: HM or Employee records
manual office cash disbursement. │ │ # Enforces: Account Upgrade identity
verified (checks account_upgrade_documents), loan approved. │ │ # Sets:
loans.status='active', disbursement_method='office_cash'. │ │ # Writes:
disbursements, audit_log. Triggers: notification to Lender. │ │ │ ├──
disbursements-rider-delivery/index.ts │ │ # POST: HM or Employee assigns Rider
for cash delivery. │ │ # Body: { loan_id, rider_id, delivery_date, notes }. │ │
# Sets: assigned_by=authenticated_user. │ │ # Writes: disbursements, audit_log.
│ │ # Triggers: FCM push to Rider. │ │ │ ├──
disbursements-xendit-webhook/index.ts │ │ # POST: Xendit disbursement webhook
receiver. │ │ # Verifies: X-CALLBACK-TOKEN signature. │ │ # Updates:
disbursements.status, xendit_status, disbursed_at. │ │ # Writes: xendit_logs,
audit_log. │ │ │ │ # ── Blacklist (3 functions)
─────────────────────────────────────── │ ├── blacklist-add/index.ts │ │ # POST:
HM only. Add Lender to blacklist. │ │ # Body: { lender_id, reason }. │ │ #
Enforces: HM role only, not already blacklisted. │ │ # Sets:
lender_profiles.is_blacklisted=TRUE. │ │ # Writes: blacklist, audit_log.
Triggers: notification to Lender. │ │ │ ├── blacklist-remove/index.ts │ │ #
PATCH: HM only. Remove Lender from blacklist. │ │ # Sets:
lender_profiles.is_blacklisted=FALSE, blacklist.is_active=FALSE. │ │ # Writes:
audit_log. Triggers: notification to Lender. │ │ │ ├──
blacklist-get-list/index.ts │ │ # GET: Paginated blacklist. RBAC: HM only. │ │ │
│ # ── Location (2 functions) ──────────────────────────────────────── │ ├──
location-update-rider/index.ts │ │ # POST: Rider posts GPS coordinates during
active assignment. │ │ # Enforces: rate-limited (1 update per 30s), valid
lat/long range. │ │ # GPS spoof detection: rejects impossible coordinate jumps.
│ │ # Upserts: rider_locations (one row per rider). │ │ │ ├──
location-get-rider/index.ts │ │ # GET: Fetch rider's latest GPS coordinates. │ │
# RBAC: Lender=only if has active collection by that rider. │ │ #
HM/Employee=any active rider. │ │ │ │ # ── Notifications (3 functions)
─────────────────────────────────── │ ├── notifications-send/index.ts │ │ #
POST: HM or Employee sends push notification to a user. │ │ # Body: { user_id,
title, body, type, reference_id? }. │ │ # Calls: FCM send push via fcm_token. │
│ # Writes: notifications, audit_log. │ │ │ ├── notifications-get-list/index.ts
│ │ # GET: Fetch own notifications. All roles. │ │ # Filters: is_read, type.
Pagination. │ │ │ ├── notifications-mark-read/index.ts │ │ # PATCH: Mark one or
all notifications as read. All roles (own only). │ │ │ │ # ── Reports (3
functions) ───────────────────────────────────────── │ ├──
reports-generate/index.ts │ │ # POST: HM only. Generate a report from a
template. │ │ # Body: { template_key, parameters: { date_range, filters... } }.
│ │ # Queries: PostgreSQL views and aggregates. │ │ # Produces: PDF (via Deno
PDF lib) + XLSX stored in Supabase Storage. │ │ # Writes: reports,
audit_log(report_export). │ │ │ ├── reports-get-list/index.ts │ │ # GET: Report
template library. HM only. │ │ │ ├── reports-get-history/index.ts │ │ # GET:
Paginated generated report history with signed download URLs. HM only. │ │ │ │ #
── In-Office Applications (4 functions) ────────────────────────── │ ├──
in-office-create-draft/index.ts │ │ # POST: HM or Employee starts a walk-in
application draft. │ │ # Creates: in_office_applications (status=draft,
wizard_step=1). │ │ │ ├── in-office-save-step/index.ts │ │ # PATCH: Save any
wizard step data (1–5) to JSONB columns. │ │ # Body: { application_id, step:
1–5, data: {...} }. │ │ # Updates: in_office_applications.wizard_step,
stepN_data. │ │ │ ├── in-office-submit/index.ts │ │ # POST: Finalize and convert
wizard to a real loan application. │ │ # Enforces: all 5 steps complete,
signature captured. │ │ # Creates: lender (if new), addresses,
emergency_contacts, co_maker, │ │ # co_maker_documents, loan, loan_schedules. │
│ # Sets: in_office_applications.status='converted', loan_id. │ │ # Writes:
audit_log, notifications. │ │ │ ├── in-office-get-list/index.ts │ │ # GET: List
walk-in applications. │ │ # RBAC: HM=all. Employee=own created only.
Others=forbidden. │ │ │ │ # ── KPI Dashboards (4 functions)
────────────────────────────────── │ ├── kpi-head-manager/index.ts │ │ # GET:
All 19 HM KPI metrics in one call. │ │ # Returns: total_employees, total_riders,
total_lenders, │ │ # total_loan_applications, total_approved, total_rejected, │
│ # total_active, total_completed, total_overdue, │ │ # total_released_amount,
total_collected, total_outstanding, │ │ # total_interest_earned,
total_penalties, total_revenue, │ │ # total_collection_transactions,
total_ci_assignments, │ │ # total_report_exports, total_pending_account_upgrade.
│ │ # RBAC: head_manager only. │ │ │ ├── kpi-employee/index.ts │ │ # GET: 7
Employee-scoped KPI metrics (filtered to own actions). │ │ # RBAC: employee
only. │ │ │ ├── kpi-rider/index.ts │ │ # GET: 6 Rider-scoped KPI metrics. │ │ #
RBAC: rider only. │ │ │ ├── kpi-lender/index.ts │ │ # GET: 10 Lender-scoped KPI
metrics. │ │ # RBAC: lender only. │ │ │ │ # ── SMS (2 functions)
───────────────────────────────────────────── │ ├── sms-send-reminder/index.ts │
│ # POST: Cron-triggered. Send SMS payment reminders 2 days before due. │ │ #
Fetches: loan_schedules where due_date = today + 2. │ │ # Uses:
sms_templates(payment_reminder), Semaphore API. │ │ # Writes: sms_logs. │ │ │
├── sms-send-otp/index.ts │ │ # POST: Internal helper. Send OTP via Semaphore
SMS. │ │ # Called by: auth-send-otp. Not publicly accessible. │ │ │ │ # ── Audit
(1 function) ──────────────────────────────────────────── │ └──
audit-get-logs/index.ts │ # GET: Paginated audit log viewer. HM only. Read-only.
│ # Filters: action, performed_by, table_name, date_range. │ # Supports: JSON
diff view (old_values vs new_values). │ └── lib/ # ─── FRONTEND
────────────────────── ├── main.dart │ # Entry point: loads .env via
flutter_dotenv, initializes Supabase │ # client (anon key only), Firebase, DI
container, GoRouter. │ ├── app.dart │ # MaterialApp.router: GoRouter, theme,
locale, platform detection. │ ├── firebase_options.dart │ # Auto-generated by
FlutterFire CLI. FCM + Google Sign-In config. │ ├── core/ │ ├── config/ │ │ ├──
app_config.dart │ │ │ # Static constants: company name, min/max loan (display
only), │ │ │ # app version. NO business rule values here. │ │ │ │ │ ├──
env_config.dart │ │ │ # Reads all values from flutter_dotenv. Single source of
truth │ │ │ # for SUPABASE_URL, SUPABASE_ANON_KEY, EDGE_FUNCTIONS_URL, │ │ │ #
GOOGLE_MAPS_API_KEY, APP_ENV. Throws on missing required keys. │ │ │ │ │ └──
supabase_config.dart │ │ # Supabase.initialize(...) call. Only anon key and URL.
│ │ # NO service role key anywhere in Flutter code. │ │ │ ├── constants/ │ │ ├──
api_constants.dart # Edge function path segments │ │ ├── app_constants.dart #
Timeouts, pagination defaults │ │ ├── asset_constants.dart # Asset file paths │
│ ├── role_constants.dart # 'head_manager'|'employee'|'rider'|'lender' │ │ └──
route_constants.dart # Named route strings │ │ │ ├── di/ │ │ ├── injection.dart
│ │ │ # Riverpod ProviderContainer + GetIt service locator. │ │ │ # Registers:
DioClient, all Repository impls, all Services. │ │ │ # All non-auth providers
registered here. │ │ │ │ │ └── service_locator.dart │ │ # GetIt instance for
non-Riverpod services (e.g. LocationService). │ │ │ ├── errors/ │ │ ├──
app_exception.dart # Typed exception classes │ │ ├── failure.dart # Sealed
failure types │ │ └── error_handler.dart # Maps Dio errors to app failures │ │ │
├── extensions/ │ │ ├── context_extensions.dart # Theme, screen size, platform
helpers │ │ ├── date_extensions.dart # Format dates (Philippine locale) │ │ ├──
num_extensions.dart # Currency format ₱ with commas │ │ └──
string_extensions.dart # Mask PII (09123456789 → 0912_ _**789) │ │ │ ├──
network/ │ │ ├── api_client.dart │ │ │ # Abstract interface for all HTTP calls
to Edge Functions. │ │ │ │ │ ├── dio_client.dart │ │ │ # Dio instance configured
with: │ │ │ # - BaseOptions: baseUrl=EDGE_FUNCTIONS_URL, timeouts │ │ │ # -
Interceptors: auth, error, logging │ │ │ # - HTTPS only (rejects HTTP) │ │ │ │ │
├── api_endpoints.dart │ │ │ # All endpoint paths as static const strings. │ │ │
# e.g. static const kpiHeadManager = 'kpi-head-manager'; │ │ │ │ │ └──
interceptors/ │ │ ├── auth_interceptor.dart │ │ │ # Injects Authorization:
Bearer <token> header. │ │ │ # Handles 401: refreshes token via
auth-refresh-session, │ │ │ # retries once, then redirects to login. │ │ │ │ │
├── error_interceptor.dart │ │ │ # Maps server error codes to typed
AppException. │ │ │ # Strips stack traces from responses (generic messages to
UI). │ │ │ │ │ └── logging_interceptor.dart │ │ # Dev-only: logs
request/response (disabled in production build). │ │ │ ├── router/ │ │ ├──
app_router.dart │ │ │ # GoRouter configuration: all routes, redirects, error
page. │ │ │ # Redirect logic: checks auth state + role → routes to correct
portal. │ │ │ # Web: /hm/... | /employee/... paths. │ │ │ # Mobile: /rider/... |
/lender/... paths. │ │ │ │ │ ├── route_guards.dart │ │ │ # AuthGuard: redirect
unauthenticated to /login. │ │ │ # RoleGuard: redirect to role-correct dashboard
if wrong path. │ │ │ # ForcePasswordGuard: block all routes if
force_password_change=TRUE. │ │ │ │ │ └── routes.dart │ │ # All route name +
path constants. │ │ │ ├── security/ │ │ ├── secure_storage.dart │ │ │ #
flutter_secure_storage wrapper. │ │ │ # Stores: access_token, refresh_token. │ │
│ # Never stores: passwords, service role keys. │ │ │ # Clears: all on logout. │
│ │ │ │ └── token_manager.dart │ │ # Reads/writes tokens from secure storage. │
│ # Provides: getAccessToken(), setTokens(), clearAll(). │ │ │ ├── services/ │ │
├── fcm_service.dart │ │ │ # Firebase Messaging setup. │ │ │ # Foreground
handler: shows in-app notification. │ │ │ # Background handler: deep-links to
relevant screen. │ │ │ # Saves/updates FCM token via users-update-profile Edge
Function. │ │ │ │ │ ├── location_service.dart │ │ │ # Background GPS posting
every 30s (Rider only, active assignment). │ │ │ # Calls: location-update-rider
Edge Function. │ │ │ # Handles: permissions, battery optimization, background
mode. │ │ │ │ │ └── supabase_storage_service.dart │ │ # Supabase Storage: upload
file to bucket, get signed URL. │ │ # Validates: mime type, file size before
upload attempt. │ │ # Used by: Account Upgrade submit, CI documents, collection
proof. │ │ │ ├── theme/ │ │ ├── app_colors.dart │ │ │ # Deep Navy: #0D1B2A
(primary brand) │ │ │ # Gold: #C9A84C (accent / logo) │ │ │ # Green: #2E7D32
(Rider bottom nav accent) │ │ │ # Purple: #6A1B9A (Lender bottom nav accent) │ │
│ # Surface White: #FAFAFA │ │ │ # Error: #D32F2F │ │ │ │ │ ├──
app_decorations.dart # BoxDecoration presets │ │ ├── app_theme.dart # ThemeData
(light, system) │ │ └── app_typography.dart # Inter body + Playfair Display
headings │ │ │ └── utils/ │ ├── formatters.dart # Phone mask, currency, date
format │ ├── helpers.dart # UUID idempotency key generator │ ├── logger.dart #
Dev logging (disabled in prod build) │ └── validators.dart # Client-side field
validators (UI only) │ ├── data/ │ ├── datasources/ │ │ ├── local/ │ │ │ ├──
secure_local_datasource.dart # Token read/write via SecureStorage │ │ │ └──
cache_datasource.dart # In-memory LRU cache for signed URLs │ │ │ │ │ └──
remote/ │ │ ├── account_upgrade_remote_datasource.dart │ │ ├──
auth_remote_datasource.dart │ │ ├── audit_remote_datasource.dart │ │ ├──
blacklist_remote_datasource.dart │ │ ├── ci_remote_datasource.dart │ │ ├──
collection_remote_datasource.dart │ │ ├── disbursement_remote_datasource.dart │
│ ├── in_office_remote_datasource.dart │ │ ├── kpi_remote_datasource.dart │ │
├── loan_remote_datasource.dart │ │ ├── location_remote_datasource.dart │ │ ├──
notification_remote_datasource.dart │ │ ├── payment_remote_datasource.dart │ │
├── report_remote_datasource.dart │ │ ├── system_remote_datasource.dart │ │ └──
user_remote_datasource.dart │ │ │ ├── models/ │ │ # Each model: fromJson(),
toJson(), copyWith(), Equatable. │ │ # Mirrors database schema exactly. NO
business rule fields. │ │ ├── account_upgrade_document_model.dart │ │ ├──
address_model.dart │ │ ├── audit_log_model.dart │ │ ├── auth_log_model.dart │ │
├── blacklist_model.dart │ │ ├── ci_document_model.dart │ │ ├──
co_maker_document_model.dart │ │ ├── co_maker_model.dart │ │ ├──
collection_assignment_model.dart │ │ ├── credit_investigation_model.dart │ │ ├──
disbursement_model.dart │ │ ├── emergency_contact_model.dart │ │ ├──
employee_profile_model.dart │ │ ├── in_office_application_model.dart │ │ ├──
kpi_employee_model.dart │ │ ├── kpi_head_manager_model.dart │ │ ├──
kpi_lender_model.dart │ │ ├── kpi_rider_model.dart │ │ ├──
lender_profile_model.dart │ │ ├── loan_document_model.dart │ │ ├──
loan_model.dart │ │ ├── loan_schedule_model.dart │ │ ├── notification_model.dart
│ │ ├── payment_model.dart │ │ ├── payment_reversal_model.dart │ │ ├──
penalty_log_model.dart │ │ ├── report_model.dart │ │ ├──
report_template_model.dart │ │ ├── rider_location_model.dart │ │ ├──
rider_profile_model.dart │ │ ├── sms_log_model.dart │ │ ├──
sms_template_model.dart │ │ ├── system_config_model.dart │ │ ├──
terms_consent_log_model.dart │ │ ├── user_model.dart │ │ └──
xendit_log_model.dart │ │ │ └── repositories/ │ # Implements domain interface.
Calls remote datasource via DioClient. │ # Handles errors, maps models to
entities. │ ├── account_upgrade_repository_impl.dart │ ├──
auth_repository_impl.dart │ ├── audit_repository_impl.dart │ ├──
blacklist_repository_impl.dart │ ├── ci_repository_impl.dart │ ├──
collection_repository_impl.dart │ ├── disbursement_repository_impl.dart │ ├──
in_office_repository_impl.dart │ ├── kpi_repository_impl.dart │ ├──
loan_repository_impl.dart │ ├── location_repository_impl.dart │ ├──
notification_repository_impl.dart │ ├── payment_repository_impl.dart │ ├──
report_repository_impl.dart │ ├── system_repository_impl.dart │ └──
user_repository_impl.dart │ ├── domain/ │ ├── entities/ │ │ # Pure Dart classes,
no Flutter imports, no JSON. │ │ ├── account_upgrade_document_entity.dart │ │
├── address_entity.dart │ │ ├── audit_log_entity.dart │ │ ├──
blacklist_entity.dart │ │ ├── ci_entity.dart │ │ ├── co_maker_entity.dart │ │
├── collection_assignment_entity.dart │ │ ├── disbursement_entity.dart │ │ ├──
emergency_contact_entity.dart │ │ ├── employee_profile_entity.dart │ │ ├──
in_office_application_entity.dart │ │ ├── kpi_entity.dart │ │ ├──
lender_profile_entity.dart │ │ ├── loan_entity.dart │ │ ├──
loan_schedule_entity.dart │ │ ├── notification_entity.dart │ │ ├──
payment_entity.dart │ │ ├── penalty_log_entity.dart │ │ ├── report_entity.dart │
│ ├── rider_location_entity.dart │ │ ├── rider_profile_entity.dart │ │ ├──
system_config_entity.dart │ │ └── user_entity.dart │ │ │ └── repositories/ │ #
Abstract interfaces only. No implementation here. │ ├──
i_account_upgrade_repository.dart │ ├── i_auth_repository.dart │ ├──
i_audit_repository.dart │ ├── i_blacklist_repository.dart │ ├──
i_ci_repository.dart │ ├── i_collection_repository.dart │ ├──
i_disbursement_repository.dart │ ├── i_in_office_repository.dart │ ├──
i_kpi_repository.dart │ ├── i_loan_repository.dart │ ├──
i_location_repository.dart │ ├── i_notification_repository.dart │ ├──
i_payment_repository.dart │ ├── i_report_repository.dart │ ├──
i_system_repository.dart │ └── i_user_repository.dart │ └── presentation/ │ ├──
shared/ │ ├── providers/ │ │ └── auth_state_provider.dart │ │ # Riverpod
StateNotifierProvider. │ │ # Holds: current user, role, force_password_change
flag. │ │ # Resets all state on logout. │ │ │ └── widgets/ │ ├── animated/ │ │
├── count_up_animation.dart # KPI number count-up on load │ │ ├──
fade_animation.dart │ │ ├── slide_animation.dart │ │ └── stagger_animation.dart
# List item stagger │ │ │ ├── dialogs/ │ │ ├── confirmation_dialog.dart #
Confirm before critical actions │ │ ├── error_dialog.dart # Generic error (no
stack trace) │ │ ├── info_dialog.dart │ │ └── success_dialog.dart │ │ │ ├──
forms/ │ │ ├── app_date_picker.dart # Philippine locale │ │ ├──
app_date_range_picker.dart │ │ ├── app_dropdown.dart # Searchable dropdown │ │
├── app_file_picker.dart # Type + size validation before upload │ │ └──
app_text_field.dart # Floating labels, real-time validation │ │ │ ├── layout/ │
│ ├── web_scaffold.dart │ │ │ # Collapsible sidebar (deep navy + gold) + top
bar. │ │ │ # Used by: Head Manager and Employee portals. │ │ │ │ │ └──
mobile_scaffold.dart │ │ # Bottom navigation bar. │ │ # Rider: green accent.
Lender: purple accent. │ │ │ ├── loaders/ │ │ ├── shimmer_loader.dart # Shimmer
effect placeholder │ │ └── skeleton_card.dart # KPI card skeleton │ │ │ ├──
navigation/ │ │ ├── collapsible_sidebar.dart │ │ │ # Sidebar for web portal.
Expands/collapses with animation. │ │ │ # Items driven by role — hidden items
never rendered. │ │ │ # Uses lucide icons. │ │ │ │ │ └── mobile_bottom_nav.dart
│ │ # Animated bottom navigation. Badge count for notifications. │ │ │ ├──
tables/ │ │ ├── enterprise_table.dart │ │ │ # Sticky header, resizable columns,
row hover, bulk select, │ │ │ # context menu, expandable rows, sort animations.
│ │ │ # Accepts: columns[], rows[], onRowTap, actions. │ │ │ │ │ ├──
table_filter_bar.dart # Search + filter chips + date range │ │ └──
table_pagination.dart # Page size selector + prev/next │ │ │ ├── app_button.dart
# Primary, secondary, danger variants │ ├── app_card.dart # Expandable card with
animation │ ├── app_chip.dart # Status chip (color-coded) │ ├──
document_viewer.dart # Signed URL image/PDF viewer │ ├── empty_state_widget.dart
# Illustration + CTA │ ├── error_state_widget.dart # Error + retry button │ ├──
kpi_stat_card.dart # Animated KPI card (count-up) │ ├── notification_badge.dart
# Unread count badge │ ├── pii_mask_widget.dart # Masked text (Juan D**_* C****)
│ ├── signature_pad.dart # Borrower signature capture widget │ ├──
status_badge.dart # Loan/Account Upgrade/collection status chip │ └──
upload_progress_widget.dart # File upload progress indicator │ └── features/ │
├── auth/ # ── ALL ROLES │ ├── providers/ │ │ └── auth_provider.dart │ │ #
Calls: auth-login, auth-send-otp, auth-verify-otp, │ │ #
auth-force-change-password, auth-logout, │ │ # auth-forgot-password,
auth-reset-password. │ │ # Manages: AuthState (loading, authenticated,
unauthenticated). │ │ # Uses: SecureStorage for token persistence. │ │ # Google
Sign-In: google_sign_in + Supabase OAuth. │ │ │ ├── screens/ │ │ ├──
splash_screen.dart │ │ │ # Checks auth token validity. Routes to: │ │ │ # →
Terms screen (first install, mobile only) │ │ │ # → Force change password screen
(if flag) │ │ │ # → Role dashboard (authenticated) │ │ │ # → Login screen
(unauthenticated) │ │ │ │ │ ├── terms_conditions_screen.dart │ │ │ # Mobile
only. One-time T&C acceptance. │ │ │ # Calls: terms acceptance stored locally +
backend log. │ │ │ # Cannot proceed without accepting. │ │ │ │ │ ├──
web_login_screen.dart │ │ │ # HM + Employee: Email + Password login. │ │ │ #
Deep navy sidebar-style branding panel + login form. │ │ │ # Password strength
indicator, show/hide toggle. │ │ │ # Forgot password link. │ │ │ │ │ ├──
mobile_login_screen.dart │ │ │ # Rider + Lender: Phone number input. │ │ │ #
Lender also shows: Google Sign-In button. │ │ │ # Static text: "Don't have an
account? Contact our office." │ │ │ # NO register link. NO create account
button. │ │ │ │ │ ├── otp_verify_screen.dart │ │ │ # 6-digit OTP input. 60s
countdown resend timer. │ │ │ # Auto-submit on 6th digit. Rate-limit error
handling. │ │ │ │ │ ├── force_change_password_screen.dart │ │ │ # Shown on first
login. Cannot bypass. │ │ │ # Calls: auth-force-change-password. │ │ │ #
Password strength indicator + complexity rules display. │ │ │ │ │ ├──
forgot_password_screen.dart │ │ │ # Web only. Email input. Calls:
auth-forgot-password. │ │ │ │ │ └── reset_password_screen.dart │ │ # Web only.
Token from email link. New password form. │ │ # Calls: auth-reset-password. │ │
│ └── widgets/ │ ├── login_form.dart │ ├── otp_input_widget.dart # 6-box OTP
field │ └── password_strength_indicator.dart │ │ ├── head_manager/ # ── WEB
PORTAL ──────────────── │ │ │ ├── dashboard/ │ │ ├── providers/ │ │ │ └──
hm_dashboard_provider.dart │ │ │ # Calls: kpi-head-manager. Supabase Realtime
subscription │ │ │ # for live KPI counter updates and activity feed. │ │ │ │ │
├── screens/ │ │ │ └── hm_dashboard_screen.dart │ │ │ # 19 KPI stat cards
(count-up animation on load). │ │ │ # Charts: monthly disbursements,
collections, loans by status. │ │ │ # Real-time activity feed (loan events,
Account Upgrade, payments). │ │ │ │ │ └── widgets/ │ │ ├──
hm_kpi_cards_grid.dart # 19-card responsive grid │ │ ├── hm_activity_feed.dart #
Live event scrollable feed │ │ └── hm_charts_panel.dart # Recharts-style
analytics │ │ │ ├── employees/ │ │ ├── providers/ │ │ │ └──
hm_employee_provider.dart │ │ │ # CRUD: users-create-employee,
users-update-profile, │ │ │ # users-suspend-activate, users-archive, │ │ │ #
users-get-list (role=employee). │ │ │ │ │ ├── screens/ │ │ │ ├──
hm_employee_list_screen.dart │ │ │ │ # Enterprise table: search,
filter(status/dept), sort, paginate. │ │ │ │ # Row actions: View Details, Edit,
Suspend/Activate, Archive. │ │ │ │ # Export: PDF, Excel. │ │ │ │ │ │ │ └──
hm_employee_details_screen.dart │ │ │ # Full employee profile: personal info,
position, dept, │ │ │ # activity log, assigned lenders count. │ │ │ # Action
buttons here (not on table row). │ │ │ │ │ └── widgets/ │ │ ├──
create_employee_modal.dart │ │ │ # Fields: name, gender, civil_status, DOB,
email, phone, │ │ │ # department, position, hired_at. │ │ │ # Default password:
12345678 (set server-side). │ │ │ │ │ └── edit_employee_modal.dart │ │ │ ├──
riders/ │ │ ├── providers/ │ │ │ └── hm_rider_provider.dart │ │ │ # CRUD:
users-create-rider, users-update-profile, │ │ │ # users-suspend-activate,
users-archive. │ │ │ │ │ ├── screens/ │ │ │ ├── hm_rider_list_screen.dart │ │ │
│ # Enterprise table: filter by status/vehicle_type. │ │ │ │ │ │ │ └──
hm_rider_details_screen.dart │ │ │ # Profile: name, plate, vehicle, license,
status, │ │ │ # total_collected, assignment history. │ │ │ │ │ └── widgets/ │ │
├── create_rider_modal.dart │ │ │ # Fields: name, phone, vehicle_type,
plate_number, │ │ │ # drivers_license_number, expiry, brand. │ │ │ │ │ └──
edit_rider_modal.dart │ │ │ ├── lenders/ │ │ ├── providers/ │ │ │ └──
hm_lender_provider.dart │ │ │ # users-create-lender,
users-get-list(role=lender), │ │ │ # blacklist-add, blacklist-remove. │ │ │ │ │
├── screens/ │ │ │ ├── hm_lender_list_screen.dart │ │ │ │ # Columns: name,
phone, GCash, Account Upgrade status, active loan, │ │ │ │ # blacklist status,
account status. │ │ │ │ │ │ │ └── hm_lender_details_screen.dart │ │ │ # Full
profile: personal, addresses, emergency contacts, │ │ │ # documents, Account
Upgrade submissions, loans history, │ │ │ # payment history, blacklist history.
│ │ │ # Masked PII display. │ │ │ │ │ └── widgets/ │ │ ├──
create_lender_modal.dart │ │ ├── edit_lender_modal.dart │ │ └──
blacklist_modal.dart # Reason + confirm dialog │ │ │ ├── loans/ │ │ ├──
providers/ │ │ │ └── hm_loan_provider.dart │ │ │ # loans-approve, loans-reject,
loans-cancel, │ │ │ # loans-get-list, loans-get-details, loans-apply-penalty, │
│ │ # loans-request-ci. │ │ │ │ │ ├── screens/ │ │ │ ├──
hm_loan_applications_list_screen.dart │ │ │ │ # Tabs: All / Pending / Under
Review / CI Required. │ │ │ │ # Filter: status, date, amount range. │ │ │ │ │ │
│ ├── hm_loan_application_details_screen.dart │ │ │ │ # Full review before any
action. │ │ │ │ # Sections: lender profile, Account Upgrade status, co-maker, │
│ │ │ # documents, loan request, previous history. │ │ │ │ # Buttons: Approve,
Reject, Request CI, Cancel. │ │ │ │ # Buttons visible ONLY here — never on list
table. │ │ │ │ │ │ │ ├── hm_loan_list_screen.dart │ │ │ │ # Tabs: Active /
Completed / Overdue / History. │ │ │ │ │ │ │ └── hm_loan_details_screen.dart │ │
│ # Full loan: amounts, schedule table, payment history, │ │ │ # disbursement
info, CI history, penalty history. │ │ │ │ │ └── widgets/ │ │ ├──
approve_reject_modal.dart # Confirm + rejection reason │ │ ├──
penalty_modal.dart # Server-computed amount preview │ │ └──
loan_schedule_table.dart # Period-by-period installment view │ │ │ ├──
account_upgrade/ │ │ ├── providers/ │ │ │ └── hm_account_upgrade_provider.dart │
│ │ # kyc-view?fn=get-list, kyc-view?fn=verify. │ │ │ │ │ ├── screens/ │ │ │ ├──
hm_account_upgrade_list_screen.dart │ │ │ │ # Filter: status, date, lender_name.
│ │ │ │ │ │ │ └── hm_account_upgrade_details_screen.dart │ │ │ # Document viewer
(signed URL). Verify / Reject per doc. │ │ │ # Rejection remarks textarea. │ │ │
│ │ └── widgets/ │ │ └── account_upgrade_document_viewer_modal.dart │ │ │ ├──
ci/ │ │ ├── providers/ │ │ │ └── hm_ci_provider.dart │ │ │ # ci-assign,
ci-get-list, users-get-list(role=rider,available). │ │ │ │ │ ├── screens/ │ │ │
├── hm_ci_list_screen.dart │ │ │ │ # Filter: status, rider, date range. │ │ │ │
│ │ │ └── hm_ci_details_screen.dart │ │ │ # CI details: borrower address,
assigned rider, │ │ │ # ci_notes, rider report summary, photo gallery │ │ │ #
(GPS-tagged), completion status + timeline. │ │ │ │ │ └── widgets/ │ │ └──
ci_assign_modal.dart │ │ # Rider picker (available only), deadline, notes. │ │ │
├── collections/ │ │ ├── providers/ │ │ │ └── hm_collection_provider.dart │ │ │
# collections-assign, collections-get-list, reassign. │ │ │ │ │ ├── screens/ │ │
│ ├── hm_collection_list_screen.dart │ │ │ └── hm_collection_details_screen.dart
│ │ │ # Assignment details, proof photos, signature, │ │ │ # GPS coordinates,
amount collected. │ │ │ │ │ └── widgets/ │ │ └──
assign_rider_collection_modal.dart │ │ # Rider picker, collection schedule
datetime, notes. │ │ │ ├── disbursements/ │ │ ├── providers/ │ │ │ └──
hm_disbursement_provider.dart │ │ │ # disbursements-gcash,
disbursements-office-cash, │ │ │ # disbursements-rider-delivery. │ │ │ │ │ ├──
screens/ │ │ │ ├── hm_disbursement_list_screen.dart │ │ │ │ # Columns: loan#,
lender, method, amount, status, date. │ │ │ │ │ │ │ └──
hm_disbursement_details_screen.dart │ │ │ # Method-specific: GCash→Xendit ref;
Cash→office notes; │ │ │ # Rider→delivery proof + signature. │ │ │ │ │ └──
widgets/ │ │ └── disburse_modal.dart │ │ # 3-tab modal: GCash / Office Cash /
Rider Delivery. │ │ │ ├── payments/ │ │ ├── providers/ │ │ │ └──
hm_payment_provider.dart │ │ │ # payments-get-list, payments-reverse,
payments-get-receipt. │ │ │ │ │ ├── screens/ │ │ │ ├──
hm_payment_list_screen.dart │ │ │ │ # Filter: method, status, date range. │ │ │
│ │ │ │ ├── hm_payment_details_screen.dart │ │ │ │ # Reference#, Xendit ID,
amount, method, recorded by, │ │ │ │ # remaining balance after payment. │ │ │ │
│ │ │ └── hm_penalty_list_screen.dart │ │ │ # All penalties: loan#, basis, rate,
amount, applied by, date. │ │ │ │ │ └── widgets/ │ │ └──
reverse_payment_modal.dart # HM only, reason required │ │ │ ├── blacklist/ │ │
├── providers/ │ │ │ └── hm_blacklist_provider.dart │ │ │ # blacklist-add,
blacklist-remove, blacklist-get-list. │ │ │ │ │ └── screens/ │ │ └──
hm_blacklist_screen.dart │ │ # Blacklisted lenders table. Add/remove buttons. │
│ # History: who blacklisted/removed, when, reason. │ │ │ ├── reports/ │ │ ├──
providers/ │ │ │ └── hm_report_provider.dart │ │ │ # reports-generate,
reports-get-list, reports-get-history. │ │ │ │ │ ├── screens/ │ │ │ ├──
hm_report_library_screen.dart │ │ │ │ # Grid of 14 report templates with
Generate button. │ │ │ │ │ │ │ └── hm_report_history_screen.dart │ │ │ #
Archived reports with signed download URLs. │ │ │ # Filter: date, report type. │
│ │ │ │ └── widgets/ │ │ └── generate_report_modal.dart │ │ # Date range,
filters, preview table, Export PDF / Excel. │ │ │ ├── audit/ │ │ ├── providers/
│ │ │ └── hm_audit_provider.dart │ │ │ # audit-get-logs. │ │ │ │ │ └── screens/
│ │ └── hm_audit_logs_screen.dart │ │ # Full audit trail: action, performed_by,
table, record, │ │ # old/new values (JSON diff view), IP, datetime. Read-only. │
│ │ ├── in_office/ │ │ ├── providers/ │ │ │ └── hm_in_office_provider.dart │ │ │
# in-office-create-draft, in-office-save-step, │ │ │ # in-office-submit,
in-office-get-list. │ │ │ # loans-get-schedule-preview (live preview call). │ │
│ │ │ ├── screens/ │ │ │ └── hm_in_office_list_screen.dart │ │ │ # Draft /
Submitted / Converted tabs. │ │ │ │ │ └── widgets/ │ │ ├── in_office_wizard.dart
# 5-step wizard container │ │ ├── wizard_step_indicator.dart # Step progress bar
│ │ ├── step1_identify_borrower.dart # Search/create lender │ │ ├──
step2_address_contacts.dart # Address + emergency contacts │ │ ├──
step3_loan_details.dart # Amount + freq + live schedule │ │ ├──
step4_co_maker.dart # Co-maker form + docs │ │ └── step5_docs_signature.dart #
Upload docs + signature pad │ │ │ ├── notifications/ │ │ ├── providers/ │ │ │
└── hm_notification_provider.dart │ │ │ # notifications-send,
notifications-get-list. │ │ │ │ │ └── screens/ │ │ └──
hm_notification_center_screen.dart │ │ # Sent notifications list. Send modal
(recipient, title, body). │ │ # SMS logs tab.. │ │ │ ├── settings/ │ │ ├──
providers/ │ │ │ └── hm_settings_provider.dart │ │ │ # system-get-config,
system-update-config. │ │ │ │ │ └── screens/ │ │ └── hm_settings_screen.dart │ │
# Sections: Roles, Permissions matrix, SMS Templates editor, │ │ # Report
Templates manager, System config values. │ │ │ └── profile/ │ ├── providers/ │ │
└── hm_profile_provider.dart │ │ # users-get-profile, users-update-profile, │ │
# auth-force-change-password. │ │ │ └── screens/ │ └── hm_profile_screen.dart │
# View/edit: name, gender, civil_status, DOB, photo. │ # Change password form
(requires current password). │ │ ├── employee/ # ── WEB PORTAL ────────────────
│ │ │ ├── dashboard/ │ │ ├── providers/ │ │ │ └── emp_dashboard_provider.dart │
│ │ # kpi-employee. Activity feed (own processed apps only). │ │ │ │ │ ├──
screens/ │ │ │ └── emp_dashboard_screen.dart │ │ │ # 7 KPI stat cards + own
activity feed. │ │ │ │ │ └── widgets/ │ │ └── emp_kpi_cards.dart │ │ │ ├──
lenders/ │ │ ├── providers/ │ │ │ └── emp_lender_provider.dart │ │ │ #
users-create-lender, users-get-list(role=lender), │ │ │ # users-update-profile.
│ │ │ # Cannot: suspend, archive, blacklist — hidden from UI. │ │ │ │ │ ├──
screens/ │ │ │ ├── emp_lender_list_screen.dart │ │ │ └──
emp_lender_details_screen.dart │ │ │ # Full profile. Blacklist/archive buttons
hidden. │ │ │ │ │ └── widgets/ │ │ ├── emp_register_lender_modal.dart │ │ └──
emp_edit_lender_modal.dart │ │ │ ├── riders/ │ │ ├── providers/ │ │ │ └──
emp_rider_provider.dart │ │ │ │ │ ├── screens/ │ │ │ ├──
emp_rider_list_screen.dart │ │ │ └── emp_rider_details_screen.dart │ │ │ │ │ └──
widgets/ │ │ └── emp_create_rider_modal.dart │ │ │ ├── loans/ │ │ ├── providers/
│ │ │ └── emp_loan_provider.dart │ │ │ # loans-get-list, loans-get-details,
loans-reject, │ │ │ # loans-approve, loans-request-ci. │ │ │ │ │ ├── screens/ │
│ │ ├── emp_loan_applications_screen.dart │ │ │ ├──
emp_loan_application_details_screen.dart │ │ │ │ # Review + Recommend
Approve/Reject. │ │ │ │ # Verify requirements, request docs. │ │ │ │ │ │ │ └──
emp_loan_details_screen.dart │ │ │ │ │ └── widgets/ │ │ └──
emp_loan_action_modal.dart │ │ │ ├── account_upgrade/ │ │ ├── providers/ │ │ │
└── emp_account_upgrade_provider.dart │ │ │ │ │ ├── screens/ │ │ │ ├──
emp_account_upgrade_list_screen.dart │ │ │ └──
emp_account_upgrade_details_screen.dart │ │ │ │ │ └── widgets/ │ │ └──
emp_account_upgrade_verify_modal.dart │ │ │ ├── ci/ │ │ ├── providers/ │ │ │ └──
emp_ci_provider.dart │ │ │ │ │ ├── screens/ │ │ │ ├── emp_ci_list_screen.dart │
│ │ └── emp_ci_details_screen.dart │ │ │ │ │ └── widgets/ │ │ └──
emp_ci_assign_modal.dart │ │ │ ├── collections/ │ │ ├── providers/ │ │ │ └──
emp_collection_provider.dart │ │ │ │ │ ├── screens/ │ │ │ ├──
emp_collection_list_screen.dart │ │ │ └── emp_collection_details_screen.dart │ │
│ │ │ └── widgets/ │ │ └── emp_assign_rider_modal.dart │ │ │ ├── payments/ │ │
├── providers/ │ │ │ └── emp_payment_provider.dart │ │ │ # payments-get-list,
payments-record-office. │ │ │ │ │ ├── screens/ │ │ │ ├──
emp_payment_list_screen.dart │ │ │ └── emp_payment_details_screen.dart │ │ │ │ │
└── widgets/ │ │ └── record_office_payment_modal.dart │ │ # Loan selector,
amount, date, notes, idempotency key. │ │ │ ├── in_office/ │ │ ├── providers/ │
│ │ └── emp_in_office_provider.dart │ │ │ # Same edge functions as HM but
employee-scoped. │ │ │ # Can only see own drafts (HM sees all). │ │ │ │ │ └──
screens/ │ │ └── emp_in_office_list_screen.dart │ │ # Re-uses wizard widgets
from shared in_office widgets. │ │ │ ├── notifications/ │ │ ├── providers/ │ │ │
└── emp_notification_provider.dart │ │ │ │ │ └── screens/ │ │ └──
emp_notifications_screen.dart │ │ │ └── profile/ │ ├── providers/ │ │ └──
emp_profile_provider.dart │ │ │ └── screens/ │ └── emp_profile_screen.dart │ │
├── rider/ # ── MOBILE (Green accent) ────── │ │ │ ├── dashboard/ │ │ ├──
providers/ │ │ │ └── rider_dashboard_provider.dart │ │ │ # kpi-rider. Fetches
today's assignments (CI + collection). │ │ │ │ │ ├── screens/ │ │ │ └──
rider_dashboard_screen.dart │ │ │ # 6 KPI stat cards. Today's task list (CI +
collection). │ │ │ # Pull-to-refresh. │ │ │ │ │ └── widgets/ │ │ └──
rider_task_card.dart # Assignment card with deep-link │ │ │ ├── collections/ │ │
├── providers/ │ │ │ └── rider_collection_provider.dart │ │ │ #
collections-accept, collections-decline, │ │ │ # collections-record,
collections-upload-proof, │ │ │ # collections-get-list. │ │ │ #
location-update-rider (during active collection). │ │ │ │ │ ├── screens/ │ │ │
├── rider_collection_list_screen.dart │ │ │ │ # Tabs: Pending / Accepted /
Completed / Failed. │ │ │ │ │ │ │ ├── rider_collection_details_screen.dart │ │ │
│ # Assignment: borrower, loan#, amount due, schedule, notes. │ │ │ │ # Accept /
Decline buttons. │ │ │ │ │ │ │ ├── rider_borrower_info_screen.dart │ │ │ │ #
Borrower profile: name, phone, address. Call shortcuts. │ │ │ │ │ │ │ ├──
rider_navigate_to_borrower_screen.dart │ │ │ │ # Google Maps route from rider
GPS to borrower home address. │ │ │ │ │ │ │ ├──
rider_record_collection_screen.dart │ │ │ │ # Amount input, payment method,
notes. │ │ │ │ # GPS auto-captured. Calls: collections-record. │ │ │ │ │ │ │ └──
rider_upload_proof_screen.dart │ │ │ # Camera/gallery for: payment proof,
borrower signature pad, │ │ │ # scene photo. Calls: collections-upload-proof. │
│ │ │ │ └── widgets/ │ │ └── rider_collection_card.dart │ │ │ ├── ci/ │ │ ├──
providers/ │ │ │ └── rider_ci_provider.dart │ │ │ # ci-accept, ci-decline,
ci-upload-documents, ci-submit-report, │ │ │ # ci-get-list. │ │ │ │ │ ├──
screens/ │ │ │ ├── rider_ci_list_screen.dart │ │ │ │ # Tabs: Pending / Accepted
/ In Progress / Completed. │ │ │ │ │ │ │ ├── rider_ci_details_screen.dart │ │ │
│ # CI assignment: borrower to investigate, deadline, notes. │ │ │ │ # Accept /
Decline buttons. │ │ │ │ │ │ │ ├── rider_ci_borrower_info_screen.dart │ │ │ │ #
Borrower addresses for CI visit. │ │ │ │ │ │ │ ├──
rider_navigate_to_borrower_ci_screen.dart │ │ │ │ # Google Maps route to
borrower address for CI. │ │ │ │ │ │ │ ├── rider_upload_ci_documents_screen.dart
│ │ │ │ # Camera/gallery. Caption per photo. GPS auto-tagged. │ │ │ │ # Types:
site photo, neighbor interview, proof of residence. │ │ │ │ # Calls:
ci-upload-documents. │ │ │ │ │ │ │ └── rider_submit_ci_report_screen.dart │ │ │
# Rider writes investigation notes. Reviews uploaded docs. │ │ │ # Submit
triggers ci-submit-report. │ │ │ │ │ └── widgets/ │ │ └──
rider_ci_evidence_gallery.dart │ │ │ ├── location/ │ │ └── providers/ │ │ └──
rider_location_provider.dart │ │ # Background GPS posting (30s interval). │ │ #
Calls: location-update-rider. │ │ # Manages: permission, tracking state,
foreground service. │ │ │ ├── notifications/ │ │ ├── providers/ │ │ │ └──
rider_notification_provider.dart │ │ │ # notifications-get-list,
notifications-mark-read. │ │ │ # FCM foreground listener → in-app notification.
│ │ │ # Assignment notifications deep-link to detail screen. │ │ │ │ │ └──
screens/ │ │ └── rider_notifications_screen.dart │ │ │ └── profile/ │ ├──
providers/ │ │ └── rider_profile_provider.dart │ │ # users-get-profile,
users-update-profile, │ │ # auth-force-change-password. │ │ │ └── screens/ │ └──
rider_profile_screen.dart │ # View/edit: name, photo, plate, vehicle, license. │
# Change password form. │ │ └── lender/ # ── MOBILE (Purple accent) ───── │ ├──
dashboard/ │ ├── providers/ │ │ └── lender_dashboard_provider.dart │ │ #
kpi-lender. Quick action buttons state. │ │ │ ├── screens/ │ │ └──
lender_dashboard_screen.dart │ │ # 10 KPI stat cards (count-up animation). │ │ #
Quick actions: Apply for Loan, Pay Now, View Schedule. │ │ │ └── widgets/ │ └──
lender_kpi_cards.dart │ ├── account_upgrade/ │ ├── providers/ │ │ └──
lender_account_upgrade_provider.dart │ │ # kyc-submit?fn=submit,
kyc-view?fn=get-status. │ │ │ └── screens/ │ ├──
lender_account_upgrade_submit_screen.dart │ │ # Required docs: valid ID, selfie,
proof of billing, │ │ # proof of income. File type + size validated before
upload. │ │ # Upload progress per file. Submit when all uploaded. │ │ │ └──
lender_account_upgrade_status_screen.dart │ # Status timeline: Submitted → Under
Review → Verified/Rejected. │ # Rejection notes visible. Resubmit button if
rejected. │ ├── loans/ │ ├── providers/ │ │ └── lender_loan_provider.dart │ │ #
loans-apply, loans-cancel, loans-get-list, │ │ # loans-get-details,
loans-get-schedule-preview. │ │ │ └── screens/ │ ├──
lender_apply_loan_screen.dart │ │ # Amount slider ₱3,000–₱500,000. │ │ # Payment
frequency selector (daily/weekly/monthly). │ │ # Purpose text field. │ │ # Live
schedule preview: calls loans-get-schedule-preview, │ │ # shows installment
table instantly (NO Dart math). │ │ # Blocked if: Account Upgrade not verified,
active loan exists, blacklisted │ │ # (all checks done server-side; UI shows
server error message). │ │ │ ├── lender_loan_application_status_screen.dart │ │
# Timeline: Applied → Account Upgrade Verified → CI Done → Approved/Rejected. │
│ # Rejection reason shown. │ │ │ ├── lender_loan_details_screen.dart │ │ #
Loan#, amount, total_payable, interest, installment, │ │ # frequency, term,
due_date, outstanding_balance, │ │ # disbursement info. │ │ │ └──
lender_loan_history_screen.dart │ ├── payments/ │ ├── providers/ │ │ └──
lender_payment_provider.dart │ │ # payments-generate-xendit-link,
payments-get-list, │ │ # payments-get-receipt. │ │ │ └── screens/ │ ├──
lender_payment_schedule_screen.dart │ │ # Period-by-period: due date, amount
due, paid, status. │ │ # Download schedule button. │ │ │ ├──
lender_pay_via_gcash_screen.dart │ │ # Generates Xendit payment link. Redirects
to GCash app. │ │ # Shows pending → confirmed state after webhook fires. │ │ │
├── lender_payment_history_screen.dart │ │ # All payments: date, amount, method,
status, reference#. │ │ │ └── lender_payment_receipt_screen.dart │ # PDF receipt
viewer. Download + share buttons. │ ├── collections/ │ ├── providers/ │ │ └──
lender_collection_provider.dart │ │ # collections-get-list, location-get-rider
(polling 30s). │ │ │ └── screens/ │ ├── lender_collection_history_screen.dart │
│ # Rider collection visits: date, rider, amount, status. │ │ │ ├──
lender_collection_details_screen.dart │ │ # One collection: rider name, date,
amount, proof photo. │ │ # "Track Rider" button (visible during active
assignment). │ │ │ └── lender_track_rider_screen.dart │ # Google Maps showing
rider's real-time GPS location. │ # Updates every 30s. Calls:
location-get-rider. │ ├── documents/ │ ├── providers/ │ │ └──
lender_documents_provider.dart │ │ # kyc-submit?fn=submit (reuse), signed URL
fetch. │ │ │ └── screens/ │ ├── lender_documents_screen.dart │ │ # All uploaded
docs (Account Upgrade + loan attachments). │ │ # Type, upload date, status.
Signed URL viewer. │ │ │ └── lender_upload_document_screen.dart │ # Doc type
picker, file picker, upload progress. │ ├── notifications/ │ ├── providers/ │ │
└── lender_notification_provider.dart │ │ # notifications-get-list,
notifications-mark-read. │ │ # FCM foreground listener. Badge count on bottom
nav. │ │ │ └── screens/ │ └── lender_notifications_screen.dart │ # All push
notifications. Mark read. Loan/payment deep-links. │ └── profile/ ├── providers/
│ └── lender_profile_provider.dart │ # users-get-profile, users-update-profile.
│ └── screens/ ├── lender_profile_screen.dart │ # Name, phone (masked), GCash,
employment, income. │ # Upload profile photo button. │ └──
lender_edit_profile_screen.dart # Edit all personal details. Save calls
users-update-profile..
