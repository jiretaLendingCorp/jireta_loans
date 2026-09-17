// lib/presentation/shared/widgets/philippines_address_field.dart
//
// Reusable Philippine address picker (official PSA data via philippines_rpcmb)
// — Region → Province → City/Municipality → Barangay (+ free-text Street).
// It emits ONE composed address string so callers that store a single
// `address` column (e.g. loan emergency contacts, co-makers) can keep their
// existing payload shape while giving the user the standardized cascade.
import 'package:flutter/material.dart';
import 'package:philippines_rpcmb/philippines_rpcmb.dart';

import '../../../core/theme/app_colors.dart';

/// Hinahanap ang Region ng isang City/Municipality name sa PSG/PSA data.
///
/// Kailangan ito ng prefill: ang `addresses` / `application_addresses` table
/// ay hindi nag-iimbak ng Region (street / barangay / city / province lang) —
/// kaya kapag nag-prefill mula sa DB, hindi na kailangang piliin muli ng user
/// ang Region dropdown.
String? philippineRegionForCity(String? city) {
  final c = (city ?? '').trim().toLowerCase();
  if (c.isEmpty) return null;
  for (final r in philippineRegions) {
    for (final p in r.provinces) {
      for (final m in p.municipalities) {
        if (m.name.toLowerCase() == c) return r.regionName;
      }
    }
  }
  return null;
}

class PhilippinesAddressField extends StatefulWidget {
  final String label;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  // ── Prefill (opsyonal) — para sa mga edit/continue form na may existing na
  // address sa `addresses` table. Ang mga pangalan ay tinutugma sa opisyal na
  // PSA list (case-insensitive); kapag walang tugma, blangko na lang ang
  // dropdown (hindi ito error).
  final String? initialStreet;
  final String? initialRegion;
  final String? initialProvince;
  final String? initialCity;
  final String? initialBarangay;

  const PhilippinesAddressField({
    super.key,
    this.label = 'Address',
    this.errorText,
    this.onChanged,
    this.initialStreet,
    this.initialRegion,
    this.initialProvince,
    this.initialCity,
    this.initialBarangay,
  });

  @override
  State<PhilippinesAddressField> createState() =>
      PhilippinesAddressFieldState();
}

class PhilippinesAddressFieldState extends State<PhilippinesAddressField> {
  final _streetCtrl = TextEditingController();
  // Kapag na-focus ang Street / House No., hintayin ang keyboard animation at
  // i-scroll ito sa gitna ng viewport — kung hindi, natatakpan ito ng keyboard
  // (lalo na kapag huling field ito ng address cascade).
  final _streetFocus = FocusNode();
  final _streetFieldKey = GlobalKey();
  Region? _region;
  Province? _province;
  Municipality? _municipality;
  String? _barangay;
  bool _attempted = false;

  bool get isValid =>
      _streetCtrl.text.trim().isNotEmpty &&
      _region != null &&
      _province != null &&
      _municipality != null &&
      (_barangay != null && _barangay!.trim().isNotEmpty);

  String get composedAddress {
    final parts = <String>[
      _streetCtrl.text.trim(),
      _barangay ?? '',
      _municipality?.name ?? '',
      _province?.name ?? '',
      _region?.regionName ?? '',
    ].where((p) => p.isNotEmpty).toList();
    return parts.join(', ');
  }

  // ── Structured parts (for callers that persist to the normalized
  // `addresses` table instead of a single free-text column). ──────────────
  String get street => _streetCtrl.text.trim();
  String? get barangay => _barangay;
  String? get city => _municipality?.name;
  String? get province => _province?.name;
  String? get region => _region?.regionName;

  /// Reveals the inline required errors and reports whether the address is
  /// complete. Call this from the parent's Next/Submit validation.
  bool validate() {
    setState(() => _attempted = true);
    return isValid;
  }

  /// Itago muli ang inline errors nang hindi binabago ang napiling address —
  /// ginagamit ng mga parent na may 2-second auto-hide ng validation errors
  /// (hal. Lender Account Upgrade wizard).
  void clearErrors() {
    if (!_attempted) return;
    setState(() => _attempted = false);
  }

  @override
  void initState() {
    super.initState();
    _streetFocus.addListener(_onStreetFocus);
    _applyInitialValues();
  }

  /// Prefill mula sa [PhilippinesAddressField.initialStreet] at ng mga
  /// initial na pangalan ng Region/Province/City/Barangay (tugma sa PSA list).
  void _applyInitialValues() {
    _streetCtrl.text = widget.initialStreet?.trim() ?? '';
    // Region: direktang ipinasa, o kung wala (hindi ito nakaimbak sa DB)
    // hinahanap mula sa city/province name ng PSA data.
    final explicitRegion = widget.initialRegion?.trim() ?? '';
    final regionName = explicitRegion.isNotEmpty
        ? explicitRegion.toLowerCase()
        : philippineRegionForCity(widget.initialCity)?.toLowerCase();
    final provinceName = widget.initialProvince?.trim().toLowerCase();
    final cityName = widget.initialCity?.trim().toLowerCase();
    final barangayName = widget.initialBarangay?.trim().toLowerCase();

    if (regionName != null && regionName.isNotEmpty) {
      _region = philippineRegions
          .where((r) => r.regionName.toLowerCase() == regionName)
          .firstOrNull;
    }
    final provinces = _region?.provinces ?? const <Province>[];
    if (provinceName != null && provinceName.isNotEmpty) {
      _province =
          provinces.where((p) => p.name.toLowerCase() == provinceName).firstOrNull;
    }
    final municipalities = _province?.municipalities ?? const <Municipality>[];
    if (cityName != null && cityName.isNotEmpty) {
      _municipality = municipalities
          .where((m) => m.name.toLowerCase() == cityName)
          .firstOrNull;
    }
    final barangays = _municipality?.barangays ?? const <String>[];
    if (barangayName != null && barangayName.isNotEmpty) {
      _barangay = barangays
          .where((b) => b.toLowerCase() == barangayName)
          .firstOrNull;
    }
  }

