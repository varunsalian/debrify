import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:debrify/services/launch_animation/launch_animation_library.dart';
import 'package:debrify/services/launch_animation/launch_package.dart';
import 'launch_package_test.dart' show packageBytes;

class TrackedAnimation extends LoadedLaunchAnimation {
  TrackedAnimation()
    : super(
        LottieComposition.parseJsonBytes(
          LaunchPackage.decode(packageBytes()).prepare('main').json,
        ),
        0xff000000,
        [],
      );
  bool disposed = false;
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  test('successful load is returned and owned by caller', () async {
    final animation = TrackedAnimation();
    expect(
      await loadLaunchAnimationForStartup(
        () async => animation,
        isCurrent: () => true,
      ),
      same(animation),
    );
    expect(animation.disposed, isFalse);
    animation.dispose();
  });
  test('load failure chooses fallback', () async {
    expect(
      await loadLaunchAnimationForStartup(
        () async => throw StateError('bad file'),
        isCurrent: () => true,
      ),
      isNull,
    );
  });
  test(
    'timeout chooses fallback and disposes a later successful result',
    () async {
      final pending = Completer<LoadedLaunchAnimation>();
      final animation = TrackedAnimation();
      expect(
        await loadLaunchAnimationForStartup(
          () => pending.future,
          isCurrent: () => true,
          deadline: const Duration(milliseconds: 1),
        ),
        isNull,
      );
      pending.complete(animation);
      await Future<void>.delayed(Duration.zero);
      expect(animation.disposed, isTrue);
    },
  );
  test('disposal or profile change during loading discards result', () async {
    var current = true;
    final pending = Completer<LoadedLaunchAnimation>();
    final result = loadLaunchAnimationForStartup(
      () => pending.future,
      isCurrent: () => current,
    );
    current = false;
    final animation = TrackedAnimation();
    pending.complete(animation);
    expect(await result, isNull);
    expect(animation.disposed, isTrue);
  });
  test('late load errors after timeout are consumed', () async {
    final pending = Completer<LoadedLaunchAnimation>();
    expect(
      await loadLaunchAnimationForStartup(
        () => pending.future,
        isCurrent: () => true,
        deadline: const Duration(milliseconds: 1),
      ),
      isNull,
    );
    pending.completeError(StateError('late'));
    await Future<void>.delayed(Duration.zero);
  });
}
