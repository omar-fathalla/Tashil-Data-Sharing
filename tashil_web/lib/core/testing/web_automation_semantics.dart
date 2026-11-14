import 'package:flutter/foundation.dart';

/// True when web automation explicitly opts into the flt-semantics DOM glass
/// pane (`?semantics=1` or `?e2e=1`).
///
/// Forced [SemanticsBinding.ensureSemantics] must NOT run for normal
/// production mouse users: Pricing filter chips / segmented controls publish
/// interactive nodes near the sidebar Compare row, and those DOM nodes can
/// swallow native clicks while canvas hit-tests still pass (live v188 / #186).
bool webAutomationSemanticsRequested() {
  if (!kIsWeb) return false;
  final q = Uri.base.queryParameters;
  return q['semantics'] == '1' || q['e2e'] == '1';
}
