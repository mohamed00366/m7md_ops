// =============================================================================
// 🌐 تَرجَمات نِظام أَمانة — مَركَزيّ لِكُلّ الموديول (ar / en / ur)
// =============================================================================
// الاستِخدام:
//   final L = LaundryStrings.of(context);
//   Text(L.directReceive)     // → "استِلام مُباشِر" / "Direct Receive" / "براہ راست وصول"
// =============================================================================

import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../domain/models.dart';

class LaundryStrings {
  final AppStrings _s;
  LaundryStrings(this._s);

  static LaundryStrings of(BuildContext context) =>
      LaundryStrings(AppStrings.of(context));

  String _t(String ar, String en, [String? ur]) => _s.t(ar, en, ur);

  // ─── العَناوين الرَئيسيّة ───────────────────────────────────────
  String get amana => _t('أَمانة', 'Amana', 'امانہ');
  String get laundry => _t('المَغسلة', 'Laundry', 'لانڈری');
  String get myLaundry => _t('مَغسَلَتي (أَمانة)', 'My Laundry (Amana)', 'میری لانڈری (امانہ)');
  String get dashboard => _t('لَوحة الكَمب بُوص', 'Camp Boss Dashboard', 'کیمپ باس ڈیش بورڈ');

  // ─── الأَزرار الرَئيسيّة ─────────────────────────────────────────
  String get directReceive => _t('استِلام مُباشِر', 'Direct Receive', 'براہ راست وصول');
  String get directReceiveSub =>
      _t('الإجراء الرَئيسيّ — تَخَطّى الطَلَب', 'Main action — skip request',
          'مرکزی عمل — درخواست چھوڑیں');
  String get newRequest => _t('طَلَب جَديد', 'New Request', 'نئی درخواست');
  String get sendRequest => _t('طَلَب تَسليم جَديد', 'Submit New Request',
      'نئی درخواست بھیجیں');

  // ─── KPIs ────────────────────────────────────────────────────
  String get requests => _t('طَلَبات', 'Requests', 'درخواستیں');
  String get activeVouchers => _t('سَنَدات نَشطة', 'Active Vouchers', 'فعال ووچرز');
  String get inLaundry => _t('في المَغسلة', 'In Laundry', 'لانڈری میں');
  String get readyToDeliver => _t('جاهِزة لِلتَسليم', 'Ready to Deliver', 'حوالہ کیلئے تیار');
  String get openReports => _t('بَلاغات مَفتوحة', 'Open Reports', 'کھلی رپورٹس');
  String get history => _t('السِجِلّ', 'History', 'تاریخ');

  // ─── أَزرار ثانَويّة (CTAs) ──────────────────────────────────
  String get incomingRequests => _t('طَلَبات واردة', 'Incoming Requests', 'آنے والی درخواستیں');
  String get noRequests => _t('لا تُوجَد طَلَبات', 'No requests', 'کوئی درخواست نہیں');
  String get pendingRequestsHint =>
      _t('بانتِظار التَأكيد', 'pending confirmation', 'تصدیق کے انتظار میں');
  String get vouchersReady =>
      _t('جاهِزة لِلتَجميع', 'ready to batch', 'بیچ کیلئے تیار');
  String get batchesSection =>
      _t('الدُفعات + استِلام مِن المَغسلة', 'Batches + Receive from Laundry',
          'بیچز + لانڈری سے وصول');
  String get batchesInLaundry =>
      _t('دُفعة في المَغسلة', 'batch in laundry', 'بیچ لانڈری میں');
  String get readyForEmployeeDelivery =>
      _t('جاهِزة لِلتَسليم لِلمُوَظَّف', 'Ready to deliver to Employee',
          'ملازم کو حوالے کیلئے تیار');
  String get vouchersAwaitingDelivery =>
      _t('سَنَد يَنتَظِر التَسليم', 'voucher awaiting delivery',
          'ووچر حوالہ کا منتظر');
  String get noVoucherReady =>
      _t('لا يُوجَد سَنَد جاهِز', 'No voucher ready', 'کوئی ووچر تیار نہیں');
  String get missingReports => _t('بَلاغات المَفقودات', 'Missing Reports', 'گمشدہ رپورٹس');
  String get openReportsCount => _t('بَلاغ مَفتوح', 'open report', 'کھلی رپورٹ');
  String get noReports => _t('لا تُوجَد بَلاغات', 'No reports', 'کوئی رپورٹ نہیں');
  String get fullHistoryReports =>
      _t('السِجِلّ الكامِل + تَقارير', 'Full History + Reports', 'مکمل تاریخ + رپورٹس');
  String get allVouchersStats =>
      _t('كُلّ السَنَدات + الإحصاءات', 'All vouchers + statistics',
          'تمام ووچرز + شماریات');

