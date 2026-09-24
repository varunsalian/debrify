import 'package:debrify/services/iptv_catalog_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('captures extended SQLite codes without SQL or bound credentials', () {
    final fields = iptvCatalogFailureFields(
      SqliteException(
        2067,
        'UNIQUE constraint failed: private_provider_key',
        'https://provider.example/user/password',
        "INSERT INTO channels VALUES ('private-password')",
        ['private-password'],
      ),
    );
    expect(fields['sqlite_code'], 19);
    expect(fields['sqlite_extended_code'], 2067);
    expect(fields['sqlite_reason'], 'UNIQUE_constraint_failed');
    expect(fields['sql_operation'], 'INSERT');
    expect(fields['statement_id'], matches(RegExp(r'^[a-f0-9]{12}$')));
    expect(fields.toString(), isNot(contains('private')));
    expect(fields.toString(), isNot(contains('provider.example')));
  });

  test('extracts native preparation lock errors', () {
    final fields = iptvCatalogFailureFields(
      StateError('IPTV catalog SQL failed (5): database is locked'),
    );
    expect(fields['sqlite_code'], 5);
    expect(fields['sqlite_reason'], 'database_is_locked');
  });

  test('omits unrecognized messages and non-SQLite error content', () {
    expect(iptvCatalogFailureFields(SqliteException(1, 'secret-token')), {
      'error_type': 'SqliteException',
      'sqlite_code': 1,
      'sqlite_extended_code': 1,
    });
    expect(iptvCatalogFailureFields(StateError('https://user:password@host')), {
      'error_type': 'StateError',
    });
  });
}
