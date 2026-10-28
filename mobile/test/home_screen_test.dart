import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myos_mobile/src/app.dart';
import 'package:myos_mobile/src/core/app_mode.dart';
import 'package:myos_mobile/src/core/active_workout.dart';
import 'package:myos_mobile/src/core/display_language/controller.dart';
import 'package:myos_mobile/src/core/api_client.dart';
import 'package:myos_mobile/src/core/chat_storage.dart';
import 'package:myos_mobile/src/core/models.dart';
import 'package:myos_mobile/src/core/theme/theme_mode_store.dart';
import 'package:myos_mobile/src/core/token_store.dart';
import 'package:myos_mobile/src/core/workout_storage.dart';
import 'package:myos_mobile/src/core/install_prompt_store.dart';
import 'package:myos_mobile/src/features/shared/install_prompt.dart';
import 'package:myos_mobile/src/providers.dart';
import 'package:myos_mobile/src/core/ui/myos_bottom_navigation.dart';
import 'package:myos_mobile/src/features/player/tour/tour_controller.dart';
import 'package:myos_mobile/src/features/player/tour/tour_targets.dart';
import 'package:myos_mobile/src/features/player/workout/active_workout_controller.dart';
import 'package:myos_mobile/src/router.dart';

import 'support/fake_myos_api.dart';
import 'support/fake_analytics_client.dart';
import 'support/fake_tour_seen_retry_store.dart';

class _FakeInstallPromptStore implements InstallPromptStore {
  _FakeInstallPromptStore(this.environment, {this.outcome = 'unavailable'});
  final InstallPromptEnvironment environment;
  final String outcome;
  bool dismissed = false;
  int prompts = 0;
  void Function()? installed;
  void Function()? installStateChanged;
  bool installedBeforeListener = false;
  bool canPersist = true;

  @override
  Future<InstallPromptEnvironment> readEnvironment() async => environment;
  @override
  Future<void> rememberDismissal() async {
    if (canPersist) {
      dismissed = true;
    }
  }
  @override
  Future<String> promptInstall() async {
    prompts++;
    return outcome;
  }
  @override
  void listenForInstalled(void Function() onInstalled) {
    installed = onInstalled;
    if (installedBeforeListener) onInstalled();
  }
  @override
  void listenForInstallState(void Function() onInstallStateChanged) =>
      installStateChanged = onInstallStateChanged;
  @override
  bool consumeInstalled() {
    final bool wasInstalled = installedBeforeListener;
    installedBeforeListener = false;
    return wasInstalled;
  }

  void fireInstallStateChanged() => installStateChanged?.call();