  // ─── شاشة الاستِلام المُباشِر ────────────────────────────────
  String get searchEmployee =>
      _t('ابحَث بِالاسم أَو الكود أَو رَقَم الجَوّال...',
          'Search by name, code or mobile...',
          'نام، کوڈ یا موبائل سے تلاش کریں...');
  String get startSearch =>
      _t('اكتُب اسم أَو كود لِلبَدء', 'Type a name or code to start',
          'شروع کرنے کیلئے نام یا کوڈ لکھیں');
  String get noResults => _t('لا تُوجَد نَتائِج لِـ', 'No results for', 'کوئی نتیجہ نہیں');
  String get addEmployee => _t('إضافة مُوَظَّف جَديد', 'Add New Employee', 'نیا ملازم شامل کریں');
  String get addItem => _t('إضافة قِطعة', 'Add Item', 'آئٹم شامل کریں');
  String get addItemMore =>
      _t('إضافة + صَنف آخَر', 'Add + Another item', 'شامل کریں + ایک اور');
  String get addAndFinish =>
      _t('إضافة وَإنهاء', 'Add & Finish', 'شامل کر کے ختم');
  String get totalItems => _t('إجمالي القِطَع', 'Total Items', 'کل آئٹمز');
  String get optionalNote => _t('مُلاحَظة (اختِياريّ)', 'Note (optional)', 'نوٹ (اختیاری)');
  String get employeeSignature => _t('تَوقيع المُوَظَّف', 'Employee Signature', 'ملازم کا دستخط');
  String get confirmVoucher => _t('اعتِماد السَند', 'Confirm Voucher', 'ووچر تصدیق کریں');

  // ─── حالات السَنَد ─────────────────────────────────────────
  String voucherStatus(VoucherStatus st) {
    switch (st) {
      case VoucherStatus.confirmed:
        return _t('مُؤَكَّد', 'Confirmed', 'تصدیق شدہ');
      case VoucherStatus.inLaundry:
        return _t('في المَغسلة', 'In Laundry', 'لانڈری میں');
      case VoucherStatus.returnedComplete:
        return _t('رَجَعَ كامِل', 'Returned Complete', 'مکمل واپس');
      case VoucherStatus.returnedWithMissing:
        return _t('رَجَعَ مَع نَقص', 'Returned w/ Missing', 'کمی کے ساتھ واپس');
      case VoucherStatus.delivered:
        return _t('مُسَلَّم', 'Delivered', 'حوالہ شدہ');
    }
  }

  // ─── حالات الطَلَب ─────────────────────────────────────────
  String requestStatus(LaundryRequestStatus st) {
    switch (st) {
      case LaundryRequestStatus.pendingConfirmation:
        return _t('بانتِظار التَأكيد', 'Pending Confirmation', 'تصدیق کے انتظار میں');
      case LaundryRequestStatus.confirmedWithChanges:
        return _t('مُؤَكَّد مَع تَعديل', 'Confirmed w/ Changes', 'تبدیلی کے ساتھ تصدیق');
      case LaundryRequestStatus.confirmed:
        return _t('مُؤَكَّد', 'Confirmed', 'تصدیق شدہ');
      case LaundryRequestStatus.cancelled:
        return _t('مُلغى', 'Cancelled', 'منسوخ');
      case LaundryRequestStatus.expired:
        return _t('مُنتَهية', 'Expired', 'ختم شدہ');
    }
  }

