// lib/screens/settings_page.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import '../models/custom_field.dart';
import '../models/hospital_full.dart';
import '../providers/queue_provider.dart';
import '../widgets/cq_button.dart';

class SettingsPage extends ConsumerStatefulWidget {
  final String hospitalId;
  const SettingsPage({super.key, required this.hospitalId});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with SingleTickerProviderStateMixin {
  final _tokenLimitCtrl  = TextEditingController();
  final _avgTimeCtrl     = TextEditingController();
  final _alertBeforeCtrl = TextEditingController();
  final _startTimeCtrl   = TextEditingController();
  final _endTimeCtrl     = TextEditingController();

  bool _enableAge    = true;
  bool _enableReason = true;
  final List<CustomField> _customFields = [];

  // Token format
  final _tokenPrefixCtrl = TextEditingController();
  TokenFormat _tokenFormat  = TokenFormat.numeric;
  int         _tokenPadding = 2;

  bool    _isLoaded  = false;
  bool    _isSaving  = false;
  String? _errorMsg;
  String? _successMsg;

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _tokenLimitCtrl.dispose();
    _avgTimeCtrl.dispose();
    _alertBeforeCtrl.dispose();
    _startTimeCtrl.dispose();
    _endTimeCtrl.dispose();
    _tokenPrefixCtrl.dispose();
    super.dispose();
  }

  void _populate(HospitalSettings s) {
    if (_isLoaded) return;
    _tokenLimitCtrl.text  = '${s.tokenLimit}';
    _avgTimeCtrl.text     = '${s.avgTimePerPatient}';
    _alertBeforeCtrl.text = '${s.alertBefore}';
    _startTimeCtrl.text   = s.workingHoursStart;
    _endTimeCtrl.text     = s.workingHoursEnd;
    _enableAge            = s.enableAge;
    _enableReason         = s.enableReason;
    _customFields..clear()..addAll(s.customFields);
    _tokenPrefixCtrl.text = s.tokenPrefix;
    _tokenFormat          = s.tokenFormat;
    _tokenPadding         = s.tokenPadding;
    _isLoaded = true;
  }

  Future<void> _save() async {
    final tokenLimit  = int.tryParse(_tokenLimitCtrl.text.trim());
    final avgTime     = int.tryParse(_avgTimeCtrl.text.trim());
    final alertBefore = int.tryParse(_alertBeforeCtrl.text.trim());

    if (tokenLimit == null || tokenLimit < 1 || tokenLimit > 500) {
      return _setError('Token limit must be 1 - 500');
    }
    if (avgTime == null || avgTime < 1 || avgTime > 120) {
      return _setError('Avg time must be 1 - 120 minutes');
    }
    for (final f in _customFields) {
      if (f.label.trim().isEmpty) return _setError('All custom fields need a label');
      if (f.type == CustomFieldType.dropdown && f.options.isEmpty) {
        return _setError('"${f.label}" dropdown needs at least one option');
      }
    }

    setState(() { _isSaving = true; _errorMsg = null; _successMsg = null; });

    final result = await ref.read(queueServiceProvider).updateSettings(
      hospitalId:        widget.hospitalId,
      tokenLimit:        tokenLimit,
      avgTimePerPatient: avgTime,
      alertBefore:       alertBefore,
      workingHoursStart: _startTimeCtrl.text.trim().isEmpty ? null : _startTimeCtrl.text.trim(),
      workingHoursEnd:   _endTimeCtrl.text.trim().isEmpty   ? null : _endTimeCtrl.text.trim(),
      enableAge:         _enableAge,
      enableReason:      _enableReason,
      customFields:      _customFields.map((f) => f.toJson()).toList(),
      tokenPrefix:       _tokenPrefixCtrl.text.trim(),
      tokenFormat:       _tokenFormat.value,
      tokenPadding:      _tokenPadding,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.isFailure) {
      _setError(result.error!);
    } else {
      setState(() => _successMsg = 'Settings saved!');
      ref.invalidate(hospitalFullProvider(widget.hospitalId));
    }
  }

