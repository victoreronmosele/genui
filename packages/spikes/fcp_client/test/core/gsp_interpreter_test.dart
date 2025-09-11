// Copyright 2025 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:fcp_client/fcp_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GspInterpreter', () {
    late StreamController<String> streamController;
    late GspInterpreter interpreter;

    setUp(() {
      streamController = StreamController<String>();
      interpreter = GspInterpreter(
        stream: streamController.stream,
        catalog: WidgetCatalog(
          catalogVersion: '1.0.0',
          dataTypes: <String, Object?>{},
          items: <String, WidgetDefinition?>{},
        ),
      );
    });

    test('initializes with correct default values', () {
      expect(interpreter.isReadyToRender, isFalse);
      expect(interpreter.currentState, isEmpty);
      expect(interpreter.currentLayout, isNull);
    });

    testWidgets('processes StreamHeader and initializes state', (
      WidgetTester tester,
    ) async {
      streamController.add(
        '{"messageType": "StreamHeader", "formatVersion": "1.0.0", '
        '"initialState": {"count": 1}}',
      );
      await tester.pump();
      expect(interpreter.currentState['count'], 1);
    });

    testWidgets('processes Layout and buffers nodes', (
      WidgetTester tester,
    ) async {
      streamController.add(
        '{"messageType": "Layout", "nodes": [{"id": "node1", "type": "Text"}]}',
      );
      await tester.pump();
      expect(interpreter.currentLayout, isNull);
      expect(interpreter.isReadyToRender, isFalse);
    });

    testWidgets(
      'processes multiple Layout messages and merges nodes',
      (WidgetTester tester) async {
        streamController.add(
          '{"messageType": "Layout", "nodes": [{"id": "node1", "type": "Text"}]}',
        );
        await tester.pump();
        streamController.add(
          '{"messageType": "Layout", "nodes": [{"id": "node2", "type": "Column"}]}',
        );
        streamController.add('{"messageType": "LayoutRoot", "rootId": "node1"}');
        await tester.pump();
        expect(interpreter.isReadyToRender, isTrue);
        expect(interpreter.currentLayout!.nodes.length, 2);
      },
    );

    testWidgets(
      'processes LayoutRoot and sets isReadyToRender when root is buffered',
      (WidgetTester tester) async {
        streamController.add(
          '{"messageType": "Layout", "nodes": '
          '[{"id": "root", "type": "Text"}]}',
        );
        streamController.add('{"messageType": "LayoutRoot", "rootId": "root"}');
        await tester.pump();
        expect(interpreter.isReadyToRender, isTrue);
        expect(interpreter.currentLayout, isNotNull);
        expect(interpreter.currentLayout!.root, 'root');
      },
    );

    testWidgets(
      'processes LayoutRoot before node is buffered, then sets isReadyToRender',
      (WidgetTester tester) async {
        streamController.add('{"messageType": "LayoutRoot", "rootId": "root"}');
        await tester.pump();
        expect(interpreter.isReadyToRender, isFalse);
        streamController.add(
          '{"messageType": "Layout", '
          '"nodes": [{"id": "root", "type": "Text"}]}',
        );
        await tester.pump();
        expect(interpreter.isReadyToRender, isTrue);
      },
    );

    testWidgets('processes StateUpdate and updates state', (
      WidgetTester tester,
    ) async {
      streamController.add(
        '{"messageType": "StreamHeader", "formatVersion": "1.0.0", '
        '"initialState": {"count": 1}}',
      );
      await tester.pump();
      streamController.add(
        '{"messageType": "StateUpdate", "state": {"count": 2}}',
      );
      await tester.pump();
      expect(interpreter.currentState['count'], 2);
    });

    testWidgets('notifies listeners on change', (WidgetTester tester) async {
      int callCount = 0;
      interpreter.addListener(() => callCount++);

      streamController.add(
        '{"messageType": "StreamHeader", "formatVersion": "1.0.0", '
        '"initialState": {"count": 1}}',
      );
      await tester.pump();
      expect(callCount, 1);

      streamController.add(
        '{"messageType": "Layout", "nodes": [{"id": "node1", "type": "Text"}]}',
      );
      await tester.pump();
      expect(callCount, 2);

      streamController.add('{"messageType": "LayoutRoot", "rootId": "node1"}');
      await tester.pump();
      expect(callCount, 3);

      streamController.add(
        '{"messageType": "StateUpdate", "state": {"count": 2}}',
      );
      await tester.pump();
      expect(callCount, 4);
    });

    testWidgets('handles empty message string gracefully', (
      WidgetTester tester,
    ) async {
      int callCount = 0;
      interpreter.addListener(() => callCount++);
      streamController.add('');
      await tester.pump();
      expect(callCount, 0);
    });

    testWidgets('handles malformed JSON gracefully', (
      WidgetTester tester,
    ) async {
      expect(
        () => interpreter.processMessage('{"messageType": "Layout", "nodes":'),
        throwsFormatException,
      );
    });

    testWidgets('handles unknown message type gracefully', (
      WidgetTester tester,
    ) async {
      expect(
        () => interpreter.processMessage('{"messageType": "Unknown"}'),
        throwsFormatException,
      );
    });
  });
}
