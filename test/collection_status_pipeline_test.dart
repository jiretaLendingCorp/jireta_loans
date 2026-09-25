// test/collection_status_pipeline_test.dart
//
// COLLECTION STATUS — HORIZONTAL PIPELINE (Collection Details, HM + Employee)
//
// DATI: vertical na listahan ng check rows (Requested / Assigned / Accepted /
// …) na naka-stack pababa, kaya matangkad ang card at hindi kita agad ang
// progreso sa isang tingin.
//
// NGAYON: horizontal pipeline/stepper — dots na may connector sa pagitan,
// kaparehong wika ng "Workflow Progress" stepper ng CI details:
//   • berde  = tapos nang stage
//   • asul   = kasalukuyang stage
//   • pula   = bigong stage (rejected)
//   • abuhin = hindi pa narating
// Nasa makitid na screen (< 720px) lang ang vertical na bersyon.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _hmScreen =
    'lib/presentation/features/head_manager/collections/screens/hm_collection_details_screen.dart';
const _empScreen =
    'lib/presentation/features/employee/collections/screens/emp_collection_details_screen.dart';

String _readNormalized(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

/// Ang `_buildStatusCard` hanggang sa dulo ng `_pipelineDot` — normalize sa
/// isang linya para hindi dipende sa formatting ang mga assertion.
String _pipelineBlock(String source) {
  final start = source.indexOf('Widget _buildStatusCard(');
  final end = source.indexOf('Future<void> _approveCollection(');
  expect(start, greaterThanOrEqualTo(0), reason: 'walang _buildStatusCard');
  expect(end, greaterThan(start), reason: 'hindi mahanap ang dulo ng block');
  return source
      .substring(start, end)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

void main() {
  group('Source guard: horizontal pipeline ang Collection Status', () {
    for (final screen in {_hmScreen, _empScreen}) {
      final name = screen.split('/').last;

      test('$name: horizontal kapag malawak, vertical kapag makitid', () {
        final block = _pipelineBlock(_readNormalized(screen));

        expect(block, contains('_buildHorizontalPipeline(steps, activeIndex'),
            reason: 'Nawala ang horizontal pipeline');
        expect(block, contains('_buildVerticalPipeline(steps, activeIndex'),
            reason: 'Nawala ang vertical fallback para sa mobile');
        expect(block, contains('c.maxWidth >= 720'),
            reason: 'Nawala ang breakpoint ng horizontal/vertical');
      });

      test('$name: berde/asul/pula ang mga stage dot', () {
        final block = _pipelineBlock(_readNormalized(screen));

        expect(block, contains('AppColors.riderGreen'),
            reason: 'Nawala ang kulay ng tapos nang stage');
        expect(block, contains('AppColors.lenderBlue'),
            reason: 'Nawala ang kulay ng kasalukuyang stage');
        expect(block, contains('AppColors.error'),
            reason: 'Nawala ang pulang stage ng rejected');
        // May connector na linya sa pagitan ng mga dot.
        expect(block, contains('_pipelineDot'));
      });

      test('$name: hindi na vertical checklist ang mga stage', () {
        final src = _readNormalized(screen);

        // Ang lumang vertical checklist rows ay dapat tuluyang nawala.
        expect(src, isNot(contains('_StatusRow(')));
        expect(src, isNot(contains('class _StatusRow')));
      });
    }

    test('HM at Employee: pareho ang pipeline block (sync rule)', () {
      expect(_pipelineBlock(_readNormalized(_empScreen)),
          _pipelineBlock(_readNormalized(_hmScreen)),
          reason:
              'Dapat kapareho ng HM ang Employee screen — i-run ang scripts/sync_employee_screens.py');
    });
  });
}