  void _setError(String m) => setState(() { _errorMsg = m; _successMsg = null; });

  void _addField() => setState(() => _customFields.add(CustomField(
        id: 'field_${Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
        label: '', type: CustomFieldType.text)));

  void _removeField(int i)                  => setState(() => _customFields.removeAt(i));
  void _updateField(int i, CustomField f)   => setState(() => _customFields[i] = f);
  void _reorderField(int o, int n)          => setState(() {
        if (n > o) n--;
        _customFields.insert(n, _customFields.removeAt(o));
      });

  Future<void> _pickTime(TextEditingController ctrl) async {
    final parts = ctrl.text.split(':');
    final init  = parts.length == 2
        ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0)
        : const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(
      context: context, initialTime: init,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!));
    if (picked != null && mounted) {
      setState(() => ctrl.text =
          '${picked.hour.toString().padLeft(2,'0')}:${picked.minute.toString().padLeft(2,'0')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hospitalAsync = ref.watch(hospitalFullProvider(widget.hospitalId));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => context.go('/dashboard'),
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppColors.textSecondary,
        ),
        title: Text('Settings', style: GoogleFonts.dmSans(
            fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: AppColors.border)),
      ),
      body: hospitalAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (hospital) {
          if (hospital != null) _populate(hospital.settings);
          return FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: _buildBody(),
              )),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Queue Settings', style: GoogleFonts.playfairDisplay(
          fontSize: 26, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Customise your check-in form and queue behaviour.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
      const SizedBox(height: 24),
      if (_errorMsg   != null) ...[_Banner(message: _errorMsg!,   isError: true),  const SizedBox(height: 14)],
      if (_successMsg != null) ...[_Banner(message: _successMsg!, isError: false), const SizedBox(height: 14)],

      _SectionCard(icon: Icons.confirmation_number_outlined, title: 'Token Controls', children: [
        _NumRow(label: 'Daily Token Limit',   subtitle: 'Max tokens issued per day', ctrl: _tokenLimitCtrl,  suffix: 'tokens'),
        _RowDivider(),
        _NumRow(label: 'Alert Before',         subtitle: 'Notify patient N tokens before turn', ctrl: _alertBeforeCtrl, suffix: 'tokens'),
      ]),
      const SizedBox(height: 14),
      _SectionCard(icon: Icons.schedule_rounded, title: 'Wait Time', children: [
        _NumRow(label: 'Avg. Time per Patient', subtitle: 'Used to estimate patient wait time', ctrl: _avgTimeCtrl, suffix: 'min'),
      ]),
      const SizedBox(height: 14),
      _SectionCard(icon: Icons.access_time_rounded, title: 'Working Hours', children: [
        _TimeRow(label: 'Opens At',  ctrl: _startTimeCtrl, onTap: () => _pickTime(_startTimeCtrl)),
        _RowDivider(),
        _TimeRow(label: 'Closes At', ctrl: _endTimeCtrl,   onTap: () => _pickTime(_endTimeCtrl)),
      ]),
      const SizedBox(height: 14),
      _SectionCard(icon: Icons.tune_rounded, title: 'Check-in Form Fields', children: [
        _ToggleRow(label: 'Age Field',          subtitle: 'Show age input on check-in form',          value: _enableAge,    onChanged: (v) => setState(() => _enableAge    = v)),
        _RowDivider(),
        _ToggleRow(label: 'Reason for Visit',   subtitle: 'Show reason dropdown on check-in form',    value: _enableReason, onChanged: (v) => setState(() => _enableReason = v)),
      ]),
      const SizedBox(height: 14),
      _TokenFormatSection(
        prefixCtrl:   _tokenPrefixCtrl,
        format:       _tokenFormat,
        padding:      _tokenPadding,
        onFormatChanged:  (f) => setState(() => _tokenFormat  = f),
        onPaddingChanged: (p) => setState(() => _tokenPadding = p),
        onPrefixChanged:  ()  => setState(() {}),
      ),
      const SizedBox(height: 14),
      _CustomFieldsSection(
        fields:    _customFields,
        onAdd:     _addField,
        onRemove:  _removeField,
        onUpdate:  _updateField,
        onReorder: _reorderField,
      ),
      const SizedBox(height: 28),
      CQButton(label: 'Save All Settings', isLoading: _isSaving, onPressed: _save, icon: Icons.save_rounded),
      const SizedBox(height: 48),
    ],
  );
}

