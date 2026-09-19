import 'package:flutter/material.dart';

import '../constants/app_config.dart';

/// Scrollable, centred content column capped at [AppConfig.maxContentWidth]
/// so layouts stay readable from small phones to tablets.
class ResponsiveBody extends StatelessWidget {
  /// Creates a responsive body.
  const ResponsiveBody({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24),
  });

  /// Column children.
  final List<Widget> children;

  /// Inner padding.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: padding,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppConfig.maxContentWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}
