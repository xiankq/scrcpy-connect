import 'dart:async';

import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/files/system_documents.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/files/models/document_event.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

/// 跟踪精确的系统保存操作，包含从持久账本恢复的操作。
class DocumentConflictPanel extends ConsumerWidget {
  const DocumentConflictPanel({super.key, required this.operationId});
  final String operationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _ConflictView(
    documents: ref.watch(systemDocumentsProvider),
    events: ref.watch(runtimeEventsProvider),
    operationId: operationId,
  );
}

class _ConflictView extends StatefulWidget {
  const _ConflictView({
    required this.documents,
    required this.events,
    required this.operationId,
  });
  final SystemDocuments documents;
  final Stream<RuntimeEvent> events;
  final String operationId;

  @override
  State<_ConflictView> createState() => _ConflictViewState();
}

class _ConflictViewState extends State<_ConflictView> {
  int _scope = 0;
  StreamSubscription<RuntimeEvent>? _events;
  DocumentConflict? _pending;
  String? _error, _resolving;
  bool _applyToRemaining = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(_ConflictView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.documents, widget.documents) &&
        identical(oldWidget.events, widget.events) &&
        oldWidget.operationId == widget.operationId) {
      return;
    }
    _release(oldWidget);
    _pending = null;
    _error = _resolving = null;
    _applyToRemaining = false;
    _follow();
  }

  void _follow() {
    // 先订阅再读取，避免漏掉初始化期间的冲突，也防止旧读取重新显示已解决的提示。
    _events = widget.events.listen((event) {
      final data = event.data;
      if (data is! DocumentConflictChanged ||
          data.operationId != widget.operationId) {
        return;
      }
      _revision++;
      _accept(data.pending);
    });
    unawaited(_read());
  }

  Future<void> _read() async {
    final revision = ++_revision;
    final owner = widget.operationId;
    try {
      final response = await widget.documents.readDocumentConflict(owner);
      if (!mounted || revision != _revision || owner != widget.operationId) {
        return;
      }
      _accept(response);
    } catch (error) {
      if (!mounted || revision != _revision || owner != widget.operationId) {
        return;
      }
      setState(
        () => _error = failureMessage(error, fallback: '无法读取同名文件的处理结果。请重新检查。'),
      );
    }
  }

  void _accept(DocumentConflict? candidate) {
    final pending =
        candidate?.operationId == widget.operationId &&
            candidate?.conflictId.isNotEmpty == true
        ? candidate
        : null;
    setState(() {
      if (_pending?.conflictId != pending?.conflictId) {
        _applyToRemaining = false;
      }
      _pending = pending;
      _error = null;
    });
  }

  Future<void> _resolve(DocumentConflictDecision choice) async {
    final pending = _pending;
    if (pending == null || _resolving != null) return;
    final owner = widget.operationId;
    final scope = _scope;
    final conflictId = pending.conflictId;
    setState(() => _resolving = conflictId);
    try {
      final response = await widget.documents.resolveDocumentConflict(
        owner,
        conflictId,
        choice,
        applyToRemaining: choice != .cancel && _applyToRemaining,
      );
      if (!mounted ||
          owner != widget.operationId ||
          scope != _scope ||
          _pending?.conflictId != conflictId) {
        return;
      }
      if (response) {
        _revision++;
        _accept(null);
      } else {
        await _read();
      }
    } catch (error) {
      if (mounted &&
          owner == widget.operationId &&
          scope == _scope &&
          _pending?.conflictId == conflictId) {
        setState(
          () => _error = failureMessage(
            error,
            fallback: '暂时无法确认同名文件是否已处理。请先检查结果。',
          ),
        );
      }
    } finally {
      if (mounted &&
          owner == widget.operationId &&
          scope == _scope &&
          _resolving == conflictId) {
        setState(() => _resolving = null);
      }
    }
  }

  void _release(_ConflictView owner) {
    _revision++;
    _scope++;
    unawaited(_events?.cancel());
    _events = null;
    // 恢复的待保存操作也需要离页取消所有者；幂等命令不会取消替换后的新操作。
    owner.documents.cancelDocument(owner.operationId).ignore();
  }

  @override
  void dispose() {
    _release(widget);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    if (pending == null) {
      return _error == null ? const SizedBox.shrink() : StateNote(_error!);
    }
    final busy = _resolving != null;
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    return ContentPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('存在同名项目', style: type.headline),
          const SizedBox(height: DesignTokens.spacingSm),
          Text(pending.name, style: type.body),
          const SizedBox(height: DesignTokens.spacingXs),
          Text(
            '保留两份时会为本次文件生成新名称。',
            style: type.subheadline.copyWith(color: colors.textSecondary),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _applyToRemaining,
            onChanged: busy
                ? null
                : (value) => setState(() => _applyToRemaining = value == true),
            title: const Text('应用于本次保存的后续同名项目'),
          ),
          if (_error != null) StateNote(_error!),
          Wrap(
            spacing: DesignTokens.spacingSm,
            runSpacing: DesignTokens.spacingSm,
            children: [
              FilledButton(
                onPressed: busy ? null : () => _resolve(.keepBoth),
                child: const Text('保留两份'),
              ),
              OutlinedButton(
                onPressed: busy ? null : () => _resolve(.skip),
                child: const Text('跳过此项'),
              ),
              TextButton(
                onPressed: busy ? null : () => _resolve(.cancel),
                child: const Text('取消本次保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
