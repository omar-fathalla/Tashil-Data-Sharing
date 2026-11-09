import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../data/arabic_qa_models.dart';
import '../data/arabic_qa_repository.dart';

/// Phase C Arabic Q&A over BigQuery — read-only, tenant-scoped.
class ArabicQaScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final ArabicQaDataSource? dataSource;

  const ArabicQaScreen({super.key, this.apiClient, this.dataSource});

  @override
  State<ArabicQaScreen> createState() => _ArabicQaScreenState();
}

class _ArabicQaScreenState extends State<ArabicQaScreen> {
  late final ArabicQaDataSource _ds =
      widget.dataSource ?? HttpArabicQaDataSource(widget.apiClient!);
  final _controller = TextEditingController();
  final _turns = <ArabicQaAnswer>[];
  List<ArabicQaCapability> _caps = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCaps();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadCaps() async {
    try {
      final caps = await _ds.capabilities();
      if (!mounted) return;
      setState(() => _caps = caps);
    } catch (_) {
      // Capabilities are optional chrome; ask still works.
    }
  }

  Future<void> _ask() async {
    final q = _controller.text.trim();
    if (q.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ans = await _ds.ask(q);
      if (!mounted) return;
      setState(() {
        _turns.insert(0, ans);
        _controller.clear();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('أسئلة عربية على البيانات'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'قراءة فقط من بيانات المستأجر في BigQuery — مفيش كتابة ولا SQL حر.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              if (_caps.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in _caps)
                      ActionChip(
                        label: Text(c.titleAr),
                        onPressed: () {
                          if (c.examplesAr.isNotEmpty) {
                            _controller.text = c.examplesAr.first;
                            setState(() {});
                          }
                        },
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'اسأل بالعربي عن المبيعات أو السلاسل أو التوريد…',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _ask(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _loading ? null : _ask,
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('اسأل'),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: _turns.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final t = _turns[i];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(t.questionAr, style: theme.textTheme.titleSmall),
                            const SizedBox(height: 6),
                            Text(t.answerAr),
                            const SizedBox(height: 8),
                            Text(
                              'مصدر: ${t.mappingSource} · قراءة فقط: ${t.readOnly ? "نعم" : "لا"} · ${t.intent}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
