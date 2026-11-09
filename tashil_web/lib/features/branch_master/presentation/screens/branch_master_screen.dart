import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/m3_spacing.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/m3_feedback.dart';
import '../../data/branch_master_repository.dart';

/// إدارة الفروع: أكواد موحدة، أسماء قصيرة، أسماء مستعارة، وحل المعلّق (RTL + M3).
class BranchMasterScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final BranchMasterDataSource? dataSource;

  const BranchMasterScreen({super.key, this.apiClient, this.dataSource});

  @override
  State<BranchMasterScreen> createState() => _BranchMasterScreenState();
}

class _BranchMasterScreenState extends State<BranchMasterScreen> with SingleTickerProviderStateMixin {
  late final BranchMasterDataSource _ds =
      widget.dataSource ?? HttpBranchMasterDataSource(widget.apiClient!);
  late final TabController _tabs = TabController(length: 3, vsync: this);
  BranchMasterState _state = const BranchMasterState();
  bool _loading = true;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await _ds.load();
      if (mounted) setState(() => _state = s);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editName(BranchMasterBranch b) async {
    final ctl = TextEditingController(text: b.displayName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('edit_branch_display_dialog'),
        icon: const Icon(AppIcons.edit),
        title: Text('تعديل اسم ${b.code}'),
        content: TextField(
          key: const Key('edit_branch_display_field'),
          controller: ctl,
          decoration: const InputDecoration(
            labelText: 'الاسم القصير للعرض',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = b.code);
    try {
      await _ds.updateDisplayName(b.code, ctl.text.trim());
      if (mounted) M3Feedback.showSuccess(context, 'تم تحديث الاسم');
      await _load();
    } catch (e) {
      if (mounted) M3Feedback.showError(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _confirm(BranchMasterPending p, {required String branchCode}) async {
    setState(() => _busy = p.id);
    try {
      await _ds.confirmPending(p.id, branchCode: branchCode);
      if (mounted) M3Feedback.showSuccess(context, 'تم تأكيد الربط');
      await _load();
    } catch (e) {
      if (mounted) M3Feedback.showError(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _reject(BranchMasterPending p) async {
    setState(() => _busy = p.id);
    try {
      await _ds.rejectPending(p.id);
      if (mounted) M3Feedback.showSuccess(context, 'تم رفض الاقتراح');
      await _load();
    } catch (e) {
      if (mounted) M3Feedback.showError(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة الفروع'),
          actions: [
            IconButton(
              key: const Key('branch_master_refresh'),
              tooltip: 'تحديث',
              onPressed: _load,
              icon: const Icon(AppIcons.refresh),
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            tabs: [
              Tab(text: 'الفروع (${_state.branches.length})'),
              Tab(text: 'المستعارة (${_state.aliases.length})'),
              Tab(text: 'معلّق (${_state.pending.where((p) => true).length})'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: theme.textTheme.bodyLarge))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _branchesList(theme),
                      _aliasesList(theme),
                      _pendingList(theme),
                    ],
                  ),
      ),
    );
  }

  Widget _branchesList(ThemeData theme) {
    if (_state.branches.isEmpty) {
      return const ListTile(
        leading: Icon(AppIcons.branchMaster),
        title: Text('لا توجد فروع بعد — أكّد اقتراح الـ dry-run أولاً'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(M3Spacing.md),
      itemCount: _state.branches.length,
      separatorBuilder: (_, __) => const SizedBox(height: M3Spacing.xs),
      itemBuilder: (ctx, i) {
        final b = _state.branches[i];
        return ListTile(
          key: Key('branch_row_${b.code}'),
          leading: Icon(b.unallocated ? AppIcons.warning : AppIcons.store),
          title: Text('${b.displayName} · ${b.code}'),
          subtitle: Text('سلسلة ${b.chainCode}${b.unallocated ? ' · غير موزع' : ''}'),
          trailing: b.unallocated || _busy == b.code
              ? null
              : IconButton(
                  key: Key('branch_edit_${b.code}'),
                  tooltip: 'تعديل الاسم',
                  icon: const Icon(AppIcons.edit),
                  onPressed: () => _editName(b),
                ),
        );
      },
    );
  }

  Widget _aliasesList(ThemeData theme) {
    if (_state.aliases.isEmpty) {
      return const ListTile(leading: Icon(AppIcons.tag), title: Text('لا توجد أسماء مستعارة'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(M3Spacing.md),
      itemCount: _state.aliases.length,
      separatorBuilder: (_, __) => const SizedBox(height: M3Spacing.xs),
      itemBuilder: (ctx, i) {
        final a = _state.aliases[i];
        return ListTile(
          key: Key('alias_row_${a.rawName}'),
          leading: const Icon(AppIcons.tag),
          title: Text(a.rawName),
          subtitle: Text('→ ${a.branchCode} · ${a.source}'),
        );
      },
    );
  }

  Widget _pendingList(ThemeData theme) {
    final pending = _state.pending;
    if (pending.isEmpty) {
      return const ListTile(leading: Icon(AppIcons.verified), title: Text('لا يوجد معلّق'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(M3Spacing.md),
      itemCount: pending.length,
      separatorBuilder: (_, __) => const SizedBox(height: M3Spacing.xs),
      itemBuilder: (ctx, i) {
        final p = pending[i];
        final busy = _busy == p.id;
        return ListTile(
          key: Key('pending_branch_${p.id}'),
          leading: const Icon(AppIcons.pendingCustomers),
          title: Text(p.rawName),
          subtitle: Text(p.reasonAr.isEmpty ? p.kind : p.reasonAr),
          isThreeLine: true,
          trailing: busy
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : Wrap(
                  spacing: 4,
                  children: [
                    if (p.suggestedCode.isNotEmpty)
                      FilledButton(
                        key: Key('pending_confirm_${p.id}'),
                        onPressed: () => _confirm(p, branchCode: p.suggestedCode),
                        child: Text(p.suggestedName.isEmpty ? 'تأكيد' : p.suggestedName),
                      ),
                    if (p.altSuggestedCode.isNotEmpty)
                      FilledButton.tonal(
                        key: Key('pending_alt_${p.id}'),
                        onPressed: () => _confirm(p, branchCode: p.altSuggestedCode),
                        child: Text(p.altSuggestedName.isEmpty ? 'البديل' : p.altSuggestedName),
                      ),
                    FilledButton.tonal(
                      key: Key('pending_new_${p.id}'),
                      onPressed: () => _confirm(p, branchCode: 'new'),
                      child: const Text('فرع جديد'),
                    ),
                    OutlinedButton(
                      key: Key('pending_reject_${p.id}'),
                      onPressed: () => _reject(p),
                      child: const Text('رفض'),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