// ═══════════════════════════════════════════════════════════
// TOKEN FORMAT SECTION
// ═══════════════════════════════════════════════════════════

class _TokenFormatSection extends StatelessWidget {
  final TextEditingController prefixCtrl;
  final TokenFormat            format;
  final int                    padding;
  final void Function(TokenFormat) onFormatChanged;
  final void Function(int)         onPaddingChanged;
  final VoidCallback               onPrefixChanged;

  const _TokenFormatSection({
    required this.prefixCtrl,
    required this.format,
    required this.padding,
    required this.onFormatChanged,
    required this.onPaddingChanged,
    required this.onPrefixChanged,
  });

  // Build a live preview string
  String _preview() {
    if (format == TokenFormat.numeric) return '1   2   3   …';
    final p  = prefixCtrl.text.isEmpty ? 'A' : prefixCtrl.text;
    final a  = 1.toString().padLeft(padding, '0');
    final b  = 2.toString().padLeft(padding, '0');
    return '$p$a   $p$b   …';
  }

  @override
  Widget build(BuildContext context) {
    final showPrefix = format != TokenFormat.numeric;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.confirmation_number_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Token Format',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.border),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Format selector chips
                Text(
                  'Format Style',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: TokenFormat.values.map((f) {
                    final selected = f == format;
                    return ChoiceChip(
                      label: Text(f.label),
                      selected: selected,
                      onSelected: (_) => onFormatChanged(f),
                      selectedColor:
                          AppColors.primary.withValues(alpha: 0.12),
                      labelStyle: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      side: BorderSide(
                        color: selected
                            ? AppColors.primary
                            : AppColors.border,
                      ),
                      backgroundColor: AppColors.surface,
                      showCheckmark: false,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    );
                  }).toList(),
                ),

                // Prefix + padding (only when not numeric)
                if (showPrefix) ...[
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Prefix input
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Prefix',
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: prefixCtrl,
                              onChanged: (_) => onPrefixChanged(),
                              maxLength: 8,
                              decoration: InputDecoration(
                                hintText: 'e.g. A, City-',
                                counterText: '',
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: AppColors.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: AppColors.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: AppColors.primary,
                                      width: 1.5),
                                ),
                                filled: true,
                                fillColor: AppColors.background,
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Padding selector
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Number Padding',
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                _PadChip(
                                  label: '1  (1)',
                                  value: 1,
                                  selected: padding,
                                  onTap: onPaddingChanged,
                                ),
                                const SizedBox(width: 6),
                                _PadChip(
                                  label: '01',
                                  value: 2,
                                  selected: padding,
                                  onTap: onPaddingChanged,
                                ),
                                const SizedBox(width: 6),
                                _PadChip(
                                  label: '001',
                                  value: 3,
                                  selected: padding,
                                  onTap: onPaddingChanged,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],

                // Live preview
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.visibility_outlined,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Preview: ',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _preview(),
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PadChip extends StatelessWidget {
  final String label;
  final int    value;
  final int    selected;
  final void Function(int) onTap;

  const _PadChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// CUSTOM FIELDS SECTION
// ═══════════════════════════════════════════════════════════

class _CustomFieldsSection extends StatelessWidget {
  final List<CustomField> fields;
  final VoidCallback onAdd;
  final void Function(int) onRemove;
  final void Function(int, CustomField) onUpdate;
  final void Function(int, int) onReorder;

  const _CustomFieldsSection({
    required this.fields, required this.onAdd, required this.onRemove,
    required this.onUpdate, required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
            child: Row(
              children: [
                const Icon(Icons.add_box_outlined, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('Custom Fields', style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const Spacer(),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Field'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    textStyle: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.border),

          if (fields.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Column(children: [
                Icon(Icons.dynamic_form_outlined, size: 36, color: AppColors.textHint.withValues(alpha: 0.5)),
                const SizedBox(height: 10),
                Text('No custom fields yet', style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textHint)),
                const SizedBox(height: 4),
                Text('Tap "Add Field" to create one', style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textHint)),
              ])),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: fields.length,
              onReorder: onReorder,
              buildDefaultDragHandles: false,
              itemBuilder: (_, i) => _FieldCard(
                key: ValueKey(fields[i].id),
                field: fields[i], index: i,
                onRemove: () => onRemove(i),
                onUpdate: (f) => onUpdate(i, f),
              ),
            ),

          if (fields.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                const Icon(Icons.drag_indicator_rounded, size: 13, color: AppColors.textHint),
                const SizedBox(width: 6),
                Text('Drag to reorder', style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textHint)),
              ]),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// INDIVIDUAL FIELD CARD
// ─────────────────────────────────────────────────────────

class _FieldCard extends StatefulWidget {
  final CustomField field;
  final int index;
  final VoidCallback onRemove;
  final void Function(CustomField) onUpdate;

  const _FieldCard({super.key, required this.field, required this.index,
      required this.onRemove, required this.onUpdate});

  @override
  State<_FieldCard> createState() => _FieldCardState();
}

class _FieldCardState extends State<_FieldCard> {
  late TextEditingController _labelCtrl;
  late TextEditingController _optionCtrl;
  late List<String> _options;

  @override
  void initState() {
    super.initState();
    _labelCtrl  = TextEditingController(text: widget.field.label);
    _optionCtrl = TextEditingController();
    _options    = List.from(widget.field.options);
  }

  @override
  void dispose() { _labelCtrl.dispose(); _optionCtrl.dispose(); super.dispose(); }

  void _emit({String? label, CustomFieldType? type, bool? required, List<String>? options}) =>
      widget.onUpdate(widget.field.copyWith(
        label:    label    ?? widget.field.label,
        type:     type     ?? widget.field.type,
        required: required ?? widget.field.required,
        options:  options  ?? _options,
      ));

  void _addOption() {
    final v = _optionCtrl.text.trim();
    if (v.isEmpty) return;
    setState(() { _options.add(v); _optionCtrl.clear(); });
    _emit(options: List.from(_options));
  }

  void _removeOption(int i) {
    setState(() => _options.removeAt(i));
    _emit(options: List.from(_options));
  }

  bool get _isDropdown => widget.field.type == CustomFieldType.dropdown;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.background,
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Row 1: drag + badge + label + delete
      Row(children: [
        ReorderableDragStartListener(
          index: widget.index,
          child: const Icon(Icons.drag_indicator_rounded, size: 20, color: AppColors.textHint),
        ),
        const SizedBox(width: 8),
        Container(
          width: 22, height: 22,
          decoration: const BoxDecoration(color: AppColors.primarySurface, shape: BoxShape.circle),
          child: Center(child: Text('${widget.index + 1}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary))),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: _labelCtrl,
            onChanged: (v) => _emit(label: v),
            textInputAction: TextInputAction.done,
            style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Field label, e.g. "Blood Group"',
              hintStyle: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textHint),
              filled: true, fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: widget.onRemove,
          icon: const Icon(Icons.delete_outline_rounded, size: 20),
          color: AppColors.error, tooltip: 'Remove',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ]),
      const SizedBox(height: 12),

      // Row 2: type selector + required toggle
      Row(children: [
        const SizedBox(width: 40),
        Expanded(
          child: _TypeSelector(
            value: widget.field.type,
            onChange: (t) { if (t != null) _emit(type: t); },
          ),
        ),
        const SizedBox(width: 12),
        Row(children: [
          Transform.scale(scale: 0.82,
            child: Switch.adaptive(
              value: widget.field.required,
              onChanged: (v) => _emit(required: v),
              activeThumbColor: AppColors.primary,
            ),
          ),
          Text('Required', style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        ]),
      ]),

      // Dropdown options
      if (_isDropdown) ...[
        const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.only(left: 40),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Dropdown Options', style: GoogleFonts.dmSans(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
            const SizedBox(height: 8),
            ..._options.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                const Icon(Icons.radio_button_unchecked_rounded, size: 14, color: AppColors.textHint),
                const SizedBox(width: 8),
                Expanded(child: Text(e.value, style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textPrimary))),
                GestureDetector(
                  onTap: () => _removeOption(e.key),
                  child: const Icon(Icons.close_rounded, size: 16, color: AppColors.error),
                ),
              ]),
            )),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _optionCtrl,
                  onFieldSubmitted: (_) => _addOption(),
                  style: GoogleFonts.dmSans(fontSize: 13),
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'Add an option...',
                    hintStyle: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textHint),
                    filled: true, fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 38,
                child: ElevatedButton(
                  onPressed: _addOption,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Icon(Icons.add_rounded, size: 18),
                ),
              ),
            ]),
          ]),
        ),
      ],
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
// TYPE SELECTOR (segmented)
// ═══════════════════════════════════════════════════════════

