import '../../cart/domain/order_pricing.dart' show formatInr;

/// Reward rules (mirrors the server in rewards.js; display only; the server
/// calculates and validates every value).
const double kRewardRate = 0.025;
const double kFreeClaimThreshold = 100000;

double _num(Object? value) => (num.tryParse('${value ?? ''}') ?? 0).toDouble();
double _round2(double v) => (v * 100).roundToDouble() / 100;

/// "12.50", "3,558", "1,271.25": Indian grouping, decimals only when needed.
String formatPoints(double points) {
  final rounded = _round2(points);
  final whole = rounded == rounded.truncateToDouble();
  final text = formatInr(rounded.abs(), decimals: !whole);
  final digits = whole ? text.substring(1).split('.').first : text.substring(1);
  return '${rounded < 0 ? '−' : ''}$digits';
}

/// One row of the reward ledger.
class RewardEntry {
  const RewardEntry({
    required this.type,
    required this.status,
    this.orderId,
    this.orderDate,
    this.date,
    this.orderAmount = 0,
    this.pointsEarned = 0,
    this.pointsRedeemed = 0,
  });

  /// earned | reversed | reinstated | redeemed
  final String type;

  /// credited | reversed | pending | approved | rejected
  final String status;
  final String? orderId;
  final DateTime? orderDate;
  final DateTime? date;
  final double orderAmount;
  final double pointsEarned;
  final double pointsRedeemed;

  bool get isClaim => type == 'redeemed';

  factory RewardEntry.fromJson(Map json) {
    final earned = _num(json['pointsEarned'] ?? json['points']);
    final type = '${json['type'] ?? ''}'.trim().isNotEmpty
        ? '${json['type']}'
        : (earned < 0 ? 'reversed' : 'earned');
    final status = '${json['status'] ?? ''}'.trim().isNotEmpty
        ? '${json['status']}'
        : (earned < 0 ? 'reversed' : 'credited');
    final orderId = '${json['orderId'] ?? ''}'.trim();
    return RewardEntry(
      type: type,
      status: status,
      orderId: orderId.isEmpty || orderId == 'null' ? null : orderId,
      orderDate: DateTime.tryParse('${json['orderDate'] ?? ''}'),
      date: DateTime.tryParse('${json['createdAt'] ?? json['date'] ?? ''}'),
      orderAmount: _num(json['orderAmount']),
      pointsEarned: earned,
      pointsRedeemed: _num(json['pointsRedeemed']),
    );
  }
}

/// Reward balance, Free Claim eligibility and history for the Profile page.
class RewardSummary {
  const RewardSummary({
    required this.availablePoints,
    required this.totalEarned,
    required this.totalRedeemed,
    required this.pendingRedemption,
    required this.eligiblePurchase,
    required this.history,
    this.threshold = kFreeClaimThreshold,
    this.pointValue = 1,
    this.claimAvailable = true,
  });

  /// False until the server's reward ledger is ready (it then says so).
  final bool claimAvailable;

  final double availablePoints;
  final double totalEarned;
  final double totalRedeemed;
  final double pendingRedemption;

  /// Cumulative amount of all non-cancelled orders.
  final double eligiblePurchase;
  final double threshold;

  /// Rupees per point.
  final double pointValue;
  final List<RewardEntry> history;

  double get availableValue => _round2(availablePoints * pointValue);
  bool get unlocked => eligiblePurchase >= threshold;
  double get remaining =>
      _round2((threshold - eligiblePurchase).clamp(0, threshold).toDouble());
  double get progress =>
      threshold <= 0 ? 1 : (eligiblePurchase / threshold).clamp(0.0, 1.0);
  bool get canClaim => claimAvailable && unlocked && availablePoints > 0;

  /// From GET /api/user/rewards. Older servers only sent totals + history,
  /// so missing figures are derived from the history.
  factory RewardSummary.fromJson(Map? json) {
    final data = json ?? const {};
    final history = (data['history'] as List? ?? const [])
        .whereType<Map>()
        .map(RewardEntry.fromJson)
        .toList();
    double sum(
      double Function(RewardEntry e) f,
      bool Function(RewardEntry e) w,
    ) => _round2(history.where(w).fold<double>(0, (s, e) => s + f(e)));
    bool orderRows(RewardEntry e) => !e.isClaim;
    return RewardSummary(
      availablePoints: _num(data['availablePoints'] ?? data['totalPoints']),
      totalEarned: data['totalPointsEarned'] != null
          ? _num(data['totalPointsEarned'])
          : sum((e) => e.pointsEarned, orderRows),
      totalRedeemed: data['totalPointsRedeemed'] != null
          ? _num(data['totalPointsRedeemed'])
          : sum((e) => e.pointsRedeemed, (e) => e.status == 'approved'),
      pendingRedemption: data['pendingRedemption'] != null
          ? _num(data['pendingRedemption'])
          : sum((e) => e.pointsRedeemed, (e) => e.status == 'pending'),
      eligiblePurchase: data['eligiblePurchaseAmount'] != null
          ? _num(data['eligiblePurchaseAmount'])
          : sum((e) => e.orderAmount, orderRows),
      threshold: data['freeClaimThreshold'] != null
          ? _num(data['freeClaimThreshold'])
          : kFreeClaimThreshold,
      pointValue: data['pointValueInr'] != null
          ? _num(data['pointValueInr'])
          : 1,
      history: history,
      // Older servers: no flag. Unlocked but canClaim false = not ready yet.
      claimAvailable:
          !(data['canClaim'] == false &&
              data['freeClaimUnlocked'] == true &&
              _num(data['availablePoints'] ?? data['totalPoints']) > 0),
    );
  }
}
