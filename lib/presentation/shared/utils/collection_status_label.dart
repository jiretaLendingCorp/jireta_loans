// lib/presentation/shared/utils/collection_status_label.dart

/// Proper na pangalan ng status ng isang collection assignment — hindi ang
/// hilaw na `status` sa DB na basta naka-capitalize.
///
/// Pinakamahalaga dito ang `failed`: hindi ito basta "Failed" na parang
/// may nagkamali. Ang ibig sabihin ay HINDI NAKOLEKTA ang koleksyon —
/// nag-expire ang request (48h walang aksyon) o na-overdue ang assignment
/// (lumipas ang `collection_schedule` + 24h / `due_date` + 3d), kaya
/// automatic itong sinara ng system. "Uncollected" din ang tawag dito sa
/// rider side (`CollectionAssignmentModel.statusLabel`) at sa History, kaya
/// pantay na ang salita sa lahat ng role.
String collectionStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'pending':
      return 'Pending';
    case 'requested':
      return 'Requested';
    case 'assigned':
      return 'Assigned';
    case 'accepted':
      return 'Accepted';
    case 'in_progress':
      return 'In Progress';
    case 'pending_approval':
      return 'Pending Approval';
    case 'completed':
      return 'Completed';
    case 'rejected':
      return 'Rejected';
    case 'declined':
      return 'Declined';
    case 'cancelled':
      return 'Cancelled';
    case 'expired':
      return 'Expired';
    case 'failed':
      return 'Uncollected';
    default:
      // Hindi pa kilalang status — capitalize lang ang bawat salita para may
      // mabasang label pa rin imbes na hilaw na `snake_case`.
      return status
          .split('_')
          .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
  }
}

/// Maikling paliwanag kung BAKIT naging `failed`/`expired` ang assignment —
/// galing sa `collection_notes` na sinusulat ng system. Dalawa lang ang
/// pinagmulan nito:
///   • `expired: no action within 48h` — lender request na walang umaksyon
///     (collections-manage, kapag may bagong request sa parehong schedule).
///   • `[auto-expired: overdue]` — na-overdue ang assignment at sinara ng
///     `expire_overdue_assignments()`.
///
/// `null` kapag hindi failed/expired ang status o walang makikilalang system
/// note — hindi nagpapakita ng haka-haka o libreng staff note.
String? collectionCloseReason(String status, String? notes) {
  final s = status.toLowerCase();
  if (s != 'failed' && s != 'expired') return null;
  final text = (notes ?? '').toLowerCase();
  if (text.contains('no action within 48h')) return 'No action within 48h';
  if (text.contains('auto-expired') || text.contains('overdue')) {
    return 'Overdue — auto-closed';
  }
  return null;
}
