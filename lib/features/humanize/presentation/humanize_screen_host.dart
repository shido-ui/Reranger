import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../editor/presentation/editor_providers.dart';
import 'humanize_controller.dart';
import 'humanize_screen.dart';

/// Screen host binding router project context to [HumanizeScreen] and [HumanizeController].
class HumanizeScreenHost extends ConsumerStatefulWidget {
  final String projectId;
  final HumanizeController? controller;

  const HumanizeScreenHost({
    super.key,
    required this.projectId,
    this.controller,
  });

  @override
  ConsumerState<HumanizeScreenHost> createState() => _HumanizeScreenHostState();
}

class _HumanizeScreenHostState extends ConsumerState<HumanizeScreenHost> {
  HumanizeController? _controller;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller;
      _isLoading = false;
    } else {
      _initialize();
    }
  }

  Future<void> _initialize() async {
    try {
      final editorCtrl = ref.read(editorControllerProvider(widget.projectId));
      await editorCtrl.loadProject(widget.projectId);

      final project = editorCtrl.project;
      final sourceBytes = editorCtrl.sourceImageBytes;

      if (project == null || sourceBytes == null) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Project source image could not be loaded.';
            _isLoading = false;
          });
        }
        return;
      }

      final ctrl = HumanizeController();
      await ctrl.initialize(
        sourceImageBytes: sourceBytes,
        width: project.sourceWidth,
        height: project.sourceHeight,
      );

      if (mounted) {
        setState(() {
          _controller = ctrl;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load Humanize Studio: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Humanize Studio')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(_errorMessage!),
          ),
        ),
      );
    }

    return HumanizeScreen(
      controller: _controller!,
      onBackToConventional: () {
        if (GoRouter.maybeOf(context) != null &&
            GoRouter.of(context).canPop()) {
          GoRouter.of(context).pop();
        } else {
          context.go(AppRouteNames.editor.replaceAll(':id', widget.projectId));
        }
      },
    );
  }
}
