import 'package:flutter_test/flutter_test.dart';
import 'package:ro_wholesale_dealer_app/features/admin/data/supabase_admin_dealer_approval_route.dart';

void main() {
  group('mapSupabaseAdminDealerApprovalRequest', () {
    test('maps the existing approval action and normalizes status', () {
      expect(
        mapSupabaseAdminDealerApprovalRequest(
          'set-status',
          method: 'POST',
          data: {'identifier': 'dealer@example.test', 'status': 'APPROVED'},
        )?.toJson(),
        {'identifier': 'dealer@example.test', 'status': 'approved'},
      );
      expect(
        mapSupabaseAdminDealerApprovalRequest(
          '/set-status/',
          method: 'POST',
          data: {'email': ' dealer@example.test ', 'status': 'pending'},
        )?.toJson(),
        {'identifier': 'dealer@example.test', 'status': 'pending'},
      );
    });

    test('leaves unsupported, malformed, and other routes on Express', () {
      expect(
        mapSupabaseAdminDealerApprovalRequest(
          'set-status',
          method: 'GET',
          data: {'identifier': 'dealer@example.test', 'status': 'approved'},
        ),
        isNull,
      );
      expect(
        mapSupabaseAdminDealerApprovalRequest(
          'set-status',
          method: 'POST',
          data: {'identifier': '', 'status': 'approved'},
        ),
        isNull,
      );
      expect(
        mapSupabaseAdminDealerApprovalRequest(
          'set-status',
          method: 'POST',
          data: {'identifier': 'dealer@example.test', 'status': 'admin'},
        ),
        isNull,
      );
      expect(
        mapSupabaseAdminDealerApprovalRequest(
          'users/dealer-1',
          method: 'DELETE',
          data: null,
        ),
        isNull,
      );
    });
  });
}
