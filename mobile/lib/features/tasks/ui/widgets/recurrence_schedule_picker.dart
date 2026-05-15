import 'package:flutter/material.dart';

// ────────────────────────────────────────────────
// RRULE Preset helpers (SPR-005-MB §Technical Notes)
// ────────────────────────────────────────────────

/// Builds a daily RRULE string.
const String kDailyRRule = 'FREQ=DAILY';

/// Builds a weekly RRULE on selected weekday codes ('MO','TU',...'SU').
String weeklyRRule(List<String> days) =>
    'FREQ=WEEKLY;BYDAY=${days.join(",")}';

/// Named presets the picker offers.
enum RecurrencePreset {
  daily,
  weekdays,   // Mon–Fri
  weekly,     // same weekday as the task's start date
  custom;
}

// ────────────────────────────────────────────────
// Widget
// ────────────────────────────────────────────────

/// RRULE schedule picker shown inside the task create/edit form (M-037).
///
/// Surfaces three presets (Daily, Weekdays, Weekly) and a Custom raw-input
/// field.  Calls [onRRuleChanged] on every RRULE change.
/// The parent form is responsible for passing the result into
/// [CreateTaskRequest.rrule] / [UpdateTaskRequest.rrule].
class RecurrenceSchedulePicker extends StatefulWidget {
  const RecurrenceSchedulePicker({
    super.key,
    this.initialRRule,
    required this.onRRuleChanged,
    this.errorText,
  });

  /// The current RRULE value — null if first open.
  final String? initialRRule;

  /// Called whenever the selected RRULE changes.
  final ValueChanged<String?> onRRuleChanged;

  /// Inline error text — non-null when the backend returned INVALID_RRULE.
  final String? errorText;

  @override
  State<RecurrenceSchedulePicker> createState() =>
      _RecurrenceSchedulePickerState();
}

class _RecurrenceSchedulePickerState extends State<RecurrenceSchedulePicker> {
  RecurrencePreset _selected = RecurrencePreset.daily;
  final _customCtrl = TextEditingController();

  // Weekday state for the Weekly preset
  final Set<String> _selectedDays = {'MO', 'WE', 'FR'};

  static const _weekdays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
  static const _weekdayLabels = {
    'MO': 'Mon',
    'TU': 'Tue',
    'WE': 'Wed',
    'TH': 'Thu',
    'FR': 'Fri',
    'SA': 'Sat',
    'SU': 'Sun',
  };

  @override
  void initState() {
    super.initState();
    // Detect initial preset from existing rrule.
    final r = widget.initialRRule;
    if (r != null) {
      if (r == kDailyRRule) {
        _selected = RecurrencePreset.daily;
      } else if (r == 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR') {
        _selected = RecurrencePreset.weekdays;
      } else if (r.startsWith('FREQ=WEEKLY;BYDAY=') &&
          r.split('BYDAY=')[1].split(',').length == 1) {
        _selected = RecurrencePreset.weekly;
        _selectedDays
          ..clear()
          ..add(r.split('BYDAY=')[1]);
      } else {
        _selected = RecurrencePreset.custom;
        _customCtrl.text = r;
      }
    }
    _customCtrl.addListener(_onCustomChanged);
    // Emit initial value.
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _customCtrl
      ..removeListener(_onCustomChanged)
      ..dispose();
    super.dispose();
  }

  void _onCustomChanged() => _emit();

  void _emit() {
    widget.onRRuleChanged(_buildRRule());
  }

  String? _buildRRule() => switch (_selected) {
        RecurrencePreset.daily => kDailyRRule,
        RecurrencePreset.weekdays => 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
        RecurrencePreset.weekly => _selectedDays.isNotEmpty
            ? weeklyRRule(_selectedDays.toList())
            : null,
        RecurrencePreset.custom => _customCtrl.text.trim().isEmpty
            ? null
            : _customCtrl.text.trim(),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Preset chips ─────────────────────────────────────────────────────
        Wrap(
          spacing: 8,
          children: [
            _PresetChip(
              key: const Key('rrule_preset_daily'),
              label: 'Daily',
              selected: _selected == RecurrencePreset.daily,
              onTap: () => setState(() {
                _selected = RecurrencePreset.daily;
                _emit();
              }),
            ),
            _PresetChip(
              key: const Key('rrule_preset_weekdays'),
              label: 'Weekdays',
              selected: _selected == RecurrencePreset.weekdays,
              onTap: () => setState(() {
                _selected = RecurrencePreset.weekdays;
                _emit();
              }),
            ),
            _PresetChip(
              key: const Key('rrule_preset_weekly'),
              label: 'Weekly',
              selected: _selected == RecurrencePreset.weekly,
              onTap: () => setState(() {
                _selected = RecurrencePreset.weekly;
                _emit();
              }),
            ),
            _PresetChip(
              key: const Key('rrule_preset_custom'),
              label: 'Custom',
              selected: _selected == RecurrencePreset.custom,
              onTap: () => setState(() {
                _selected = RecurrencePreset.custom;
                _emit();
              }),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Conditional secondary UI ──────────────────────────────────────────
        if (_selected == RecurrencePreset.weekly) ...[
          Text('Repeat on:', style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: _weekdays
                .map((day) => FilterChip(
                      key: Key('rrule_day_$day'),
                      label: Text(_weekdayLabels[day]!,
                          style: const TextStyle(fontSize: 12)),
                      selected: _selectedDays.contains(day),
                      onSelected: (v) => setState(() {
                        if (v) {
                          _selectedDays.add(day);
                        } else {
                          _selectedDays.remove(day);
                        }
                        _emit();
                      }),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          if (_selectedDays.isEmpty)
            Text(
              'Select at least one day.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
        ],

        if (_selected == RecurrencePreset.custom) ...[
          TextFormField(
            key: const Key('rrule_custom_input'),
            controller: _customCtrl,
            decoration: InputDecoration(
              labelText: 'RRULE string',
              hintText: 'e.g. FREQ=MONTHLY;BYMONTHDAY=1',
              errorText: widget.errorText,
              helperText: 'Advanced: enter any valid iCalendar RRULE.',
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
            ),
            autocorrect: false,
          ),
        ],

        // Non-custom presets — show current RRULE as confirmation label
        if (_selected != RecurrencePreset.custom) ...[
          Text(
            'RRULE: ${_buildRRule() ?? "(none selected)"}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              fontFamily: 'monospace',
            ),
          ),
        ],

        // Error from API (INVALID_RRULE) for non-custom cases
        if (widget.errorText != null && _selected != RecurrencePreset.custom)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              widget.errorText!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