  void fireInstalled() {
    if (installed == null) {
      installedBeforeListener = true;
    } else {
      installed!();
    }
  }
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder,
    {int attempts = 40}) async {
  for (int i = 0; i < attempts; i++) {
    if (finder.evaluate().isNotEmpty) {
      for (int j = 0; j < 4; j++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpHome(
  WidgetTester tester,
  FakeMyosApi fake, {
  ThemeModeStore? themeStore,
  DraftStore? draftStore,
  String languageCode = 'en',
  Size size = const Size(1080, 2400),
  List<Override> extraOverrides = const <Override>[],
  TourSeenRetryStore? tourRetryStore,
}) async {
  fake.displayLanguage = languageCode;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final InMemoryTokenStore tokens = InMemoryTokenStore();
  await tokens.save('token-alice');
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: <Override>[
        installPromptDelayProvider.overrideWithValue(Duration.zero),
        ...extraOverrides,
        tokenStoreProvider.overrideWithValue(tokens),
        appModeStoreProvider.overrideWithValue(InMemoryAppModeStore()),
        themeModeStoreProvider
            .overrideWithValue(themeStore ?? InMemoryThemeModeStore()),
        systemDisplayLanguageProvider.overrideWithValue(languageCode),
        tourSeenRetryStoreProvider.overrideWithValue(
            tourRetryStore ?? FakeTourSeenRetryStore()),
        draftStoreProvider
            .overrideWithValue(draftStore ?? InMemoryDraftStore()),
        workoutCacheStoreProvider
            .overrideWithValue(InMemoryWorkoutCacheStore()),
        activeWorkoutStoreProvider
            .overrideWithValue(InMemoryActiveWorkoutStore()),
        chatCacheStoreProvider.overrideWithValue(InMemoryChatCacheStore()),
        apiClientProvider.overrideWith((ref) {
          final ApiClient client = ApiClient(
            tokens: ref.watch(tokenStoreProvider),
            baseUrl: 'http://test.local',
            adapter: fake.adapter,
          );
          client.onUnauthorized = ref.watch(unauthorizedEventsProvider).signal;
          return client;
        }),
      ],
      child: const MyosApp(),
    ),
  );
  await _pumpUntilFound(
      tester, find.text(languageCode == 'ar' ? 'الرئيسية' : 'Home'));
}

FakeMyosApi _signedInFake() {
  final FakeMyosApi fake = FakeMyosApi();
  fake.issuedToken = 'token-alice';
  fake.currentUsername = 'alice';
  fake.tokenValid = true;
  fake.profileExists = true;
  fake.recoveryEmail = 'alice@example.com';
  return fake;
}

void main() {
  testWidgets('eligible install dialog waits for its injected delay', (tester) async {
    final _FakeInstallPromptStore store = _FakeInstallPromptStore(
      const InstallPromptEnvironment(
        isIosShareBrowser: false,
        hasInstallButton: true,
        isStandalone: false,
        wasDismissed: false,
      ),
    );
    await _pumpHome(
      tester,
      _signedInFake(),
      size: const Size(360, 640),
      extraOverrides: <Override>[
        installPromptStoreProvider.overrideWithValue(store),
        installPromptDelayProvider.overrideWithValue(
          const Duration(milliseconds: 1500),
        ),
      ],
    );
    expect(find.text('Install'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Install'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog close affordances dismiss and record the prompt', (tester) async {
    for (final String path in <String>['not now', 'close', 'barrier', 'back']) {
      final FakeAnalyticsClient analytics = FakeAnalyticsClient();
      final _FakeInstallPromptStore store = _FakeInstallPromptStore(
        const InstallPromptEnvironment(
          isIosShareBrowser: false,
          hasInstallButton: true,
          isStandalone: false,
          wasDismissed: false,
        ),
      );
      await _pumpHome(tester, _signedInFake(), extraOverrides: <Override>[
        installPromptStoreProvider.overrideWithValue(store),
        analyticsClientProvider.overrideWithValue(analytics),
      ]);
      await tester.pump(const Duration(milliseconds: 1500));
      switch (path) {
        case 'not now':
          await tester.tap(find.text('Not now'));
        case 'close':
          await tester.tap(find.byTooltip('Dismiss'));
        case 'barrier':
          await tester.tapAt(const Offset(2, 2));
        case 'back':
          await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(store.dismissed, isTrue, reason: path);
      expect(find.text('Install'), findsNothing, reason: path);
      expect(
        analytics.events.any((event) => event['event'] == 'install_prompt_dismissed'),
        isTrue,
        reason: path,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Home shows install variants and reports shown analytics', (tester) async {
    final FakeMyosApi fake = _signedInFake();
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    final _FakeInstallPromptStore store = _FakeInstallPromptStore(
      const InstallPromptEnvironment(
        isIosShareBrowser: false,
        hasInstallButton: true,
        isStandalone: false,
        wasDismissed: false,
      ),
    );
    await _pumpHome(tester, fake, extraOverrides: <Override>[
      installPromptStoreProvider.overrideWithValue(store),
      analyticsClientProvider.overrideWithValue(analytics),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Install'), findsOneWidget);
    expect(analytics.events.any((event) => event['event'] == 'install_prompt_shown'), isTrue);
  });

  testWidgets('storage failure still hides a dismissed prompt this visit', (tester) async {
    const InstallPromptEnvironment eligible = InstallPromptEnvironment(
      isIosShareBrowser: true,
      hasInstallButton: false,
      isStandalone: false,
      wasDismissed: false,
    );
    final _FakeInstallPromptStore store = _FakeInstallPromptStore(eligible)
      ..canPersist = false;
    await _pumpHome(tester, _signedInFake(), extraOverrides: <Override>[
      installPromptStoreProvider.overrideWithValue(store),
    ]);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.textContaining('tap Share'), findsNothing);
    store.fireInstallStateChanged();
    await tester.pump();
    expect(find.textContaining('tap Share'), findsNothing);
  });

  testWidgets('iOS hint dismisses for this visit and records dismissal', (tester) async {
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    final _FakeInstallPromptStore store = _FakeInstallPromptStore(
      const InstallPromptEnvironment(
        isIosShareBrowser: true,
        hasInstallButton: false,
        isStandalone: false,
        wasDismissed: false,
      ),
    );
    await _pumpHome(tester, _signedInFake(), extraOverrides: <Override>[
      installPromptStoreProvider.overrideWithValue(store),
      analyticsClientProvider.overrideWithValue(analytics),
    ]);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('1  Tap Share'), findsOneWidget);
    expect(find.text('2  Add to Home Screen'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(store.dismissed, isTrue);
    expect(find.text('1  Tap Share'), findsNothing);
    expect(analytics.events.any((event) => event['event'] == 'install_prompt_dismissed'), isTrue);
  });

  testWidgets('cancelling the browser dialog counts as dismissal', (tester) async {
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    final _FakeInstallPromptStore store = _FakeInstallPromptStore(
      const InstallPromptEnvironment(
        isIosShareBrowser: false,
        hasInstallButton: true,
        isStandalone: false,
        wasDismissed: false,
      ),
      outcome: 'dismissed',
    );
    await _pumpHome(tester, _signedInFake(), extraOverrides: <Override>[
      installPromptStoreProvider.overrideWithValue(store),
      analyticsClientProvider.overrideWithValue(analytics),
    ]);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();
    expect(store.prompts, 1);
    expect(store.dismissed, isTrue);
    expect(analytics.events.any((event) => event['event'] == 'install_prompt_dismissed'), isTrue);
  });

  testWidgets('accepting the browser dialog hides the prompt and is tracked', (tester) async {
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    final _FakeInstallPromptStore store = _FakeInstallPromptStore(
      const InstallPromptEnvironment(
        isIosShareBrowser: false,
        hasInstallButton: true,
        isStandalone: false,
        wasDismissed: false,
      ),
      outcome: 'accepted',
    );
    await _pumpHome(tester, _signedInFake(), extraOverrides: <Override>[
      installPromptStoreProvider.overrideWithValue(store),
      analyticsClientProvider.overrideWithValue(analytics),
    ]);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();
    expect(store.prompts, 1);
    expect(store.dismissed, isFalse);
    expect(find.text('Install'), findsNothing);
    expect(analytics.events.any((event) => event['event'] == 'install_prompt_accepted'), isTrue);
  });

  testWidgets('install events respect the analytics opt-out gate', (tester) async {
    final FakeMyosApi fake = _signedInFake()..analyticsAllowed = false;
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    final _FakeInstallPromptStore store = _FakeInstallPromptStore(
      const InstallPromptEnvironment(
        isIosShareBrowser: true,
        hasInstallButton: false,
        isStandalone: false,
        wasDismissed: false,
      ),
    );
    await _pumpHome(tester, fake, extraOverrides: <Override>[
      installPromptStoreProvider.overrideWithValue(store),
      analyticsClientProvider.overrideWithValue(analytics),
    ]);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(analytics.events, isEmpty);
  });

  testWidgets('Arabic install hint is localized and app installation is tracked', (tester) async {
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    final _FakeInstallPromptStore store = _FakeInstallPromptStore(
      const InstallPromptEnvironment(
        isIosShareBrowser: true,
        hasInstallButton: false,
        isStandalone: false,
        wasDismissed: false,
      ),
    );
    await _pumpHome(tester, _signedInFake(), languageCode: 'ar', extraOverrides: <Override>[
      installPromptStoreProvider.overrideWithValue(store),
      analyticsClientProvider.overrideWithValue(analytics),
    ]);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('١  اضغط على مشاركة'), findsOneWidget);
    expect(find.text('٢  اختر إضافة إلى الشاشة الرئيسية'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('الرئيسية'))), TextDirection.rtl);
    store.fireInstalled();
    await tester.pump();
    expect(analytics.events.any((event) => event['event'] == 'app_installed'), isTrue);
    expect(find.text('١  اضغط على مشاركة'), findsNothing);
  });

  testWidgets('installation before Dart startup is consumed with no variant', (tester) async {
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    final _FakeInstallPromptStore store = _FakeInstallPromptStore(
      const InstallPromptEnvironment(
        isIosShareBrowser: false,
        hasInstallButton: false,
        isStandalone: false,
        wasDismissed: false,
      ),
    )..installedBeforeListener = true;
    await _pumpHome(tester, _signedInFake(), extraOverrides: <Override>[
      installPromptStoreProvider.overrideWithValue(store),
      analyticsClientProvider.overrideWithValue(analytics),
    ]);
    await tester.pump();
    expect(analytics.events.where((event) => event['event'] == 'app_installed'), hasLength(1));
    expect(
      (analytics.events.singleWhere((event) => event['event'] == 'app_installed')['properties']
          as Map<String, Object>)['variant'],
      'none',
    );
    expect(find.text('Install MYOS'), findsNothing);
  });

  testWidgets(
      'Arabic Home labels use RTL while server program names stay as sent',
      (tester) async {
    final FakeMyosApi fake = _signedInFake();
    await _pumpHome(tester, fake, languageCode: 'ar');
    await _pumpUntilFound(tester, find.textContaining('محسوبة لكل عضلة'));

    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('لا يوجد برنامج تدريبي نشط'), findsNothing);
    expect(find.text('Upper/Lower 4x'), findsOneWidget);
    expect(find.text('Upper/Lower · 4 أيام في الأسبوع'), findsOneWidget);
    expect(find.textContaining('محسوبة لكل عضلة'), findsOneWidget);
    expect(
      find.text('تُحسب مجموعة التدريب بقيمة 1 للعضلة الأساسية و0.5 لكل عضلة مساعدة.'),
      findsOneWidget,
    );
    expect(
      Directionality.of(tester.element(find.text('الرئيسية'))),
      TextDirection.rtl,
    );
  });

  testWidgets('Arabic Home translates the pending workout draft banner',
      (WidgetTester tester) async {
    final FakeMyosApi fake = _signedInFake();
    final InMemoryDraftStore drafts = InMemoryDraftStore();
    await drafts.write('account-alice', <WorkoutDraft>[
      const WorkoutDraft(
        clientSessionId: 'draft-1',
        accountId: 'account-alice',
        performedDate: '2026-10-02',
        performedTimezone: 'UTC',
        programVersion: 1,
        dayOrder: 1,
        dayName: 'Upper 1',
        capturedAt: '2026-10-02T10:00:00Z',
        exercises: <DraftExercise>[],
        readiness: 4,
        updatedAt: '2026-10-02T10:00:00Z',
        attempt: 1,
        nextAttemptAt: '2099-01-01T00:00:00Z',
      ),
    ]);
    await _pumpHome(
      tester,
      fake,
      languageCode: 'ar',
      draftStore: drafts,
    );
    await _pumpUntilFound(
      tester,
      find.text('مسودة تدريبية واحدة بانتظار المزامنة'),
    );

    expect(find.text('مسودة تدريبية واحدة بانتظار المزامنة'), findsOneWidget);
  });

  testWidgets('home maps the active program, volume, and records',
      (tester) async {
    final FakeMyosApi fake = _signedInFake();
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpHome(tester, fake);

    expect(find.text('Upper/Lower 4x'), findsOneWidget);
    expect(find.text('Upper/Lower · 4 days/week'), findsOneWidget);

    // The weekly schedule (Mon/Wed/Fri) drives the next-session label.
    expect(find.textContaining('Next session ·'), findsOneWidget);

    // Volume muscles and a personal record are real values.
    expect(find.text('Chest'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('120 kg × 5'), findsOneWidget);
  });

  testWidgets('Tour walks all seven stops then marks completion seen',
      (tester) async {
    final FakeMyosApi fake = _signedInFake()..tourSeenVersion = 0;
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    await _pumpHome(tester, fake, extraOverrides: <Override>[
      analyticsClientProvider.overrideWithValue(analytics),
    ]);
    await _pumpUntilFound(tester, find.text('1 OF 7'));
    final ProviderContainer container =
        ProviderScope.containerOf(tester.element(find.byType(MyosApp)));
    expect(container.read(authControllerProvider).session?.account.tourSeenVersion, 0);
    expect(container.read(activeWorkoutControllerProvider).ready, isTrue);
    expect(container.read(playerChatStreamingProvider), isFalse);
    expect(find.text('Home'), findsWidgets);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('2 OF 7'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('tour_back')));
    await tester.pumpAndSettle();
    expect(find.text('1 OF 7'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('2 OF 7'), findsOneWidget);
    for (int step = 3; step <= 7; step++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('$step OF 7'), findsOneWidget);
    }
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(fake.tourSeenVersion, 1);
    expect(container.read(authControllerProvider).session?.account.tourSeenVersion, 1);
    expect(analytics.events.map((event) => event['event']), contains('tour_completed'));

    await _pumpHome(tester, fake);
    await tester.pumpAndSettle();
    expect(find.text('1 OF 7'), findsNothing);
  });

  testWidgets('Arabic Tour follows all seven stops across real tabs and routes',
      (tester) async {
    final FakeMyosApi fake = _signedInFake()..tourSeenVersion = 0;
    await _pumpHome(tester, fake, languageCode: 'ar');
    const List<String> titles = <String>[
      'الرئيسية', 'البرنامج التدريبي', 'المساعد', 'التغذية', 'التقدم',
      'الملف الشخصي', 'دليل الميزات',
    ];
    final ProviderContainer container =
        ProviderScope.containerOf(tester.element(find.byType(MyosApp)));
    final router = container.read(routerProvider);
    for (int index = 0; index < titles.length; index++) {
      await _pumpUntilFound(tester, find.text(titles[index]));
      expect(find.text(titles[index]), findsWidgets);
      if (index == 1) expect(container.read(playerShellTabProvider), 1);
      if (index == 2) expect(container.read(playerShellTabProvider), 0);
      if (index == 3) expect(container.read(playerShellTabProvider), 2);
      if (index == 4) expect(container.read(playerShellTabProvider), 3);
      if (index >= 5) expect(router.routeInformationProvider.value.uri.path, profilePath);
      if (index < titles.length - 1) {
        await tester.tap(find.byKey(const ValueKey<String>('tour_next')));
        await tester.pumpAndSettle();
      }
    }
    await tester.tap(find.byKey(const ValueKey<String>('tour_skip')));
    await tester.pumpAndSettle();
    expect(fake.tourSeenVersion, 1);
  });

  testWidgets('Replay tour leaves seen state untouched and marks replay analytics',
      (tester) async {
    final FakeMyosApi fake = _signedInFake()..tourSeenVersion = 1;
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    await _pumpHome(tester, fake, extraOverrides: <Override>[
      analyticsClientProvider.overrideWithValue(analytics),
    ]);
    final ProviderContainer container =
        ProviderScope.containerOf(tester.element(find.byType(MyosApp)));
    final int writesBefore = fake.tourSeenWriteCount;
    final Future<void> replay = container
        .read(tourControllerProvider.notifier)
        .startTour(1, replay: true);
    await _pumpUntilFound(tester, find.byKey(const ValueKey<String>('tour_skip')));
    await replay;
    await tester.tap(find.byKey(const ValueKey<String>('tour_skip')));
    await tester.pumpAndSettle();
    expect(fake.tourSeenVersion, 1);
    expect(fake.tourSeenWriteCount, writesBefore);
    expect(analytics.events.where((event) =>
        event['event'] == 'tour_started' &&
        (event['properties'] as Map<String, Object>)['replay'] == true), hasLength(1));
    expect(analytics.events.where((event) =>
        event['event'] == 'tour_skipped' &&
        (event['properties'] as Map<String, Object>)['replay'] == true), hasLength(1));
  });

  testWidgets('Tour Skip records seen state and Arabic mirrors Skip',
      (tester) async {
    final FakeMyosApi fake = _signedInFake()..tourSeenVersion = 0;
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    await _pumpHome(tester, fake, languageCode: 'ar', extraOverrides: <Override>[
      analyticsClientProvider.overrideWithValue(analytics),
    ]);
    await _pumpUntilFound(tester, find.text('تخطي'));
    expect(tester.getTopLeft(find.text('تخطي')).dx,
        lessThan(tester.view.physicalSize.width / 2));
    await tester.tap(find.byKey(const ValueKey<String>('tour_next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('tour_skip')), findsOneWidget);
    await tester.tap(find.text('تخطي'));
    await tester.pumpAndSettle();
    expect(fake.tourSeenVersion, 1);
    expect(analytics.events.map((event) => event['event']), contains('tour_skipped'));
  });

  testWidgets('Tour waits for a streaming reply and resumes on Home',
      (tester) async {
    final FakeMyosApi fake = _signedInFake()..tourSeenVersion = 0;
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    await _pumpHome(tester, fake, extraOverrides: <Override>[
      analyticsClientProvider.overrideWithValue(analytics),
      playerChatStreamingProvider.overrideWith((ref) => true),
    ]);
    expect(find.text('1 OF 7'), findsNothing);
    final ProviderContainer container =
        ProviderScope.containerOf(tester.element(find.byType(MyosApp)));
    container.read(playerChatStreamingProvider.notifier).state = false;
    await _pumpUntilFound(tester, find.text('1 OF 7'));
    expect(find.text('1 OF 7'), findsOneWidget);
  });

  testWidgets('Tour pauses for a newly open workout and streaming reply until Home reopens',
      (tester) async {
    final FakeMyosApi fake = _signedInFake()..tourSeenVersion = 0;
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    await _pumpHome(tester, fake, extraOverrides: <Override>[
      analyticsClientProvider.overrideWithValue(analytics),
    ]);
    await _pumpUntilFound(tester, find.byKey(const ValueKey<String>('tour_skip')));
    final ProviderContainer container =
        ProviderScope.containerOf(tester.element(find.byType(MyosApp)));

    final ActiveWorkout workout = ActiveWorkout.fromJson(<String, dynamic>{
      'id': 'tour-workout',
      'account_id': 'account-alice',
      'started_at': '2026-10-28T10:00:00Z',
      'day_order': 1,
      'day_name': 'Upper 1',
      'exercises': <dynamic>[],
      'baselines': <String, dynamic>{},
    });
    container.read(activeWorkoutControllerProvider.notifier).state =
        ActiveWorkoutState(
      accountId: 'account-alice',
      ready: true,
      workout: workout,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey<String>('tour_skip')), findsNothing);
    final int eventCountWhilePaused = analytics.events.length;

    container.read(activeWorkoutControllerProvider.notifier).state =
        const ActiveWorkoutState(
      accountId: 'account-alice',
      ready: true,
      workout: null,
    );
    container.read(playerShellTabProvider.notifier).state = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    container.read(playerShellTabProvider.notifier).state = 0;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await _pumpUntilFound(tester, find.byKey(const ValueKey<String>('tour_skip')));
    expect(analytics.events.length, greaterThan(eventCountWhilePaused));

    container.read(playerChatStreamingProvider.notifier).state = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey<String>('tour_skip')), findsNothing);
    final int eventCountWhileStreaming = analytics.events.length;
    container.read(playerChatStreamingProvider.notifier).state = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey<String>('tour_skip')), findsNothing);
    expect(analytics.events.length, eventCountWhileStreaming);
    container.read(playerShellTabProvider.notifier).state = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    container.read(playerShellTabProvider.notifier).state = 0;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await _pumpUntilFound(tester, find.byKey(const ValueKey<String>('tour_skip')));
    await tester.tap(find.byKey(const ValueKey<String>('tour_skip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('Tour events stay suppressed when analytics is opted out',
      (tester) async {
    final FakeMyosApi fake = _signedInFake()
      ..tourSeenVersion = 0
      ..analyticsAllowed = false;
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    await _pumpHome(tester, fake, extraOverrides: <Override>[
      analyticsClientProvider.overrideWithValue(analytics),
    ]);
    await _pumpUntilFound(tester, find.text('Skip'));
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(analytics.events.where((event) =>
        (event['event'] as String).startsWith('tour_')), isEmpty);
  });

  testWidgets('shell Tour controller can spotlight one feature without marking seen',
      (tester) async {
    final FakeMyosApi fake = _signedInFake();
    await _pumpHome(tester, fake);
    final ProviderContainer container =
        ProviderScope.containerOf(tester.element(find.byType(MyosApp)));

    final Future<void> spotlight =
        container.read(tourControllerProvider.notifier).showMe('home');
    await _pumpUntilFound(tester, find.text('1 OF 7'));
    await spotlight;

    expect(find.text('Home'), findsWidgets);
    expect(fake.tourSeenVersion, 1);
  });

  testWidgets('showMe Program from Profile opens its shell tab target',
      (tester) async {
    final FakeMyosApi fake = _signedInFake();
    await _pumpHome(tester, fake);
    final ProviderContainer container =
        ProviderScope.containerOf(tester.element(find.byType(MyosApp)));
    final router = container.read(routerProvider);
    router.go(profilePath);
    await tester.pumpAndSettle();

    final Future<void> spotlight =
        container.read(tourControllerProvider.notifier).showMe('program');
    await _pumpUntilFound(tester, find.byKey(const ValueKey<String>('tour_next')));
    await spotlight;

    expect(router.routeInformationProvider.value.uri.path, homePath);
    expect(container.read(playerShellTabProvider), 1);
    expect(find.text('Program'), findsWidgets);
    expect(fake.tourSeenVersion, 1);
  });

  testWidgets('showMe Profile from Home targets its route and unregisters on pop',
      (tester) async {
    final FakeMyosApi fake = _signedInFake();
    await _pumpHome(tester, fake);
    final ProviderContainer container =
        ProviderScope.containerOf(tester.element(find.byType(MyosApp)));
    final router = container.read(routerProvider);

    final Future<void> spotlight =
        container.read(tourControllerProvider.notifier).showMe('profile');
    await _pumpUntilFound(tester, find.byKey(const ValueKey<String>('tour_next')));
    await spotlight;
    expect(router.routeInformationProvider.value.uri.path, profilePath);
    expect(find.text('Profile'), findsWidgets);
    expect(fake.tourSeenVersion, 1);

    await tester.tap(find.byKey(const ValueKey<String>('tour_next')));
    await tester.pumpAndSettle();
    router.go(homePath);
    await tester.pumpAndSettle();
    await tester.pump();
    expect(container.read(tourTargetRegistryProvider), isNot(contains('profile')));
  });

  testWidgets('Tour version 2 only reaches accounts created at version 2',
      (tester) async {
    final FakeMyosApi oldAccount = _signedInFake()
      ..tourSeenVersion = 1
      ..tourCreatedVersion = 0;
    await _pumpHome(tester, oldAccount, extraOverrides: <Override>[
      tourCurrentVersionProvider.overrideWithValue(2),
    ], tourRetryStore: FakeTourSeenRetryStore());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('tour_next')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    final FakeMyosApi newAccount = _signedInFake()
      ..tourSeenVersion = 1
      ..tourCreatedVersion = 2;
    await _pumpHome(tester, newAccount, extraOverrides: <Override>[
      tourCurrentVersionProvider.overrideWithValue(2),
    ], tourRetryStore: FakeTourSeenRetryStore());
    await _pumpUntilFound(tester, find.byKey(const ValueKey<String>('tour_next')));
    expect(find.text('1 OF 7'), findsOneWidget);
  });

  testWidgets('Skip dismisses offline and retries the seen write on next Home open',
      (tester) async {
    final FakeMyosApi fake = _signedInFake()
      ..tourSeenVersion = 0
      ..tourSeenWriteFailures = 5;
    final FakeTourSeenRetryStore retryStore = FakeTourSeenRetryStore();
    final FakeAnalyticsClient analytics = FakeAnalyticsClient();
    await _pumpHome(tester, fake, extraOverrides: <Override>[
      analyticsClientProvider.overrideWithValue(analytics),
    ], tourRetryStore: retryStore);
    await _pumpUntilFound(tester, find.byKey(const ValueKey<String>('tour_skip')));

    await tester.tap(find.byKey(const ValueKey<String>('tour_skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('tour_skip')), findsNothing);
    expect(fake.tourSeenVersion, 0);
    expect(analytics.events.map((event) => event['event']), contains('tour_skipped'));
    expect(retryStore.pending.values, contains(1));

    fake.tourSeenWriteFailures = 0;
    final ProviderContainer container =
        ProviderScope.containerOf(tester.element(find.byType(MyosApp)));
    container.read(playerShellTabProvider.notifier).state = 1;
    await tester.pumpAndSettle();
    container.read(playerShellTabProvider.notifier).state = 0;
    await tester.pumpAndSettle();
    expect(fake.tourSeenVersion, 1);
    expect(find.byKey(const ValueKey<String>('tour_skip')), findsNothing);
  });

  testWidgets('Tour tooltip controls remain visible and tappable on a phone',
      (tester) async {
    final FakeMyosApi fake = _signedInFake()..tourSeenVersion = 0;
    await _pumpHome(tester, fake, size: const Size(390, 844));
    await _pumpUntilFound(tester, find.byKey(const ValueKey<String>('tour_next')));

    final Rect nextRect = tester.getRect(find.byKey(const ValueKey<String>('tour_next')));
    final Rect skipRect = tester.getRect(find.byKey(const ValueKey<String>('tour_skip')));
    expect(nextRect.top, greaterThanOrEqualTo(0));
    expect(nextRect.bottom, lessThanOrEqualTo(844));
    expect(skipRect.top, greaterThanOrEqualTo(0));
    expect(skipRect.bottom, lessThanOrEqualTo(844));
    await tester.tap(find.byKey(const ValueKey<String>('tour_next')));
    await tester.pumpAndSettle();
    expect(find.text('2 OF 7'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('tour_skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('tour_skip')), findsNothing);
  });

  testWidgets('home shows honest empty states without data', (tester) async {
    final FakeMyosApi fake = _signedInFake();
    fake.noActiveProgram = true;
    fake.scheduleEmpty = true;
    fake.volumeEmpty = true;
    fake.recordsEmpty = true;
    await _pumpHome(tester, fake);

    expect(find.text('No active program'), findsOneWidget);
    expect(
      find.text('Generate a program to see your next session here.'),
      findsOneWidget,
    );
    expect(find.text('Go to Program'), findsOneWidget);
    // With no program there is no next session at all — not even a placeholder.
    expect(find.text('Next session'), findsNothing);
    expect(find.text('No training day is scheduled yet.'), findsNothing);
    expect(find.text('No sets logged in the last 7 days.'), findsOneWidget);
    expect(find.text('No personal records yet.'), findsOneWidget);
  });

  testWidgets('the Personal records shelf localizes most reps and its value',
      (tester) async {
    for (final String language in <String>['en', 'ar']) {
      final FakeMyosApi fake = _signedInFake()
        ..personalRecordsBody = <Map<String, dynamic>>[
          <String, dynamic>{
            'exercise_id': 'push_up',
            'name': 'Push-up',
            'record_type': 'most_reps',
            'reps': 12,
            'value': 12,
            'prev_value': 8,
            'achieved_at': '2026-09-26T10:00:00Z',
            'session_id': 'session-2',
          },
        ];
      await _pumpHome(tester, fake, languageCode: language);

      expect(
        find.text(language == 'ar' ? 'أكبر عدد من التكرارات' : 'Most reps'),
        findsOneWidget,
      );
      expect(
          find.text(language == 'ar' ? '\u206612\u2069 تكرارًا' : '12 reps'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('the no-program action reaches the assistant from Program',
      (tester) async {
    final FakeMyosApi fake = _signedInFake();
    fake.noActiveProgram = true;
    fake.scheduleEmpty = true;
    fake.volumeEmpty = true;
    fake.recordsEmpty = true;
    await _pumpHome(tester, fake);

    await tester.tap(find.text('Go to Program'));
    await _pumpUntilFound(tester, find.text('Open assistant'));
    expect(find.text('Open assistant'), findsOneWidget);
    expect(find.text('Regenerate program'), findsNothing);

    await tester.tap(find.text('Open assistant'));
    await _pumpUntilFound(tester, find.byKey(const Key('chat_composer')));
    expect(find.byKey(const Key('chat_composer')), findsOneWidget);
  });

  testWidgets('home reads the latest committed session from the ledger',
      (tester) async {
    final FakeMyosApi fake = _signedInFake();
    fake.latestSessionBody = <String, dynamic>{
      'session_id': 'sess-1',
      'session_date': '2026-09-20',
      'split_name': 'Upper 1',
      'day_order': null,
      'program_version': 1,
    };
    await _pumpHome(tester, fake);

    expect(
      fake.adapter.requests
          .any((request) => request.path == '/workouts/sessions/latest'),
      isTrue,
    );
    expect(find.text('Upper 1'), findsOneWidget);
  });

  testWidgets('home opens an unopened Checkpoint review and clears its card',
      (WidgetTester tester) async {
    final FakeMyosApi fake = _signedInFake()
      ..checkpointReviewRows = <Map<String, dynamic>>[
        <String, dynamic>{
          'checkpoint': 10,
          'period_start': '2026-01-01',
          'period_end': '2026-09-30',
          'rating': <Map<String, dynamic>>[
            <String, dynamic>{'part': 'Consistency', 'label': 'Strong'},
          ],
          'opened': false,
        },
      ]
      ..checkpointReviewDetails[10] = <String, dynamic>{
        'checkpoint': 10,
        'period_start': '2026-01-01',
        'period_end': '2026-09-30',
        'facts': <String, dynamic>{'workouts_in_period': 10},
        'rating': <Map<String, dynamic>>[
          <String, dynamic>{'part': 'Consistency', 'label': 'Strong'},
        ],
        'text':
            'Checkpoint 10: 10 workouts since you started logging in MYOS.',
        'text_is_template': true,
      };
    await _pumpHome(tester, fake);

    expect(find.byKey(const ValueKey<String>('dashboard.checkpoint-review')),
        findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('dashboard.checkpoint-review')),
    );
    await _pumpUntilFound(tester, find.text('Your 10th workout'));
    expect(find.text('Consistency'), findsOneWidget);
    expect(find.text('Strong'), findsOneWidget);
    expect(
      find.text(
        'Checkpoint 10: 10 workouts since you started logging in MYOS.',
      ),
      findsOneWidget,
    );

    await tester.pageBack();
    await _pumpUntilFound(
      tester,
      find.byType(MyosBottomNavigation),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('dashboard.checkpoint-review')),
        findsNothing);
  });

  testWidgets('Arabic Checkpoint title keeps its ordinal and date range LTR',
      (WidgetTester tester) async {
    final FakeMyosApi fake = _signedInFake()
      ..checkpointReviewRows = <Map<String, dynamic>>[
        <String, dynamic>{
          'checkpoint': 10,
          'period_start': '2026-01-01',
          'period_end': '2026-09-30',
          'rating': <Map<String, dynamic>>[
            <String, dynamic>{'part': 'Consistency', 'label': 'Strong'},
          ],
          'opened': false,
        },
      ]
      ..checkpointReviewDetails[10] = <String, dynamic>{
        'checkpoint': 10,
        'period_start': '2026-01-01',
        'period_end': '2026-09-30',
        'facts': <String, dynamic>{'workouts_in_period': 10},
        'rating': <Map<String, dynamic>>[
          <String, dynamic>{'part': 'Consistency', 'label': 'Strong'},
        ],
        'text':
            'Checkpoint 10: 10 workouts since you started logging in MYOS.',
        'text_is_template': true,
      };
    await _pumpHome(tester, fake, languageCode: 'ar');
    await tester.tap(
      find.byKey(const ValueKey<String>('dashboard.checkpoint-review')),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('checkpoint.review.title')),
    );

    expect(
      find.byKey(const ValueKey<String>('checkpoint.review.title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('checkpoint.review.checkpoint')),
      findsOneWidget,
    );
    final Text period = tester.widget<Text>(
      find.byKey(const ValueKey<String>('checkpoint.review.period')),
    );
    expect(period.data, '2026-01-01 – 2026-09-30');
    expect(period.textDirection, TextDirection.ltr);
  });

  for (final ThemeMode mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
    testWidgets('home renders in ${mode.name} theme without overflow',
        (tester) async {
      final FakeMyosApi fake = _signedInFake();
      await _pumpHome(
        tester,
        fake,
        themeStore: InMemoryThemeModeStore(mode),
        size: const Size(360, 640),
      );

      // Let the home data and the persisted theme settle before checking for
      // layout overflow at the largest supported text scale.
      await _pumpUntilFound(tester, find.text('Upper/Lower 4x'));
      expect(
        Theme.of(tester.element(find.text('Upper/Lower 4x'))).brightness,
        mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
      );

      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });
  }
}
