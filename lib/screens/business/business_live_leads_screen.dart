import "package:flutter/material.dart";

import "package:prox/models/business_lead_models.dart";
import "package:prox/services/business_mode/business_lead_automation_service.dart";
import "package:prox/services/business_mode/business_lead_scoring_service.dart";

class BusinessLiveLeadsScreen extends StatefulWidget {
  const BusinessLiveLeadsScreen({super.key});

  @override
  State<BusinessLiveLeadsScreen> createState() =>
      _BusinessLiveLeadsScreenState();
}

class _BusinessLiveLeadsScreenState extends State<BusinessLiveLeadsScreen> {
  bool _busy = false;
  BusinessLeadInboxFilter _filter = BusinessLeadInboxFilter.open;

  Future<void> _applyTemplate(String leadId, String templateId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await BusinessLeadAutomationService.instance.applyTemplate(
        leadId: leadId,
        templateId: templateId,
      );
      await BusinessLeadScoringService.instance
          .markLeadResponded(leadId: leadId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Template applied.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not apply template: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scheduleFollowups(String leadId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await BusinessLeadAutomationService.instance.scheduleDefaultFollowups(
        leadId: leadId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Follow-up sequence scheduled (15m, 24h, 72h).")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not schedule follow-ups: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelFollowups(String leadId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final cancelled = await BusinessLeadAutomationService.instance
          .cancelScheduledFollowupsForLead(leadId: leadId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Cancelled $cancelled scheduled follow-ups.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not cancel follow-ups: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markWon(String leadId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await BusinessLeadScoringService.instance.markLeadWon(leadId: leadId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lead marked won.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not mark lead won: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _bandColor(ColorScheme cs, BusinessLeadScoreBand band) {
    switch (band) {
      case BusinessLeadScoreBand.hot:
        return cs.errorContainer;
      case BusinessLeadScoreBand.warm:
        return cs.tertiaryContainer;
      case BusinessLeadScoreBand.cold:
        return cs.secondaryContainer;
    }
  }

  String _bandLabel(BusinessLeadScoreBand band) {
    switch (band) {
      case BusinessLeadScoreBand.hot:
        return "HOT";
      case BusinessLeadScoreBand.warm:
        return "WARM";
      case BusinessLeadScoreBand.cold:
        return "COLD";
    }
  }

  String _slaText(DateTime? dueAt) {
    if (dueAt == null) return "No SLA";
    final now = DateTime.now().toUtc();
    final diff = dueAt.toUtc().difference(now);
    if (diff.isNegative) {
      final mins = diff.inMinutes.abs();
      return "Overdue by ${mins}m";
    }
    if (diff.inMinutes < 60) return "Respond in ${diff.inMinutes}m";
    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;
    return "Respond in ${hours}h ${mins}m";
  }

  String _filterEmptyText(BusinessLeadInboxFilter filter) {
    switch (filter) {
      case BusinessLeadInboxFilter.open:
        return "No open leads right now.";
      case BusinessLeadInboxFilter.hot:
        return "No hot leads right now.";
      case BusinessLeadInboxFilter.overdue:
        return "No overdue leads right now.";
      case BusinessLeadInboxFilter.won:
        return "No won leads yet.";
      case BusinessLeadInboxFilter.all:
        return "No leads yet. New leads will appear here automatically and be prioritized by score.";
    }
  }

  String _statusLabel(String status) {
    final cleaned = status.trim().toLowerCase();
    if (cleaned.isEmpty) return "New";
    return cleaned
        .split("_")
        .where((part) => part.trim().isNotEmpty)
        .map((part) => "${part[0].toUpperCase()}${part.substring(1)}")
        .join(" ");
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text("Business Live Leads")),
      body: StreamBuilder<List<BusinessLeadRecord>>(
        stream: BusinessLeadScoringService.instance.watchLeads(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  "Could not load live leads: ${snap.error}",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final rows = snap.data ?? const <BusinessLeadRecord>[];
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  "No leads yet. New leads will appear here automatically and be prioritized by score.",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }

          final now = DateTime.now().toUtc();
          final visibleRows = BusinessLeadInboxPolicy.apply(
            leads: rows,
            filter: _filter,
            now: now,
          );

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<BusinessLeadInboxFilter>(
                        segments: const <ButtonSegment<
                            BusinessLeadInboxFilter>>[
                          ButtonSegment(
                            value: BusinessLeadInboxFilter.open,
                            label: Text("Open"),
                          ),
                          ButtonSegment(
                            value: BusinessLeadInboxFilter.hot,
                            label: Text("Hot"),
                          ),
                          ButtonSegment(
                            value: BusinessLeadInboxFilter.overdue,
                            label: Text("Overdue"),
                          ),
                          ButtonSegment(
                            value: BusinessLeadInboxFilter.won,
                            label: Text("Won"),
                          ),
                          ButtonSegment(
                            value: BusinessLeadInboxFilter.all,
                            label: Text("All"),
                          ),
                        ],
                        selected: <BusinessLeadInboxFilter>{_filter},
                        onSelectionChanged: (selection) {
                          setState(() => _filter = selection.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Showing ${visibleRows.length} of ${rows.length} leads",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (visibleRows.isEmpty)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _filterEmptyText(_filter),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: visibleRows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final r = visibleRows[i];
                      final bandColor = _bandColor(cs, r.scoreBand);
                      final overdue = BusinessLeadInboxPolicy.isOverdue(
                        r,
                        now: now,
                      );

                      return Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: overdue
                                ? cs.error.withValues(alpha: 0.55)
                                : cs.outline.withValues(alpha: 0.2),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          title: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: bandColor,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _bandLabel(r.scoreBand),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "Score ${r.score}",
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Lead: ${r.leadId}"),
                                const SizedBox(height: 4),
                                Text(
                                  "Status: ${_statusLabel(r.status)}",
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _slaText(r.slaDueAt),
                                  style: TextStyle(
                                    color: overdue
                                        ? cs.error
                                        : cs.onSurfaceVariant,
                                    fontWeight: overdue
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                if (r.estimatedValueUsd != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    "Estimated value: \$${r.estimatedValueUsd!.toStringAsFixed(0)}",
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    PopupMenuButton<String>(
                                      enabled: !_busy,
                                      onSelected: (templateId) =>
                                          _applyTemplate(r.leadId, templateId),
                                      itemBuilder: (_) =>
                                          BusinessLeadAutomationService
                                              .templates
                                              .map(
                                                (t) => PopupMenuItem<String>(
                                                  value: t.id,
                                                  child: Text(t.title),
                                                ),
                                              )
                                              .toList(growable: false),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: cs.primaryContainer,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          border: Border.all(
                                            color: cs.primary
                                                .withValues(alpha: 0.4),
                                          ),
                                        ),
                                        child: Text(
                                          "Quick template",
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    OutlinedButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _scheduleFollowups(r.leadId),
                                      child: const Text("Schedule follow-ups"),
                                    ),
                                    OutlinedButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _cancelFollowups(r.leadId),
                                      child: const Text("Cancel follow-ups"),
                                    ),
                                    FilledButton.tonal(
                                      onPressed: _busy
                                          ? null
                                          : () => _markWon(r.leadId),
                                      child: const Text("Mark won"),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