  void _onStreetFocus() {
    if (!_streetFocus.hasFocus) return;
    Future.delayed(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      final ctx = _streetFieldKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: 0.85,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
      }
    });
  }

  @override
  void dispose() {
    _streetFocus.removeListener(_onStreetFocus);
    _streetFocus.dispose();
    _streetCtrl.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged?.call(composedAddress);

  @override
  Widget build(BuildContext context) {
    final showErrors = _attempted || (widget.errorText?.isNotEmpty ?? false);
    final missing = showErrors && !isValid;

    const regions = philippineRegions;
    final provinces = _region?.provinces ?? const <Province>[];
    final municipalities = _province?.municipalities ?? const <Municipality>[];
    final barangays = _municipality?.barangays ?? const <String>[];

    Widget dropdown({
      Key? key,
      required String label,
      required String? value,
      required List<DropdownMenuItem<String>> items,
      required void Function(String?) onChanged,
    }) {
      return DropdownButtonFormField<String>(
        key: key,
        initialValue: value,
        isExpanded: true,
        decoration: _deco(label, errorText: null),
        items: items,
        onChanged: items.isEmpty ? null : onChanged,
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final pairUp = constraints.maxWidth >= 520;
      final regionDropdown = dropdown(
        label: 'Region *',
        value: _region?.regionName,
        items: regions
            .map((r) =>
                DropdownMenuItem(value: r.regionName, child: Text(r.regionName)))
            .toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _region = regions.where((r) => r.regionName == v).firstOrNull;
            _province = null;
            _municipality = null;
            _barangay = null;
          });
          _emit();
        },
      );
      final provinceDropdown = dropdown(
        key: ValueKey('paf-prov-${_region?.regionName ?? ''}'),
        label: 'Province *',
        value: _province?.name,
        items: provinces
            .map((p) => DropdownMenuItem(value: p.name, child: Text(p.name)))
            .toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _province = provinces.where((p) => p.name == v).firstOrNull;
            _municipality = null;
            _barangay = null;
          });
          _emit();
        },
      );
      final cityDropdown = dropdown(
        key: ValueKey('paf-city-${_province?.name ?? ''}'),
        label: 'City / Municipality *',
        value: _municipality?.name,
        items: municipalities
            .map((m) => DropdownMenuItem(value: m.name, child: Text(m.name)))
            .toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _municipality =
                municipalities.where((m) => m.name == v).firstOrNull;
            _barangay = null;
          });
          _emit();
        },
      );
      final barangayDropdown = dropdown(
        key: ValueKey('paf-brgy-${_municipality?.name ?? ''}'),
        label: 'Barangay *',
        value: _barangay,
        items: barangays
            .map((b) => DropdownMenuItem(value: b, child: Text(b)))
            .toList(),
        onChanged: (v) {
          setState(() => _barangay = v);
          _emit();
        },
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.errorText != null && widget.errorText!.isNotEmpty) ...[
            Text(
              widget.errorText!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
            const SizedBox(height: 8),
          ],
          if (pairUp)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: regionDropdown),
                const SizedBox(width: 10),
                Expanded(child: provinceDropdown),
              ],
            )
          else ...[
            regionDropdown,
            const SizedBox(height: 12),
            provinceDropdown,
          ],
          const SizedBox(height: 12),
          if (pairUp)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cityDropdown),
                const SizedBox(width: 10),
                Expanded(child: barangayDropdown),
              ],
            )
          else ...[
            cityDropdown,
            const SizedBox(height: 12),
            barangayDropdown,
          ],
          const SizedBox(height: 12),
          TextField(
            key: _streetFieldKey,
            controller: _streetCtrl,
            focusNode: _streetFocus,
            maxLength: 150,
            onChanged: (_) {
              setState(() {});
              _emit();
            },
            // Sapat na ang maliit na gap para tumaas lang nang bahagya ang
            // field sa ibabaw ng keyboard (dati: +120 → masyadong mataas).
            scrollPadding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24),
            decoration: _deco('Street / House No. *',
                errorText: missing && _streetCtrl.text.trim().isEmpty
                    ? 'Street address is required'
                    : null),
          ),
          if (missing && _region == null)
            const Padding(
              padding: EdgeInsets.only(top: 2, left: 12),
              child: Text('Please select Region, Province, City and Barangay',
                  style: TextStyle(fontSize: 11.5, color: AppColors.error)),
            ),
        ],
      );
    });
  }

  InputDecoration _deco(String label, {String? errorText}) => InputDecoration(
        labelText: label,
        counterText: '',
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        errorText: errorText,
        errorStyle: const TextStyle(fontSize: 11.5, color: AppColors.error),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: errorText != null ? AppColors.error : AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.lenderBlue),
        ),
      );
}
