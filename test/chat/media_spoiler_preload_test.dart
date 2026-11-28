import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/media_spoiler.dart';

void main() {
  testWidgets('a hidden spoiler announces itself once, so the media preloads', (
    tester,
  ) async {
    var announced = 0;
    Widget build() => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: MediaSpoiler(
              identity: 1,
              enabled: true,
              onCoverBuilt: () => announced++,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(build());
    expect(announced, 1);
    await tester.pumpWidget(build());
    expect(announced, 1, reason: 'a rebuild is not a new cover');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('without a spoiler nothing is announced', (tester) async {
    var announced = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaSpoiler(
            identity: 2,
            enabled: false,
            onCoverBuilt: () => announced++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    expect(announced, 0);
  });
}
