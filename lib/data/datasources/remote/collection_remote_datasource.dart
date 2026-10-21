// lib/data/datasources/remote/collection_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../models/collection_assignment_model.dart';
import '../../models/rider_collection_monitoring_model.dart';
import '../../models/rider_quota_model.dart';

class CollectionRemoteDataSource {
  final DioClient _client;
  CollectionRemoteDataSource(this._client);

  Future<List<CollectionAssignmentModel>> getCollectionList({
    String? status,
    String? riderId,
    String? dateFrom,
    String? dateTo,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.collectionsGetList,
      queryParams: {
        if (status != null) 'status': status,
        if (riderId != null) 'rider_id': riderId,
        if (dateFrom != null) 'date_from': dateFrom,
        if (dateTo != null) 'date_to': dateTo,
        if (search != null) 'search': search,
        'page': page,
        'limit': limit,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    return list
        .map(
          (e) => CollectionAssignmentModel.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  Future<Map<String, dynamic>> getList({
    String? status,
    String? riderId,
    String? dateFrom,
    String? dateTo,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.collectionsGetList,
      queryParams: {
        if (status != null) 'status': status,
        if (riderId != null) 'rider_id': riderId,
        if (dateFrom != null) 'date_from': dateFrom,
        if (dateTo != null) 'date_to': dateTo,
        if (search != null) 'search': search,
        'page': page,
        'limit': limit,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    return {
      'items': list,
      'total': (res.data['total'] as num?)?.toInt() ?? list.length,
    };
  }

  /// HM/Employee: per-rider monitoring table + summary cards.
  ///
  /// `dateFrom`/`dateTo` ay `YYYY-MM-DD` (Manila). Ang server ang nagde-dedupe
  /// ng schedules, payments at accounts — huwag i-recompute sa UI.
  Future<RiderMonitoringPage> getRiderMonitoring({
    String? riderId,
    String? status,
    String? dateFrom,
    String? dateTo,
    String? search,
    String sort = 'rider_name',
    String dir = 'asc',
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.collectionsRiderMonitoring,
      queryParams: {
        if (riderId != null) 'rider_id': riderId,
        if (status != null && status != 'all') 'status': status,
        if (dateFrom != null) 'date_from': dateFrom,
        if (dateTo != null) 'date_to': dateTo,
        if (search != null && search.isNotEmpty) 'search': search,
        'sort': sort,
        'dir': dir,
        'page': page,
        'limit': limit,
      },
    );
    return RiderMonitoringPage.fromJson(
        Map<String, dynamic>.from(res.data as Map));
  }

  /// HM/Employee: profile + accounts + verified payments + collection history
  /// para sa isang rider lang. Role at data scoping ay server-side.
  Future<RiderMonitoringDetail> getRiderMonitoringDetail(
    String riderId, {
    String? dateFrom,
    String? dateTo,
  }) async {
    final res = await _client.get(
      ApiEndpoints.collectionsRiderMonitoringDetail,
      queryParams: {
        'rider_id': riderId,
        if (dateFrom != null) 'date_from': dateFrom,
        if (dateTo != null) 'date_to': dateTo,
      },
    );
    return RiderMonitoringDetail.fromJson(
        Map<String, dynamic>.from(res.data as Map));
  }

  /// Rider: sariling totals para sa "My Collections" header.
  Future<RiderMonitoringSummary> getMyCollectionSummary({
    String? dateFrom,
    String? dateTo,
  }) async {
    final res = await _client.get(
      ApiEndpoints.collectionsMySummary,
      queryParams: {
        if (dateFrom != null) 'date_from': dateFrom,
        if (dateTo != null) 'date_to': dateTo,
      },
    );
    final data = (res.data is Map) ? (res.data as Map)['data'] : null;
    final summary = data is Map ? data['summary'] : null;
    return RiderMonitoringSummary.fromJson(
        Map<String, dynamic>.from((summary as Map?) ?? const {}));
  }

  Future<void> assign({
    required String loanScheduleId,
    required String riderId,
    String? collectionSchedule,
    String? notes,
    String? assignmentId,
  }) =>
      assignCollection(
        loanScheduleId: loanScheduleId,
        riderId: riderId,
        collectionSchedule: collectionSchedule,
        notes: notes,
        assignmentId: assignmentId,
      );

  Future<CollectionAssignmentModel> assignCollection({
    required String loanScheduleId,
    required String riderId,
    String? collectionSchedule,

    /// Katapusan ng rider visit window ("From – To" na iskedyul).
    String? collectionScheduleEnd,
    String? notes,
    String? assignmentId,
  }) async {
    final res = await _client.post(
      ApiEndpoints.collectionsAssign,
      data: {
        if (assignmentId != null) 'assignment_id': assignmentId,
        'loan_schedule_id': loanScheduleId,
        'rider_id': riderId,
        if (collectionSchedule != null)
          'collection_schedule': collectionSchedule,
        if (collectionScheduleEnd != null)
          'collection_schedule_end': collectionScheduleEnd,
        if (notes != null) 'notes': notes,
      },
    );
    return CollectionAssignmentModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// Lender requests a rider to collect their installment at home, or an
  /// office visit to pay at the office (`type` = 'rider' | 'office').
  /// If [amount] is provided, it is the flexible payment amount the lender
  /// wishes to pay (must be >0 and <= outstanding balance). System will
  /// allocate it across unpaid installments (partial/advance supported).
  Future<Map<String, dynamic>> requestRiderCollection({
    required String loanScheduleId,
    String type = 'rider',
    double? amount,
  }) async {
    // Mas mahabang timeout: ang server-side fan-out (audit + staff FCM push)
    // ay puwedeng lumampas sa default na 30s sa mabagal na network/cold start
    // at magdulot ng pekeng "Request Timed Out" kahit na-created na ang
    // request. Ang backend ay sumasagot muna bago ang background work, kaya
    // sapat na ang mas mahabang budget dito.
    final res = await _client.post(
      ApiEndpoints.collectionsRequest,
      data: {
        'loan_schedule_id': loanScheduleId,
        'type': type,
        if (amount != null) 'amount': amount,
      },
      timeout: const Duration(seconds: 60),
    );
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  /// Isang assignment lang ang kukunin, gamit ang `collections-view?fn=get`.
  /// Eksakto at isang query lang — hindi na kailangang mag-scan ng buong listahan
  /// sa iba't ibang status (na dati ay nagdudulot ng maling "not found" kapag
  /// may isang status-fetch na tahimik na nabigo).
  Future<CollectionAssignmentModel?> getCollectionById(
      String assignmentId) async {
    final res = await _client.get(
      ApiEndpoints.collectionsGet,
      queryParams: {'id': assignmentId},
    );
    final data = res.data is Map ? (res.data as Map)['data'] : null;
    if (data is Map) {
      return CollectionAssignmentModel.fromJson(
          Map<String, dynamic>.from(data));
    }
    return null;
  }

  Future<void> acceptCollection({required String assignmentId}) async {
    await _client.patch(
      ApiEndpoints.collectionsAccept,
      data: {'assignment_id': assignmentId},
    );
  }

  Future<void> declineCollection({required String assignmentId}) async {
    await _client.patch(
      ApiEndpoints.collectionsDecline,
      data: {'assignment_id': assignmentId},
    );
  }

  /// Head Manager / Employee: kinukumpirma na nakuha ang pera. Dito lang
  /// nagiging `verified` ang rider payment at bumababa ang loan balance.
  Future<void> approveCollection({required String assignmentId}) async {
    await _client.post(
      ApiEndpoints.collectionsApprove,
      data: {'assignment_id': assignmentId},
    );
  }

  /// Head Manager / Employee: hindi nakuha ang pera. Hindi binabawasan ang
  /// loan; kailangang mag-assign muli ng rider para mangolekta.
  Future<void> rejectCollection({
    required String assignmentId,
    required String reason,
  }) async {
    await _client.post(
      ApiEndpoints.collectionsReject,
      data: {'assignment_id': assignmentId, 'reason': reason},
    );
  }

  Future<void> recordCollection({
    required String assignmentId,
    required double amountCollected,
    String? notes,
    required String idempotencyKey,
  }) async {
    await _client.postWithIdempotency(
      ApiEndpoints.collectionsRecord,
      data: {
        'assignment_id': assignmentId,
        'amount_collected': amountCollected,
        if (notes != null) 'notes': notes,
      },
      idempotencyKey: idempotencyKey,
    );
  }

  /// Returns ang server-confirmed status (`'completed'`) kapag nagtagumpay, o
  /// `null` kapag walang status sa sagot. Ito ang tanging tawag sa Step 3
  /// Submit — dito na naka-save ang `amount_collected` at ang proofs, kaya
  /// hindi na kailangang mag-record muna ng hiwalay na request.
  Future<String?> uploadProof({
    required String assignmentId,
    required List<Map<String, dynamic>> proofs,

    /// Kapag WALA pang verified payment sa server, ito ang amount na itatala ng
    /// `fn=upload-proof` mismo (self-heal) — hindi na kailangang umulit ng
    /// rider mula Step 1 dahil sa PAYMENT_NOT_RECORDED.
    double? amountCollected,
    String? notes,
  }) async {
    final res = await _client.post(
      ApiEndpoints.collectionsUploadProof,
      // 2 larawan (proof + scene) na base64 ay mabigat — ang default 30s
      // send/receive timeout ay masyadong maiksi sa mobile data, kaya nag-
      // timeout (at nagmumukhang "failed") kahit natanggap naman ng server.
      timeout: const Duration(minutes: 2),
      data: {
        'assignment_id': assignmentId,
        'proofs': proofs,
        if (amountCollected != null && amountCollected > 0)
          'amount_collected': amountCollected,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    final data = res.data;
    if (data is Map) return data['status'] as String?;
    return null;
  }

  /// HM/Employee: rider quota table + summary cards.
  ///
  /// `confirmed` at `status` ay galing sa `rider_quota_monitoring` RPC —
  /// verified payments lang at nasa loob ng quota window (Asia/Manila).
  Future<RiderQuotaPage> getRiderQuotas({
    String? riderId,
    String? period,
    String? status,
    String? dateFrom,
    String? dateTo,
    String? search,
    String sort = 'start_date',
    String dir = 'desc',
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.collectionsRiderQuotas,
      queryParams: {
        if (riderId != null) 'rider_id': riderId,
        if (period != null && period.isNotEmpty) 'period': period,
        if (status != null && status != 'all') 'status': status,
        if (dateFrom != null) 'date_from': dateFrom,
        if (dateTo != null) 'date_to': dateTo,
        if (search != null && search.isNotEmpty) 'search': search,
        'sort': sort,
        'dir': dir,
        'page': page,
        'limit': limit,
      },
    );
    return RiderQuotaPage.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// HM/Employee: active riders para sa assign form dropdown.
  Future<List<RiderQuotaRiderOption>> getRiderQuotaRiders() async {
    final res = await _client.get(ApiEndpoints.collectionsRiderQuotaRiders);
    final list = (res.data is Map) ? (res.data as Map)['data'] : null;
    return ((list as List?) ?? const [])
        .whereType<Map>()
        .map((e) => RiderQuotaRiderOption.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// Rider: sariling quota, previous results at ang verified payments na
  /// bumubuo sa kasalukuyang quota (rider id galing sa token).
  Future<RiderQuotaSelf> getMyQuota() async {
    final res = await _client.get(ApiEndpoints.collectionsMyQuota);
    final data = (res.data is Map) ? (res.data as Map)['data'] : null;
    return RiderQuotaSelf.fromJson(
        Map<String, dynamic>.from((data as Map?) ?? const {}));
  }

  /// Head Manager: mag-assign ng quota. Ang dates ay `YYYY-MM-DD` (Manila).
  Future<void> createRiderQuota({
    required String riderId,
    required String period,
    required double targetAmount,
    required String startDate,
    required String endDate,
    String? notes,
  }) async {
    await _client.post(
      ApiEndpoints.collectionsCreateRiderQuota,
      data: {
        'rider_id': riderId,
        'period': period,
        'target_amount': targetAmount,
        'start_date': startDate,
        'end_date': endDate,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
  }

  /// Head Manager: i-edit ang upcoming/active quota. Ang tapos nang period
  /// ay tinatanggihan ng server (historical record).
  Future<void> updateRiderQuota({
    required String quotaId,
    required String period,
    required double targetAmount,
    required String startDate,
    required String endDate,
    String? notes,
  }) async {
    await _client.patch(
      ApiEndpoints.collectionsUpdateRiderQuota,
      data: {
        'quota_id': quotaId,
        'period': period,
        'target_amount': targetAmount,
        'start_date': startDate,
        'end_date': endDate,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
  }

  /// Head Manager: soft-close (is_active=false). Nananatili ang history at
  /// hindi nababago ang mga naunang resulta.
  Future<void> closeRiderQuota(String quotaId) async {
    await _client.post(
      ApiEndpoints.collectionsCloseRiderQuota,
      data: {'quota_id': quotaId},
    );
  }
}
