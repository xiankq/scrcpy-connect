import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

/// Follows the exact save operation, including one restored from its ledger.
class DocumentConflictPanel extends StatefulWidget {
  const DocumentConflictPanel({
    super.key,
    required this.controller,
    required this.operationId,
  });

  final AppController controller;
  final String operationId;

  @override
  State<DocumentConflictPanel> createState() => _DocumentConflictPanelState();
}

class _DocumentConflictPanelState extends State<DocumentConflictPanel> {
  StreamSubscription<Json>? _events;
  Json? _pending;
  String? _error, _resolving;
  bool _applyToRemaining = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(DocumentConflictPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller &&
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
    // Subscribe before reading so a conflict created during initialization is
    // observed, and a stale read cannot resurrect an already resolved prompt.
    _events = widget.controller.eventStream().listen((event) {
      if (event['type'] != 'documents.conflict.changed') return;
      final data = jsonObject(event['data']);
      if (data['operationId'] != widget.operationId) return;
      _revision++;
      _accept(data['pending']);
    });
    unawaited(_read());
  }

  Future<void> _read() async {
    final revision = ++_revision;
    final owner = widget.operationId;
    try {
      final response = await widget.controller.execute(
        InteropCommand.documentsConflictGet,
        {'operationId': owner},
      );
      if (!mounted || revision != _revision || owner != widget.operationId) {
        return;
      }
      _accept(response['pending']);
    } catch (error) {
      if (!mounted || revision != _revision || owner != widget.operationId) {
        return;
      }
      setState(() => _error = '尚未读到同名处理状态：$error');
    }
  }

  void _accept(Object? raw) {
    final candidate = raw is Map<Object?, Object?> ? jsonObject(raw) : null;
    final pending =
        candidate?['operationId'] == widget.operationId &&
            value(candidate ?? {}, 'conflictId').isNotEmpty
        ? candidate
        : null;
    setState(() {
      if (_pending?['conflictId'] != pending?['conflictId']) {
        _applyToRemaining = false;
      }
      _pending = pending;
      _error = null;
    });
  }

  Future<void> _resolve(String choice) async {
    final pending = _pending;
    if (pending == null || _resolving != null) return;
    final owner = widget.operationId;
    final conflictId = value(pending, 'conflictId');
    setState(() => _resolving = conflictId);
    try {
      final response = await widget.controller.execute(
        InteropCommand.documentsConflictResolve,
        {
          'operationId': owner,
          'conflictId': conflictId,
          'choice': choice,
          'applyToRemaining': choice != 'cancel' && _applyToRemaining,
        },
      );
      if (!mounted ||
          owner != widget.operationId ||
          _pending?['conflictId'] != conflictId) {
        return;
      }
      if (response['resolved'] == true) {
        _revision++;
        _accept(null);
      } else {
        await _read();
      }
    } catch (error) {
      if (mounted &&
          owner == widget.operationId &&
          _pending?['conflictId'] == conflictId) {
        setState(() => _error = '同名处理未确认：$error');
      }
    } finally {
      if (mounted && owner == widget.operationId && _resolving == conflictId) {
        setState(() => _resolving = null);
      }
    }
  }

  void _release(DocumentConflictPanel owner) {
    _revision++;
    unawaited(_events?.cancel());
    _events = null;
    // Restored pending saves also need a page-exit cancellation owner. The
    // shared command is idempotent and cannot cancel a replacement operation.
    owner.controller.execute(InteropCommand.documentsCancel, {
      'operationId': owner.operationId,
    }).ignore();
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
    return ContentPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('存在同名项目', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(value(pending, 'name')),
          const SizedBox(height: 8),
          const Text('此位置暂不支持替换同名内容；已有文件会保留。'),
          const Text('保留两份会使用新名称。本机暂存会保留；取消不会删除已保存的项目。'),
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
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: busy ? null : () => _resolve('keepBoth'),
                child: const Text('保留两份'),
              ),
              OutlinedButton(
                onPressed: busy ? null : () => _resolve('skip'),
                child: const Text('跳过此项'),
              ),
              TextButton(
                onPressed: busy ? null : () => _resolve('cancel'),
                child: const Text('取消本次保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