class _TypeSelector extends StatelessWidget {
  final CustomFieldType value;
  final void Function(CustomFieldType?) onChange;
  const _TypeSelector({required this.value, required this.onChange});

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    decoration: BoxDecoration(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: CustomFieldType.values.map((t) {
        final sel = t == value;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChange(t),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              decoration: BoxDecoration(
                color: sel ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Center(child: Text(
                _lbl(t),
                style: GoogleFonts.dmSans(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : AppColors.textHint),
              )),
            ),
          ),
        );
      }).toList(),
    ),
  );

  String _lbl(CustomFieldType t) => switch(t) {
    CustomFieldType.text     => 'Text',
    CustomFieldType.number   => 'Number',
    CustomFieldType.dropdown => 'Dropdown',
  };
}

// ═══════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
    child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 10), child: Row(children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(title, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ])),
      Container(height: 1, color: AppColors.border),
      ...children,
    ]),
  );
}

class _RowDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(height: 1, color: AppColors.border);
}

class _NumRow extends StatelessWidget {
  final String label, subtitle, suffix;
  final TextEditingController ctrl;
  const _NumRow({required this.label, required this.subtitle, required this.ctrl, required this.suffix});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(children: [
      Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
      ])),
      const SizedBox(width: 16),
      SizedBox(width: 110, child: TextFormField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
        decoration: InputDecoration(
          suffixText: suffix,
          suffixStyle: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          filled: true, fillColor: AppColors.primarySurface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        ),
      )),
    ]),
  );
}

