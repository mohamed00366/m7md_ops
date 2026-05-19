import 'package:flutter/material.dart';
import '../models/policies.dart';

/// 5 سياسات أساسية للشركة - بيانات تجريبية
List<Policy> seedPolicies(String Function() generateId) {
  final now = DateTime.now();

  return [
    // ============ 1) سياسة الدوام والحضور ============
    Policy(
      id: generateId(),
      titleAr: 'سياسة الدوام والحضور',
      titleEn: 'Attendance & Schedule Policy',
      summaryAr: 'مواعيد الدوام، خطوات تسجيل الحضور، وقواعد التأخير',
      summaryEn: 'Working hours, check-in steps, and lateness rules',
      category: PolicyCategory.attendance,
      updatedAt: now.subtract(const Duration(days: 30)),
      sections: [
        const PolicySection(
          titleAr: 'مواعيد الدوام الرسمية',
          titleEn: 'Official Working Hours',
          icon: Icons.access_time,
          bodyAr:
              'الدوام الرسمي من الساعة 8:00 صباحاً إلى الساعة 4:00 مساءً، خمسة أيام في الأسبوع (السبت - الأربعاء). الجمعة والخميس عطلة أسبوعية.',
          bodyEn:
              'Official hours: 8:00 AM to 4:00 PM, five days a week (Sat–Wed). Friday and Thursday are weekly off.',
        ),
        const PolicySection(
          titleAr: 'خطوات تسجيل الحضور',
          titleEn: 'Check-in Steps',
          icon: Icons.checklist,
          stepsAr: [
            'افتح التطبيق قبل وقت بدء الدوام بـ 15 دقيقة',
            'تأكد من ظهور موقع العمل المخصص لك في شاشة الدوام',
            'سجّل وقت الوصول الفعلي في حقل "وقت البداية"',
            'إذا انتقلت لموقع آخر خلال اليوم، اضغط "إضافة تسجيل آخر"',
            'في نهاية اليوم، سجّل وقت المغادرة واضغط "حفظ سجل اليوم"',
          ],
          stepsEn: [
            'Open the app 15 minutes before shift start',
            'Verify your assigned work location appears in the schedule',
            'Log your actual arrival time in the "Start Time" field',
            'If moving to another location, tap "Add another log"',
            'At end of day, log your departure time and tap "Save Day Log"',
          ],
        ),
        const PolicySection(
          titleAr: 'سياسة التأخير',
          titleEn: 'Lateness Policy',
          icon: Icons.warning_amber,
          stepsAr: [
            'تأخير أقل من 10 دقائق: تنبيه شفوي',
            'تأخير من 10 إلى 30 دقيقة: خصم نصف ساعة من الراتب',
            'تأخير أكثر من 30 دقيقة: خصم يوم كامل + إنذار رسمي',
            '3 إنذارات في الشهر تستوجب خطاباً إدارياً',
          ],
          stepsEn: [
            'Less than 10 min late: verbal warning',
            '10–30 min late: half-hour salary deduction',
            'Over 30 min late: full day deduction + formal warning',
            '3 warnings per month trigger an official letter',
          ],
        ),
      ],
    ),

    // ============ 2) سياسة الإجازات ============
    Policy(
      id: generateId(),
      titleAr: 'سياسة الإجازات',
      titleEn: 'Vacation Policy',
      summaryAr: 'أنواع الإجازات وخطوات تقديم الطلب ومدة الموافقة',
      summaryEn: 'Leave types, request steps, and approval time',
      category: PolicyCategory.vacation,
      updatedAt: now.subtract(const Duration(days: 60)),
      sections: [
        const PolicySection(
          titleAr: 'أنواع الإجازات',
          titleEn: 'Leave Types',
          icon: Icons.event_available,
          stepsAr: [
            'إجازة سنوية: 30 يوم مدفوعة (تتراكم سنوياً)',
            'إجازة مرضية: 15 يوم مدفوعة بشهادة طبية',
            'إجازة طارئة: 5 أيام في السنة بدون إخطار مسبق',
            'إجازة بدون راتب: حسب موافقة الإدارة',
            'إجازة أمومة/أبوة: حسب نظام العمل',
          ],
          stepsEn: [
            'Annual leave: 30 paid days (accrued yearly)',
            'Sick leave: 15 paid days with medical certificate',
            'Emergency leave: 5 days/year without prior notice',
            'Unpaid leave: subject to management approval',
            'Maternity/Paternity leave: per labor law',
          ],
        ),
        const PolicySection(
          titleAr: 'خطوات تقديم طلب إجازة',
          titleEn: 'Steps to Request Leave',
          icon: Icons.assignment_turned_in_outlined,
          stepsAr: [
            'افتح شاشة "الطلبات" في التطبيق',
            'اضغط بطاقة "طلب إجازة"',
            'اختر نوع الإجازة (سنوية، مرضية، طارئة...)',
            'حدد تاريخ البداية والنهاية',
            'أرفق المستندات الداعمة (شهادة طبية للمرضية)',
            'اكتب سبب الإجازة باختصار',
            'اضغط "إرسال" وانتظر موافقة الإدارة',
          ],
          stepsEn: [
            'Open the "Requests" screen in the app',
            'Tap "New Leave Request" card',
            'Choose leave type (annual, sick, emergency...)',
            'Set start and end dates',
            'Attach supporting documents (medical certificate for sick leave)',
            'Briefly state the reason',
            'Tap "Submit" and await management approval',
          ],
        ),
        const PolicySection(
          titleAr: 'مدة الموافقة المتوقعة',
          titleEn: 'Expected Approval Time',
          icon: Icons.timer_outlined,
          bodyAr:
              'الإجازة الطارئة: خلال 4 ساعات. الإجازة السنوية والمرضية: خلال 24-48 ساعة عمل. الإجازة بدون راتب: قد تأخذ حتى 3 أيام.',
          bodyEn:
              'Emergency leave: within 4 hours. Annual & sick: within 24–48 working hours. Unpaid leave: up to 3 days.',
        ),
      ],
    ),

    // ============ 3) سياسة السكن والمغسلة ============
    Policy(
      id: generateId(),
      titleAr: 'سياسة السكن والمغسلة',
      titleEn: 'Housing & Laundry Policy',
      summaryAr: 'قواعد السكن وخطوات تسليم الملابس واستلامها',
      summaryEn: 'Housing rules and laundry pickup/return steps',
      category: PolicyCategory.housing,
      updatedAt: now.subtract(const Duration(days: 14)),
      sections: [
        const PolicySection(
          titleAr: 'قواعد السكن',
          titleEn: 'Housing Rules',
          icon: Icons.home_outlined,
          stepsAr: [
            'الحفاظ على نظافة الغرفة بشكل يومي',
            'الزوار غير مسموح بهم بعد الساعة 10 مساءً',
            'الالتزام بالهدوء بعد الساعة 11 مساءً',
            'ممنوع التدخين داخل المباني',
            'إبلاغ الكمب بوص فوراً بأي عطل أو مشكلة',
            'يمنع تبادل الغرف دون موافقة رسمية',
          ],
          stepsEn: [
            'Keep your room clean daily',
            'No visitors allowed after 10:00 PM',
            'Maintain silence after 11:00 PM',
            'No smoking inside buildings',
            'Report any malfunction to camp boss immediately',
            'No room swapping without official approval',
          ],
        ),
        const PolicySection(
          titleAr: 'خطوات تسليم الملابس للمغسلة',
          titleEn: 'Laundry Drop-off Steps',
          icon: Icons.local_laundry_service_outlined,
          stepsAr: [
            'سلّم القطع المتسخة لكمب بوص في أوقات الاستلام (6-8 صباحاً)',
            'تأكد من حصولك على إيصال برقم تذكرة',
            'احتفظ بالإيصال حتى استلام الغسيل',
            'استلم الملابس النظيفة خلال 48 ساعة',
            'في حال نقص أي قطعة، أبلغ خلال 24 ساعة من الاستلام',
          ],
          stepsEn: [
            'Hand dirty items to camp boss during pickup hours (6–8 AM)',
            'Ensure you receive a receipt with ticket number',
            'Keep the receipt until you collect your laundry',
            'Collect clean clothes within 48 hours',
            'Report any missing item within 24 hours of return',
          ],
        ),
      ],
    ),

    // ============ 4) قواعد السلوك المهني ============
    Policy(
      id: generateId(),
      titleAr: 'قواعد السلوك المهني',
      titleEn: 'Professional Conduct',
      summaryAr: 'المظهر العام والتعامل مع الزملاء والعملاء',
      summaryEn: 'Personal appearance and interactions with colleagues/clients',
      category: PolicyCategory.conduct,
      updatedAt: now.subtract(const Duration(days: 90)),
      sections: [
        const PolicySection(
          titleAr: 'المظهر العام',
          titleEn: 'Personal Appearance',
          icon: Icons.checkroom_outlined,
          stepsAr: [
            'ارتداء الزي الموحد بالكامل وبشكل نظيف ومرتّب',
            'الحلاقة المنتظمة والمظهر اللائق',
            'بطاقة التعريف ظاهرة طوال ساعات الدوام',
            'الالتزام بالأحذية المعتمدة فقط',
          ],
          stepsEn: [
            'Wear the full uniform clean and tidy',
            'Maintain regular grooming and a presentable look',
            'Wear ID badge visibly during all shift hours',
            'Use only approved footwear',
          ],
        ),
        const PolicySection(
          titleAr: 'التعامل مع الزملاء والعملاء',
          titleEn: 'Interactions with Colleagues & Clients',
          icon: Icons.handshake_outlined,
          stepsAr: [
            'الاحترام المتبادل في كل التعاملات',
            'استخدام لغة لائقة في الحديث',
            'تجنّب النقاشات السياسية أو الدينية في العمل',
            'التعامل مع شكاوى العملاء بمهنية وإحالتها للمشرف',
            'عدم نشر أي محتوى يتعلق بالعمل على وسائل التواصل بدون إذن',
          ],
          stepsEn: [
            'Mutual respect in all interactions',
            'Use professional language always',
            'Avoid political or religious discussions at work',
            'Handle client complaints professionally; escalate to supervisor',
            'Do not post any work-related content on social media without permission',
          ],
        ),
      ],
    ),

    // ============ 5) إجراءات الطوارئ ============
    Policy(
      id: generateId(),
      titleAr: 'إجراءات الطوارئ',
      titleEn: 'Emergency Procedures',
      summaryAr: 'خطوات حالة الحريق وأرقام الطوارئ المهمة',
      summaryEn: 'Fire procedures and important emergency numbers',
      category: PolicyCategory.emergency,
      updatedAt: now.subtract(const Duration(days: 7)),
      sections: [
        const PolicySection(
          titleAr: 'خطوات حالة الحريق',
          titleEn: 'Fire Emergency Steps',
          icon: Icons.local_fire_department_outlined,
          stepsAr: [
            'لا تذعر، حافظ على الهدوء',
            'استخدم أقرب مخرج طوارئ - لا تستخدم المصاعد أبداً',
            'توجّه إلى نقطة التجمع الخارجية المحددة',
            'أبلغ المشرف بأنك خرجت بأمان واتصل بالطوارئ',
          ],
          stepsEn: [
            'Don\'t panic, stay calm',
            'Use the nearest emergency exit — never use elevators',
            'Go to the designated outdoor assembly point',
            'Inform your supervisor you\'re safe and call emergency services',
          ],
        ),
        const PolicySection(
          titleAr: 'أرقام الطوارئ',
          titleEn: 'Emergency Contacts',
          icon: Icons.phone_in_talk_outlined,
          stepsAr: [
            'الدفاع المدني والإطفاء: 998',
            'الإسعاف: 997',
            'الشرطة: 999',
            'مدير الموقع (24 ساعة): اطلب من المشرف الرقم الحالي',
            'كمب بوص (الطوارئ السكنية): متوفر داخل التطبيق',
          ],
          stepsEn: [
            'Civil Defense / Fire: 998',
            'Ambulance: 997',
            'Police: 999',
            'Site Manager (24h): ask supervisor for current number',
            'Camp Boss (housing emergencies): available in app',
          ],
        ),
      ],
    ),
  ];
}