  // ─── شاشة المَفقودات ──────────────────────────────────────
  String get all => _t('الكُلّ', 'All', 'سب');
  String get open => _t('مَفتوح', 'Open', 'کھلا');
  String get underReview => _t('قَيد المُراجَعة', 'Under Review', 'زیر جائزہ');
  String get compensated => _t('تَعويض', 'Compensated', 'معاوضہ');
  String get found => _t('وُجِدَ', 'Found', 'مل گیا');
  String get closed => _t('مُغلَق', 'Closed', 'بند');
  String get missingPieces => _t('قِطعة مَفقودة', 'piece(s) missing', 'گمشدہ');
  String get reviewDetails => _t('راجِع التَفاصيل', 'review details', 'تفصیلات دیکھیں');

  // ─── العَامّ ─────────────────────────────────────────────
  String get save => _t('حِفظ', 'Save', 'محفوظ کریں');
  String get cancel => _t('إلغاء', 'Cancel', 'منسوخ');
  String get confirm => _t('تَأكيد', 'Confirm', 'تصدیق');
  String get back => _t('رُجوع', 'Back', 'واپس');
  String get refresh => _t('تَحديث', 'Refresh', 'تازہ کریں');
  String get details => _t('تَفاصيل', 'Details', 'تفصیلات');
  String get edit => _t('تَعديل', 'Edit', 'ترمیم');
  String get delete => _t('حَذف', 'Delete', 'حذف');
  String get pieces => _t('قِطعة', 'piece(s)', 'پیس');
  String get items => _t('قِطَع', 'items', 'آئٹمز');
  String get sent => _t('المُسَلَّم', 'Sent', 'بھیجا');
  String get received => _t('المُرجَع', 'Received', 'وصول');
  String get missing => _t('مَفقود', 'Missing', 'گمشدہ');
  String get employee => _t('المُوَظَّف', 'Employee', 'ملازم');
  String get code => _t('الكود', 'Code', 'کوڈ');
  String get date => _t('التاريخ', 'Date', 'تاریخ');
  String get note => _t('مُلاحَظة', 'Note', 'نوٹ');
  String get printPdf => _t('طِباعة / حِفظ PDF', 'Print / Save PDF', 'پرنٹ / PDF محفوظ کریں');
  String get noActiveVouchers =>
      _t('لا تُوجَد سَنَدات نَشطة', 'No active vouchers', 'کوئی فعال ووچر نہیں');
  String get noReadyVouchers =>
      _t('لا تُوجَد سَنَدات جاهِزة لِلتَسليم',
          'No vouchers ready for delivery',
          'حوالہ کیلئے کوئی ووچر تیار نہیں');
  String get countryRequired =>
      _t('اختَر دَولة لِلمُتابَعة', 'Select a country', 'جاری رکھنے کیلئے ملک منتخب کریں');
  String get countryRequiredSub =>
      _t('نِظام "أَمانة" يَعمَل عَلى مُستَوى البَلَد. اختَر الدَولة لِإدارة المَغسلة.',
          '"Amana" works at country level. Select a country to manage the laundry.',
          'امانہ ملک کی سطح پر کام کرتا ہے۔ لانڈری چلانے کیلئے ملک منتخب کریں۔');
  String get openCountrySelector =>
      _t('فَتح شاشة اختِيار الدَولة', 'Open Country Selector',
          'ملک منتخب کرنے کا اسکرین کھولیں');

  // ─── التَسليم النِهائيّ ──────────────────────────────────
  String get handoverToEmployee =>
      _t('تَسليم لِلمُوَظَّف', 'Hand over to Employee', 'ملازم کو حوالہ کریں');
  String get confirmHandover =>
      _t('تَأكيد التَسليم لِلمُوَظَّف', 'Confirm Handover to Employee',
          'ملازم کو حوالہ کی تصدیق');
  String get employeeSignatureOptional =>
      _t('تَوقيع المُوَظَّف عَلى الاستِلام (اختِياريّ)',
          'Employee receipt signature (optional)',
          'ملازم کا دستخط (اختیاری)');

  // ─── السَلام ─────────────────────────────────────
  String get welcome => _t('مَرحَباً', 'Welcome', 'خوش آمدید');
}
