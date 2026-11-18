import 'package:flutter/material.dart';

import '../../../auth/domain/models/user_model.dart';
import '../../../cart/domain/order_pricing.dart' show formatInr;

const kProfileBlue = Color(0xFF0B5FC4);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE3EAF3);
const _green = Color(0xFF059669);
const _red = Color(0xFFDC2626);

/// Consistent card used by every Profile section.
class ProfileSectionCard extends StatelessWidget {
  const ProfileSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.iconColor = kProfileBlue,
    this.trailing,
    this.isDark = false,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget? trailing;
  final Widget child;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: profileCardDecoration(isDark),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProfileIconBadge(icon: icon, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : _ink,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

BoxDecoration profileCardDecoration(bool isDark) => BoxDecoration(
  color: isDark ? const Color(0xFF132233) : Colors.white,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: isDark ? const Color(0xFF1E2D3D) : _line),
  boxShadow: [
    BoxShadow(
      color: const Color(0xFF0F2850).withValues(alpha: isDark ? 0.25 : 0.05),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ],
);

class ProfileIconBadge extends StatelessWidget {
  const ProfileIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 38,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(size * 0.32),
    ),
    child: Icon(icon, color: color, size: size * 0.52),
  );
}

/// Dealer summary: avatar, name, business, email, mobile, status, Edit.
class ProfileSummaryCard extends StatelessWidget {
  const ProfileSummaryCard({
    super.key,
    required this.user,
    required this.onEdit,
    this.isDark = false,
  });

  final UserModel user;
  final VoidCallback onEdit;
  final bool isDark;

  String get _initials {
    final parts = user.name.trim().split(RegExp(r'\s+'));
    final letters = parts.where((p) => p.isNotEmpty).take(2).map((p) => p[0]);
    final value = letters.join().toUpperCase();
    return value.isEmpty ? '?' : value;
  }

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? Colors.white : _ink;
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 560;
        final avatar = Container(
          width: narrow ? 64 : 76,
          height: narrow ? 64 : 76,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2F80ED), Color(0xFF0B4FB8)],
            ),
          ),
          child: Text(
            _initials,
            style: TextStyle(
              color: Colors.white,
              fontSize: narrow ? 22 : 26,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth - 140),
                  child: Text(
                    user.name.isEmpty ? 'Dealer' : user.name,
                    key: const ValueKey('profile-name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: narrow ? 19 : 22,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
                AccountStatusBadge(status: user.status),
              ],
            ),
            if (user.companyName.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                user.companyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  color: _muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            _ContactLine(icon: Icons.mail_outline_rounded, text: user.email),
            if (user.phoneNumber.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              _ContactLine(icon: Icons.phone_outlined, text: user.phoneNumber),
            ],
          ],
        );
        final edit = OutlinedButton.icon(
          key: const ValueKey('profile-edit'),
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Edit Profile'),
          style: OutlinedButton.styleFrom(
            foregroundColor: kProfileBlue,
            side: const BorderSide(color: Color(0xFFBFD6F2)),
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
        return Container(
          decoration: profileCardDecoration(isDark),
          padding: EdgeInsets.all(narrow ? 18 : 24),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        avatar,
                        const SizedBox(width: 14),
                        Expanded(child: info),
                      ],
                    ),
                    const SizedBox(height: 16),
                    edit,
                  ],
                )
              : Row(
                  children: [
                    avatar,
                    const SizedBox(width: 20),
                    Expanded(child: info),
                    const SizedBox(width: 16),
                    edit,
                  ],
                ),
        );
      },
    );
  }
}

class _ContactLine extends StatelessWidget {
  const _ContactLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: _muted),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, color: _muted),
        ),
      ),
    ],
  );
}

