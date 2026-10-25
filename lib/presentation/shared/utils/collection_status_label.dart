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
