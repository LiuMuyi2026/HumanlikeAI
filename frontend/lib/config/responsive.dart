import 'package:flutter/material.dart';

enum ScreenType { phone, tablet, desktop }

class Responsive {
  Responsive._();

  static ScreenType screenType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 600) return ScreenType.phone;
    if (width < 1024) return ScreenType.tablet;
    return ScreenType.desktop;
  }

  static T value<T>(
    BuildContext context, {
    required T phone,
    T? tablet,
    T? desktop,
  }) {
    return switch (screenType(context)) {
      ScreenType.phone => phone,
      ScreenType.tablet => tablet ?? phone,
      ScreenType.desktop => desktop ?? tablet ?? phone,
    };
  }

  static int gridColumns(BuildContext context) =>
      value(context, phone: 2, tablet: 3, desktop: 4);

  static double? maxContentWidth(BuildContext context) =>
      value<double?>(context, phone: null, tablet: 700, desktop: 800);

  static EdgeInsets contentPadding(BuildContext context) => EdgeInsets.symmetric(
        horizontal: value(context, phone: 16.0, tablet: 32.0, desktop: 48.0),
      );

  static Widget constrain(BuildContext context, {required Widget child}) {
    final maxWidth = maxContentWidth(context);
    if (maxWidth == null) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