/// Approved / Pending / Rejected badge.
class AccountStatusBadge extends StatelessWidget {
  const AccountStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final (label, fg, bg, icon) = s == 'approved'
        ? ('Approved', _green, const Color(0xFFDCFCE7), Icons.verified_rounded)
        : s == 'rejected'
        ? ('Rejected', _red, const Color(0xFFFEE2E2), Icons.cancel_rounded)
        : (
            s.isEmpty ? 'Pending' : '${s[0].toUpperCase()}${s.substring(1)}',
            const Color(0xFFB45309),
            const Color(0xFFFEF3C7),
            Icons.schedule_rounded,
          );
    return Container(
      key: const ValueKey('profile-status'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reward points total and transaction history (from the backend).
class RewardsCard extends StatefulWidget {
  const RewardsCard({
    super.key,
    required this.totalPoints,
    required this.history,
    this.totalEarned,
    this.isDark = false,
  });

  final int totalPoints;
  final int? totalEarned;
  final List<Map> history;
  final bool isDark;

  @override
  State<RewardsCard> createState() => _RewardsCardState();
}

class _RewardsCardState extends State<RewardsCard> {
  static const _preview = 4;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final history = widget.history;
    final shown = _all ? history : history.take(_preview).toList();
    return ProfileSectionCard(
      title: 'Reward Points',
      icon: Icons.stars_rounded,
      iconColor: const Color(0xFFD97706),
      isDark: widget.isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF7E6), Color(0xFFFFEDD5)],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Available points',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatInr(
                            widget.totalPoints.toDouble(),
                            decimals: false,
                          ).substring(1),
                          key: const ValueKey('reward-total'),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF7C2D12),
                            height: 1.1,
                          ),
                        ),
                      ),
                      if (widget.totalEarned != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${widget.totalEarned} earned from orders',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.workspace_premium_rounded,
                  size: 44,
                  color: Color(0xFFF59E0B),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (history.isEmpty)
            const _EmptyNote(
              'No reward activity yet. Points are earned on every order.',
            )
          else ...[
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: _line),
              _RewardRow(entry: shown[i], isDark: widget.isDark),
            ],
            if (history.length > _preview)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _all = !_all),
                  child: Text(
                    _all
                        ? 'Show less'
                        : 'View all ${history.length} activities',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({required this.entry, required this.isDark});

  final Map entry;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final points =
        num.tryParse('${entry['pointsEarned'] ?? entry['points'] ?? 0}') ?? 0;
    final earned = points >= 0;
    final orderId = '${entry['orderId'] ?? ''}'.trim();
    final description = '${entry['description'] ?? entry['reason'] ?? ''}'
        .trim();
    final title = description.isNotEmpty
        ? description
        : (orderId.isNotEmpty
              ? (earned
                    ? 'Earned on order #$orderId'
                    : 'Redeemed on order #$orderId')
              : 'Reward activity');
    final amount = num.tryParse('${entry['orderAmount'] ?? ''}');
    final date = formatProfileDate(
      '${entry['date'] ?? entry['createdAt'] ?? ''}',
    );
    final subtitle = [
      if (date != null) date,
      if (amount != null && amount > 0) 'Order ${formatInr(amount.toDouble())}',
    ].join('  •  ');
    final color = earned ? _green : _red;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              earned ? Icons.north_east_rounded : Icons.south_west_rounded,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : _ink,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: _muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${earned ? '+' : '−'}${points.abs()} pts',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Available credit with limit / used and a usage bar when the backend
/// provides the limit. Without a configured limit it says so (no made-up
/// figure) and shows the dealer's outstanding amount.
class CreditCard extends StatelessWidget {
  const CreditCard({
    super.key,
    required this.availableCredit,
    this.creditLimit,
    this.outstanding,
    this.isDark = false,
  });

  final double? availableCredit;
  final double? creditLimit;

  /// Unpaid, non-cancelled orders.
  final double? outstanding;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final limit = creditLimit;
    final hasLimit = limit != null && limit > 0 && availableCredit != null;
    if (!hasLimit) {
      return ProfileSectionCard(
        title: 'Credit',
        icon: Icons.account_balance_wallet_rounded,
        iconColor: const Color(0xFF0E7490),
        isDark: isDark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Credit limit not set',
              key: const ValueKey('credit-not-set'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : _ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Your account has no credit limit yet. Contact RO Wholesale to request one.',
              style: TextStyle(fontSize: 13, color: _muted),
            ),
            if (outstanding != null) ...[
              const SizedBox(height: 14),
              _CreditRow(
                'Outstanding (unpaid orders)',
                formatInr(outstanding!),
                isDark,
                bold: true,
              ),
            ],
          ],
        ),
      );
    }
    final available = availableCredit!;
    final used = (limit - available).clamp(0.0, limit).toDouble();
    final usedFraction = used / limit;
    return ProfileSectionCard(
      title: 'Available Credit',
      icon: Icons.account_balance_wallet_rounded,
      iconColor: const Color(0xFF0E7490),
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatInr(available),
              key: const ValueKey('credit-available'),
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : _ink,
              ),
            ),
          ),
          const Text(
            'available to use',
            style: TextStyle(fontSize: 13, color: _muted),
          ),
          ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                key: const ValueKey('credit-progress'),
                value: usedFraction,
                minHeight: 10,
                backgroundColor: const Color(0xFFE0F2F1),
                valueColor: AlwaysStoppedAnimation(
                  usedFraction > 0.8
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF0E9F9A),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _CreditRow('Credit limit', formatInr(limit), isDark),
            _CreditRow(
              'Used (${(usedFraction * 100).toStringAsFixed(0)}%)',
              formatInr(used),
              isDark,
            ),
            _CreditRow('Available', formatInr(available), isDark, bold: true),
          ],
        ],
      ),
    );
  }
}

