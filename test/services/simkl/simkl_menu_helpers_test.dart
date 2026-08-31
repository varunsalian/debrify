import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/services/simkl/simkl_service.dart';

Set<SimklItemMenuAction> _actions(List<SimklMenuOption> options) =>
    options.map((option) => option.action).toSet();

void main() {
  test('disconnected Simkl has no actions', () {
    expect(buildSimklMenuOptions(), isEmpty);
  });

  test('an untracked movie offers statuses but no removal', () {
    final actions = _actions(buildSimklMenuOptions(isSimklAuthenticated: true));

    expect(actions, contains(SimklItemMenuAction.moveToPlanToWatch));
    expect(actions, contains(SimklItemMenuAction.moveToCompleted));
    expect(actions, contains(SimklItemMenuAction.moveToDropped));
    expect(actions, isNot(contains(SimklItemMenuAction.moveToWatching)));
    expect(actions, isNot(contains(SimklItemMenuAction.moveToOnHold)));
    expect(actions, isNot(contains(SimklItemMenuAction.removeFromList)));
  });

  test('a tracked movie can move status or toggle the active status off', () {
    final actions = _actions(
      buildSimklMenuOptions(
        isSimklAuthenticated: true,
        status: const SimklTitleStatus(currentStatus: 'plantowatch'),
      ),
    );

    expect(actions, isNot(contains(SimklItemMenuAction.moveToPlanToWatch)));
    expect(actions, contains(SimklItemMenuAction.moveToCompleted));
    expect(actions, contains(SimklItemMenuAction.moveToDropped));
    expect(actions, contains(SimklItemMenuAction.removeFromList));
  });

  test('a tracked series keeps all exclusive destinations plus removal', () {
    final actions = _actions(
      buildSimklMenuOptions(
        isSeries: true,
        isSimklAuthenticated: true,
        status: const SimklTitleStatus(currentStatus: 'watching'),
      ),
    );

    expect(actions, isNot(contains(SimklItemMenuAction.moveToWatching)));
    expect(actions, contains(SimklItemMenuAction.moveToPlanToWatch));
    expect(actions, contains(SimklItemMenuAction.moveToOnHold));
    expect(actions, contains(SimklItemMenuAction.moveToCompleted));
    expect(actions, contains(SimklItemMenuAction.moveToDropped));
    expect(actions, contains(SimklItemMenuAction.removeFromList));
  });
}
