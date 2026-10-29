import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/presentation/sports_team_crest.dart';
import 'package:flutter_test/flutter_test.dart';

SportsTeam _player(String name, {String? flag}) => SportsTeam(
  id: name,
  name: name,
  shortName: name,
  abbreviation: name.split(' ').last,
  logoUrl: flag,
);

void main() {
  test('the country code comes from the ESPN flag URL', () {
    expect(
      sportsFlagLabel(
        _player(
          'Alex de Minaur',
          flag: 'https://a.espncdn.com/i/teamlogos/countries/500/aus.png',
        ),
      ),
      'AUS',
    );
  });

  test('without a flag URL, the initials of first and last name', () {
    expect(sportsFlagLabel(_player('Alex de Minaur')), 'AM');
    expect(sportsFlagLabel(_player('Polina Iatcenko')), 'PI');
    expect(sportsFlagLabel(_player('Cher')), 'C');
    expect(sportsFlagLabel(_player('  ')), '');
  });
}
