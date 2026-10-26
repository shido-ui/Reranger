import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/recipes/render_graph.dart';
import '../../features/autodraw/presentation/autodraw_screen.dart';
import '../../features/creations/presentation/creations_screen.dart';
import '../../features/editor/presentation/editor_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/humanize/presentation/humanize_screen_host.dart';
import '../../features/import/presentation/analysis_screen.dart';
import '../../features/import/presentation/import_controller.dart';
import '../../features/import/presentation/import_providers.dart';
import '../../features/recolor/presentation/recolor_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/shell/presentation/main_shell_screen.dart';
import 'route_names.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'shell',
);

/// Authoritative GoRouter Configuration for Reranger.
final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: AppRouteNames.home,
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return MainShellScreen(child: child);
      },
      routes: [
        GoRoute(
          path: AppRouteNames.home,
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: HomeScreen()),
        ),
        GoRoute(
          path: AppRouteNames.creations,
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: CreationsScreen()),
        ),
        GoRoute(
          path: AppRouteNames.settings,
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SettingsScreen()),
        ),
      ],
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: AppRouteNames.analysis,
      builder: (context, state) {
        return Consumer(
          builder: (context, ref, _) {
            final controller = ref.watch(importControllerProvider);
            if (controller.state is ImportSuccess ||
                controller.state is ImportCancelled) {
              controller.reset();
            }
            return AnalysisScreen(controller: controller);
          },
        );
      },
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: AppRouteNames.editor,
      builder: (context, state) {
        final id = state.pathParameters['id'] ?? 'unknown';
        return EditorScreen(projectId: id);
      },
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: AppRouteNames.recolor,
      builder: (context, state) {
        final id = state.pathParameters['id'] ?? 'unknown';
        return RecolorScreen(projectId: id);
      },
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: AppRouteNames.humanize,
      builder: (context, state) {
        final id = state.pathParameters['id'] ?? 'unknown';
        return HumanizeScreenHost(projectId: id);
      },
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: AppRouteNames.autodraw,
      builder: (context, state) {
        final id = state.pathParameters['id'] ?? 'unknown';
        final extra = state.extra;
        if (extra is Map<String, dynamic>) {
          return AutodrawScreen(
            projectId: id,
            sourceImageBytes: extra['sourceImageBytes'] as Uint8List?,
            processedImageBytes: extra['processedImageBytes'] as Uint8List?,
            renderGraph: extra['renderGraph'] as RenderGraph?,
          );
        } else if (extra is Uint8List) {
          return AutodrawScreen(projectId: id, processedImageBytes: extra);
        }
        return AutodrawScreen(projectId: id);
      },
    ),
  ],
);
