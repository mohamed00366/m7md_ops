// ⚠️ DEPRECATED — مَهجور، يُعاد بِناؤه في lib/features/laundry/employee/
//
// شاشة "المَغسلة" في تَطبيق المُوَظَّف ستُبنى مِن جَديد ضِمن نِظام "أَمانة"
// مَع شَريط حالة الكَمب بُوص + طَلَب جَديد + سَنَداتي + بَلاغاتي.

import 'package:flutter/material.dart';

class EmployeeLaundry extends StatelessWidget {
  const EmployeeLaundry({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '🧺 المَغسلة قَيد إعادة البِناء (نِظام أَمانة)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
