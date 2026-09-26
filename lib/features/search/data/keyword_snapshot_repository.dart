import '../models/keyword_snapshot.dart';

abstract interface class KeywordSnapshotRepository {
  KeywordSnapshot? take(String variant, {required bool allowed});
  void store(KeywordSnapshot snapshot);
}