class _CreditRow extends StatelessWidget {
  const _CreditRow(this.label, this.value, this.isDark, {this.bold = false});

  final String label;
  final String value;
  final bool isDark;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13.5, color: _muted),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: isDark ? Colors.white : _ink,
          ),
        ),
      ],
    ),
  );
}

/// Label / value rows (account information).
class InfoRows extends StatelessWidget {
  const InfoRows({super.key, required this.rows, this.isDark = false});

  final List<(IconData, String, String)> rows;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _EmptyNote('No business details added yet.');
    }
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 20, color: _line),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(rows[i].$1, size: 18, color: _muted),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: Text(
                  rows[i].$2,
                  style: const TextStyle(fontSize: 13.5, color: _muted),
                ),
              ),
              Expanded(
                child: Text(
                  rows[i].$3,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : _ink,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One saved delivery address with its actions menu.
class AddressTile extends StatelessWidget {
  const AddressTile({
    super.key,
    required this.address,
    required this.onAction,
    this.isDark = false,
  });

  final Map address;
  final ValueChanged<String> onAction;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final isDefault = address['isDefault'] == true;
    final label = '${address['label'] ?? address['addressType'] ?? 'Address'}'
        .trim();
    final lines = [
      '${address['street'] ?? ''}',
      '${address['city'] ?? ''}',
      '${address['state'] ?? ''} ${address['pincode'] ?? ''}',
    ].map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      decoration: BoxDecoration(
        color: isDefault
            ? kProfileBlue.withValues(alpha: 0.04)
            : (isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : const Color(0xFFF8FAFC)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDefault ? kProfileBlue.withValues(alpha: 0.35) : _line,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.location_on_outlined,
              size: 20,
              color: kProfileBlue,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      label.isEmpty ? 'Address' : label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : _ink,
                      ),
                    ),
                    if (isDefault)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: kProfileBlue,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Default',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                if (lines.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    lines,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Address actions',
            onSelected: onAction,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (!isDefault)
                const PopupMenuItem(
                  value: 'default',
                  child: Text('Set default'),
                ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

/// GST invoices list (up to [preview], expandable).
class InvoiceList extends StatefulWidget {
  const InvoiceList({super.key, required this.invoices, this.isDark = false});

  final List<Map> invoices;
  final bool isDark;

  @override
  State<InvoiceList> createState() => _InvoiceListState();
}

class _InvoiceListState extends State<InvoiceList> {
  static const _preview = 4;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final invoices = widget.invoices;
    if (invoices.isEmpty) {
      return const _EmptyNote(
        'No GST invoices yet. Choose "With GST" at checkout to get one.',
      );
    }
    final shown = _all ? invoices : invoices.take(_preview).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: _line),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.receipt_long_rounded,
                  size: 20,
                  color: Color(0xFF7C3AED),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${shown[i]['orderId'] != null ? 'Order #${shown[i]['orderId']}' : (shown[i]['invoiceNumber'] ?? 'Invoice')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: widget.isDark ? Colors.white : _ink,
                        ),
                      ),
                      Text(
                        [
                          if ('${shown[i]['date'] ?? ''}'.isNotEmpty)
                            '${shown[i]['date']}',
                          if (num.tryParse('${shown[i]['gstAmount'] ?? ''}')
                              case final g?)
                            'GST ${formatInr(g.toDouble())}',
                        ].join('  •  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: _muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  formatInr(
                    (num.tryParse('${shown[i]['amount'] ?? 0}') ?? 0)
                        .toDouble(),
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: widget.isDark ? Colors.white : _ink,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (invoices.length > _preview)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _all = !_all),
              child: Text(
                _all ? 'Show less' : 'View all ${invoices.length} invoices',
              ),
            ),
          ),
      ],
    );
  }
}

/// A tappable account option row.
class ProfileOptionTile extends StatelessWidget {
  const ProfileOptionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.trailingText,
    this.color = kProfileBlue,
    this.isDark = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final String? trailingText;
  final VoidCallback onTap;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            ProfileIconBadge(icon: icon, color: color, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : _ink,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: _muted),
                    ),
                ],
              ),
            ),
            if (trailingText != null)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  trailingText!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            const Icon(Icons.chevron_right_rounded, color: _muted),
          ],
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13.5, color: _muted, height: 1.4),
    ),
  );
}

/// ISO date → "12 Oct 2026"; already formatted text is returned as is.
String? formatProfileDate(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = date.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}
