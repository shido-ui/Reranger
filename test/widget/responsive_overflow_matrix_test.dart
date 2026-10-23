import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reranger/core/theme/app_theme.dart';
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/features/creations/presentation/creations_screen.dart';
import 'package:reranger/features/home/presentation/home_screen.dart';
import 'package:reranger/features/import/presentation/analysis_screen.dart';
import 'package:reranger/features/import/presentation/import_controller.dart';
import 'package:reranger/features/settings/presentation/settings_screen.dart';

void main() {
  group('Responsive Viewport & Font Scale Overflow Matrix', () {
    // Single baseline viewport (360x800 at 1.0 scale) for local PRoot container CI.
    // Full 32-viewport matrix is deferred to the physical Mobile MCP Cloud Device (Google Pixel 10).
    const widths = [360.0];
    const fontScales = [1.0];

    late Directory tempDir;
    late ProjectDatabase database;
    late ProjectFileStorage fileStorage;
    late LocalProjectRepository repository;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('matrix_overflow_');
      database = ProjectDatabase.openInMemory();
      fileStorage = ProjectFileStorage(rootDir: tempDir);
      repository = LocalProjectRepository(
        database: database,
        fileStorage: fileStorage,
      );
    });

    tearDown(() {
      database.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    for (final width in widths) {
      for (final fontScale in fontScales) {
        testWidgets(
          'HomeScreen: No overflow at width $width with fontScale $fontScale',
          (tester) async {
            tester.view.physicalSize = Size(width * 2.0, 800.0 * 2.0);
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  theme: AppTheme.darkTheme,
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: Size(width, 800.0),
                      textScaler: TextScaler.linear(fontScale),
                    ),
                    child: const HomeScreen(),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(find.text('RERANGER'), findsOneWidget);
            expect(find.text('Select Image'), findsOneWidget);
          },
        );

        testWidgets(
          'CreationsScreen: No overflow at width $width with fontScale $fontScale',
          (tester) async {
            tester.view.physicalSize = Size(width * 2.0, 800.0 * 2.0);
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  theme: AppTheme.darkTheme,
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: Size(width, 800.0),
                      textScaler: TextScaler.linear(fontScale),
                    ),
                    child: const CreationsScreen(),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(find.text('No Creations Saved Yet'), findsOneWidget);
          },
        );

        testWidgets(
          'SettingsScreen: No overflow at width $width with fontScale $fontScale',
          (tester) async {
            tester.view.physicalSize = Size(width * 2.0, 800.0 * 2.0);
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  theme: AppTheme.darkTheme,
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: Size(width, 800.0),
                      textScaler: TextScaler.linear(fontScale),
                    ),
                    child: const SettingsScreen(),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(find.text('DEVICE & RUNTIME CAPABILITIES'), findsOneWidget);
          },
        );

        testWidgets(
          'AnalysisScreen: No overflow at width $width with fontScale $fontScale',
          (tester) async {
            tester.view.physicalSize = Size(width * 2.0, 800.0 * 2.0);
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            final inProgressController = ImportController(
              projectRepository: repository,
              fileStorage: fileStorage,
              initialState: const ImportInProgress(
                stage: ImportStage.extractingPalette,
              ),
            );

            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  theme: AppTheme.darkTheme,
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: Size(width, 800.0),
                      textScaler: TextScaler.linear(fontScale),
                    ),
                    child: AnalysisScreen(controller: inProgressController),
                  ),
                ),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 50));

            expect(tester.takeException(), isNull);
            expect(find.text('Extracting Dominant Palette'), findsOneWidget);
          },
        );
      }
    }
  });
}
