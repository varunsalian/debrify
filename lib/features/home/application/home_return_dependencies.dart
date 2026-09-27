import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_return_repository.dart';

/// Consumption precedes catalog-session bootstrap. Provider disposal does not
/// dispose the borrowed process cache or invalidate a completed return snapshot.
final homeReturnRepositoryProvider = Provider.autoDispose
    .family<HomeReturnRepository, ProfileSessionOwner>(
      (ref, owner) => HomeReturnRepository(owner: owner),
      retry: (count, error) => null,
    );