class _TimeRow extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final VoidCallback onTap;
  const _TimeRow({required this.label, required this.ctrl, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(children: [
      Expanded(flex: 3, child: Text(label, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
      const SizedBox(width: 16),
      GestureDetector(
        onTap: onTap,
        child: AbsorbPointer(child: SizedBox(width: 110, child: TextFormField(
          controller: ctrl, textAlign: TextAlign.center,
          style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary),
          decoration: InputDecoration(
            suffixIcon: const Icon(Icons.schedule_rounded, size: 14, color: AppColors.textSecondary),
            filled: true, fillColor: AppColors.primarySurface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ))),
      ),
    ]),
  );
}

class _ToggleRow extends StatelessWidget {
  final String label, subtitle;
  final bool value;
  final void Function(bool) onChanged;
  const _ToggleRow({required this.label, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
      ])),
      Switch.adaptive(value: value, onChanged: onChanged, activeThumbColor: AppColors.primary),
    ]),
  );
}

class _Banner extends StatelessWidget {
  final String message;
  final bool isError;
  const _Banner({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    final bg     = isError ? const Color(0xFFFFF1F1) : const Color(0xFFECFDF3);
    final border = isError ? const Color(0xFFFFCDD2) : const Color(0xFFA7F3D0);
    final fg     = isError ? AppColors.error : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
      child: Row(children: [
        Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: fg, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
    );
  }
}