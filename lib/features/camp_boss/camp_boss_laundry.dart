// ⚠️ DEPRECATED — مَهجور
// الكود القَديم لِلمَغسلة حُذِف وَتَمّ استِبداله بِالموديول الجَديد "أَمانة"
// المَكان الجَديد: lib/features/laundry/
//
// يَبقى هَذا الملف فارِغاً مُؤَقَّتاً لِتَفادي كَسر أَيّ imports قَديمة،
// وَسَيُحذَف نِهائيّاً بَعد إتمام الـmigration الكامِل.

import 'package:flutter/material.dart';

class CampBossLaundry extends StatelessWidget {
  const CampBossLaundry({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '🧺 موديول المَغسلة يُعاد بِناؤه ضِمن نِظام "أَمانة" الجَديد',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
