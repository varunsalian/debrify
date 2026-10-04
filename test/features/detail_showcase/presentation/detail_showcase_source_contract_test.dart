import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/detail_showcase_source.dart';

String flat(String text) => text.replaceAll(RegExp(r'\s+'), '');

void main() {
  test(
    'manifest reader covers every original leaf exactly once and completion is gated',
    () {
      final rows = showcaseManifest();
      expect(rows, hasLength(69));
      for (final row in rows) {
        expect(
          () => showcaseDeclaration(row['original_name']!),
          returnsNormally,
        );
        expect(showcaseDeclaration(row['original_name']!), isNotEmpty);
      }
      if (showcaseComplete) {
        for (final path in rows.map((r) => r['destination_file']!).toSet()) {
          expect(File(path).existsSync(), isTrue);
        }
        expect(
          RegExp(
            r'^class ',
            multiLine: true,
          ).hasMatch(File(showcaseFacade).readAsStringSync()),
          isFalse,
        );
      }
    },
  );

  test(
    'primary eagerly owns hold with ordered disposal and live widget callbacks',
    () {
      final body = flat(showcaseDeclaration('_PrimaryState'));
      expect(body, contains('latefinalTvHoldOk_hold;'));
      expect(
        body,
        contains('voidinitState(){super.initState();_hold=TvHoldOk('),
      );
      expect(
        body,
        contains(
          'onTap:()=>widget.onTap(),onHold:()=>widget.onLongPress?.call(),',
        ),
      );
      expect(body, contains('voiddispose(){_hold.reset();super.dispose();}'));
      expect(body, contains('if(!v)_hold.reset();'));
      expect(body, contains('autofocus:true,'));
      expect(
        body,
        contains(
          'widget.onLongPress==null||!isActivateOrSpaceKey(event.logicalKey)',
        ),
      );
      expect(
        body,
        contains('HapticFeedback.mediumImpact();widget.onLongPress?.call();'),
      );
    },
  );

  test(
    'identity forwards trailer and primary objects and preserves mounting conditions',
    () {
      final body = flat(showcaseDeclaration('ShowcaseIdentity'));
      expect(body, contains('if(m.hasTrailer&&i<actionNodes.length)'));
      expect(body, contains("label:'Trailer',onTap:m.onTrailer,"));
      expect('onTap:m.onPrimary,'.allMatches(body), hasLength(2));
      expect(
        'onLongPress:m.onPrimaryLongPress,'.allMatches(body),
        hasLength(2),
      );
    },
  );

  test(
    'guide identity guard re-seats selection and resets each reveal state',
    () {
      final body = flat(showcaseDeclaration('_ShowcaseGuideState'));
      expect(body, contains('if(!identical(oldWidget.guide,widget.guide))'));
      expect(
        body,
        contains('finalfocused=widget.nodes.indexWhere((n)=>n.hasFocus);'),
      );
      expect(
        body,
        contains(
          '_sel=focused>=0?focused.clamp(0,_cats.length-1):0;_spoilers=false;_open=-1;_openSpoilers.clear();',
        ),
      );
      expect(
        flat(showcaseDeclaration('_GuideCardState')),
        contains('widget.onSelect();_keepVisible(context);'),
      );
    },
  );

  test(
    'hover and nearest horizontal visibility preserve platform and axis guards',
    () {
      expect(
        flat(showcaseDeclaration('_HoverState')),
        contains(
          'if(PlatformUtil.isTelevision)returnwidget.builder(context,false);',
        ),
      );
      final visible = flat(showcaseDeclaration('_keepVisible'));
      expect(
        visible,
        contains('if(scrollable.position.axis!=Axis.horizontal)return;'),
      );
      expect(
        visible,
        contains(
          'alignment:0.5,duration:constDuration(milliseconds:220),curve:Curves.easeOutCubic,',
        ),
      );
      expect(
        showcaseDeclaration('_CircleState'),
        contains('child: MouseRegion('),
      );
      expect(
        showcaseDeclaration('_RetryChipState'),
        isNot(contains('_keepVisible(')),
      );
    },
  );

  test('topology literals and cache and fade constants are frozen', () {
    expect(
      flat(showcaseDeclaration('ShowcaseSources')),
      contains('itemCount:2+(onBrowseAll!=null?1:0),'),
    );
    expect(
      flat(showcaseDeclaration('ShowcaseSeasons')),
      contains('node:nodes.first'),
    );
    expect(
      flat(showcaseDeclaration('ShowcaseSeasons')),
      contains('height:34*m.k'),
    );
    expect(
      flat(showcaseDeclaration('ShowcaseDidYouKnow')),
      contains('itemCount:entries.length+(hasMore?1:0)'),
    );
    expect(
      flat(showcaseDeclaration('ShowcaseMetrics')),
      contains('doublegetk=>(compact||!touch)?1.0:wideTouchScale(w);'),
    );
    expect(
      showcaseDeclaration('ShowcaseAmbient'),
      contains('memCacheWidth: 32'),
    );
    expect(showcaseDeclaration('ShowcaseAmbient'), contains('alpha: 0.58'));
    expect(
      showcaseDeclaration('ShowcaseAmbient'),
      contains('milliseconds: 550'),
    );
    expect(
      showcaseDeclaration('ShowcaseStickyLogo'),
      contains('memCacheWidth: (420 * m.k).round()'),
    );
    expect(showcaseDeclaration('_LogoOrTitle'), contains('memCacheWidth: 520'));
    expect(
      showcaseDeclaration('ShowcaseBackdropScrim'),
      contains('milliseconds: 550'),
    );
    expect(
      showcaseDeclaration('ShowcaseStickyLogo'),
      contains('milliseconds: 400'),
    );
    final dropdown = flat(showcaseDeclaration('_SeasonDropdownState'));
    expect(dropdown, contains('awaitshowMenu<int>('));
    expect(
      dropdown,
      contains('if(selected!=null)widget.view.selectSeason(selected);'),
    );
    expect(dropdown, isNot(contains('mounted')));
  });

  test(
    'feature and facade scan forbids playback engines and owned resources unconditionally',
    () {
      for (final entry in showcasePhysicalFiles().entries) {
        expect(
          entry.value,
          isNot(
            matches(
              RegExp(
                r"import .*?(media_kit|hero_trailer_backdrop|video_player_launcher|player_launch)",
              ),
            ),
          ),
          reason: entry.key,
        );
        expect(
          entry.value,
          isNot(
            matches(RegExp(r'\b(?:FocusNode|Timer|[A-Za-z]+Controller)\s*\(')),
          ),
          reason: entry.key,
        );
        expect(entry.value, isNot(contains('KeepAlive')), reason: entry.key);
        expect(
          entry.value,
          isNot(matches(RegExp(r'\b(?:node|nodes\[[^]]+\])\.dispose\('))),
          reason: entry.key,
        );
      }
    },
  );

  test(
    'source mapper retains comment and literal spelling but reverses code interpolation aliases',
    () {
      const text =
          r'// _t _ink'
          '\n'
          r'final text = "_t ${_ink}";';
      expect(showcaseOriginalNames(text), text);
    },
  );
}
