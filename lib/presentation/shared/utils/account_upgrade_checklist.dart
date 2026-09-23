// lib/presentation/shared/utils/account_upgrade_checklist.dart

/// Isang inaasahang dokumento ng Account Upgrade, kasama ang row na nahanap
/// sa `account_upgrade_documents` (null kapag wala).
class AccountUpgradeChecklistItem {
  final String type;
  final bool required;
  final Map<String, dynamic>? doc;

  const AccountUpgradeChecklistItem({
    required this.type,
    required this.required,
    this.doc,
  });

  /// May row sa DB (kahit `pending` pa ang status).
  bool get submitted => doc != null;

  /// Required pero wala sa DB — ito ang dating tahimik na nawawala sa
  /// reviewer screen (hal. Face Recognition na hindi na-submit sa web).
  bool get missingRequired => required && doc == null;

  String get status => (doc?['status'] ?? '').toString().toLowerCase();
}

/// Ang buong checklist ng Account Upgrade, sa parehong order na ipinapakita
/// sa lender (`lender_account_upgrade_submit_screen.dart`); ang may `*` doon
/// ang required. Ang `lender_signature` ay auto-captured sa Residence step.
const List<AccountUpgradeChecklistItem> kAccountUpgradeDocs = [
  AccountUpgradeChecklistItem(type: 'valid_id', required: true),
  AccountUpgradeChecklistItem(type: 'selfie', required: false),
  AccountUpgradeChecklistItem(type: 'mayors_permit', required: true),
  AccountUpgradeChecklistItem(type: 'lender_signature', required: false),
  AccountUpgradeChecklistItem(type: 'face_recognition', required: true),
];

/// Pinagsasama ang checklist sa aktwal na `documents[]` ng `kyc-view`.
///
/// Lahat ng item sa [kAccountUpgradeDocs] ay laging kasama sa resulta —
/// `doc == null` kapag wala sa DB — para makita ng reviewer ang "Not
/// submitted" sa halip na basta mawala ang dokumento. Ang mga type na wala
/// sa checklist (hal. walk-in docs: `itr`, `business_registration`,
/// `co_maker`) ay idinadagdag pa rin sa dulo para walang mawalang file.
List<AccountUpgradeChecklistItem> buildAccountUpgradeChecklist(
  List<dynamic> documents,
) {
  final byType = <String, Map<String, dynamic>>{};
  for (final raw in documents) {
    if (raw is! Map) continue;
    final doc = raw.cast<String, dynamic>();
    final type = doc['document_type']?.toString() ?? '';
    // Ang valid_id_front/back ay isang "Valid Government ID" tile lang —
    // binubuksan ang likod sa carousel ng `_openDocument`.
    if (type.isEmpty || type == 'valid_id_back') continue;
    byType.putIfAbsent(type, () => doc);
  }

  final items = <AccountUpgradeChecklistItem>[
    for (final spec in kAccountUpgradeDocs)
      AccountUpgradeChecklistItem(
        type: spec.type,
        required: spec.required,
        doc: byType.remove(spec.type),
      ),
  ];
  byType.forEach((type, doc) {
    items.add(AccountUpgradeChecklistItem(type: type, required: false, doc: doc));
  });
  return items;
}
