import 'package:flutter/material.dart';

/// مزوّد إشارة من Unified Home لتمكين Smart Home من فتح موديولات
/// نستخدم InheritedWidget لتفادي circular imports
class SmartHomeNavigator extends InheritedWidget {
  final void Function(String moduleKey) onOpenModule;

  const SmartHomeNavigator({
    super.key,
    required this.onOpenModule,
    required super.child,
  });

  static SmartHomeNavigator? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SmartHomeNavigator>();
  }

  @override
  bool updateShouldNotify(SmartHomeNavigator oldWidget) =>
      oldWidget.onOpenModule != onOpenModule;
}
