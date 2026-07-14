import 'package:flutter/material.dart';

import 'ar_to_ur_dictionary.dart';

/// نظام i18n مبسط داخلي - يدعم العربية والإنجليزية والأردو
/// يستخدم بدون الحاجة لـ flutter_gen أو ملفات .arb
///
/// الاستخدام: `AppStrings.of(context).appName`
/// لِإضافة تَرجَمة أردو لِسَطر مُحَدَّد: `_t(ar, en, ur)`
/// (لَو لَم تُمَرَّر `ur`، يَفترِض العَرَبيّ كَلُغة احتِياط لِلأردو)

class AppStrings {
  final Locale locale;
  AppStrings(this.locale);

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings) ??
        AppStrings(const Locale('ar'));
  }

  /// اللُغات المَدعومة (الأَردو RTL مِثل العَرَبيّ)
  static const supportedLocales = [
    Locale('ar'),
    Locale('en'),
    Locale('ur'),
  ];

  /// لُغات مَع أَسمائِها بِلُغَتها الأَصليّة
  static const languageNames = {
    'ar': 'العَرَبيّة',
    'en': 'English',
    'ur': 'اُردو',
  };

  /// أَيقونات الـflag (emoji)
  static const languageFlags = {
    'ar': '🇸🇦',
    'en': '🇬🇧',
    'ur': '🇵🇰',
  };

  /// `isArExact` يَتَحَقَّق بِالضَبط مِن العَرَبيّة. نادراً ما يَلزَم.
  bool get isArExact => locale.languageCode == 'ar';

  /// ⚠️ `isAr` يَعود `true` أيضاً لِلأردو لِكَي تَحصُل الـwidgets الكَثيرة
  /// التي تَستَخدِم نَمَط `isAr ? 'عربي' : 'English'` عَلَى نَص بِأَبجَديّة
  /// عَرَبيّة (مَفهومة جُزئيّاً لِلأردو) بَدَلاً مِن إنجليزيّة.
  /// يُكمَّل النَمَط بِـ `M7Text` التي تُتَرجِم النُصوص العَرَبيّة لِأردو تِلقائيّاً
  /// عَبر `kArToUrDictionary` لَو وُجِدَت في القاموس.
  bool get isAr => locale.languageCode == 'ar' || locale.languageCode == 'ur';
  bool get isEn => locale.languageCode == 'en';
  bool get isUr => locale.languageCode == 'ur';
  bool get isRtl => isArExact || isUr;

  /// تَرجَمة سَطر. الـur اختِياريّ — إن لَم يُمَرَّر، يَتِمّ
  /// مُحاوَلة الترجمة التِلقائيّة عَبر القاموس لِلأَردو، وَإلّا يُعاد العَرَبيّ.
  String _t(String ar, String en, [String? ur]) {
    if (isEn) return en;
    if (isUr) return ur ?? translateArToUr(ar);
    return ar;
  }

  /// 🔓 نُسخة عَلَنيّة مِن `_t` — لِلاسْتِخدام مِن الـwidgets مُباشَرَةً
  /// بَدَلاً مِن نَمَط `isAr ? 'ar' : 'en'` الذي يَفشَل لِلأَردو.
  /// مِثال: `AppStrings.of(context).t('عربي', 'English', 'اردو')`
  String t(String ar, String en, [String? ur]) => _t(ar, en, ur);

  /// 🔄 تَرجَمة نَص عَرَبيّ إلى أَردو تِلقائيّاً عَبر القاموس.
  /// تُستَخدَم بَعد نَمَط `isAr ? 'عربي' : 'English'` لِتَحويل النَص
  /// العَرَبيّ إلى أَردو لِمُستَخدِمي الأردو.
  /// مِثال: `Text(s.tr(isAr ? 'صباح الخير' : 'Good morning'))`
  String tr(String text) => isUr ? translateArToUr(text) : text;

  // ========== App-wide ==========
  String get appName => _t('M7 W Management', 'M7 W Management', 'M7 W Management');
  String get appTagline => _t(
      'منظومة الإدارة المتكاملة',
      'Integrated Management System',
      'مربوط انتظامیہ نظام');

  // ========== Common (مَع تَرجَمة أردو) ==========
  String get save => _t('حفظ', 'Save', 'محفوظ کریں');
  String get cancel => _t('إلغاء', 'Cancel', 'منسوخ');
  String get delete => _t('حذف', 'Delete', 'حذف کریں');
  String get edit => _t('تعديل', 'Edit', 'ترمیم');
  String get add => _t('إضافة', 'Add', 'شامل کریں');
  String get search => _t('بحث', 'Search', 'تلاش');
  String get filter => _t('فلترة', 'Filter', 'فلٹر');
  String get all => _t('الكل', 'All', 'تمام');
  String get yes => _t('نعم', 'Yes', 'ہاں');
  String get no => _t('لا', 'No', 'نہیں');
  String get confirm => _t('تأكيد', 'Confirm', 'تصدیق');
  String get back => _t('رجوع', 'Back', 'واپس');
  String get next => _t('التالي', 'Next', 'اگلا');
  String get done => _t('تم', 'Done', 'مکمل');
  String get refresh => _t('تحديث', 'Refresh', 'تازہ');
  String get loading => _t('جاري التحميل...', 'Loading...', 'لوڈ ہو رہا ہے...');
  String get noData =>
      _t('لا توجد بيانات', 'No data available', 'کوئی ڈیٹا دستیاب نہیں');
  String get error => _t('خطأ', 'Error', 'خرابی');
  String get success => _t('تم بنجاح', 'Success', 'کامیاب');
  String get notes => _t('ملاحظات', 'Notes', 'نوٹس');
  String get name => _t('الاسم', 'Name', 'نام');
  String get phone => _t('الهاتف', 'Phone', 'فون');
  String get email => _t('البريد', 'Email', 'ای میل');
  String get date => _t('التاريخ', 'Date', 'تاریخ');
  String get time => _t('الوقت', 'Time', 'وقت');
  String get from => _t('من', 'From', 'سے');
  String get to => _t('إلى', 'To', 'تک');
  String get total => _t('الإجمالي', 'Total', 'کل');
  String get status => _t('الحالة', 'Status', 'حیثیت');
  String get details => _t('التفاصيل', 'Details', 'تفصیلات');
  String get reports => _t('التقارير', 'Reports', 'رپورٹس');
  String get policies => _t('السياسات', 'Policies', 'پالیسیاں');
  String get policiesHint => _t('ابحث في السياسات أو اختر تصنيفاً',
      'Search policies or pick a category',
      'پالیسیاں تلاش کریں یا زمرہ منتخب کریں');
  String get lastUpdated => _t('آخر تحديث', 'Last updated', 'آخری اپڈیٹ');
  String get logout => _t('تسجيل الخروج', 'Logout', 'لاگ آؤٹ');
  String get profile => _t('الملف الشخصي', 'Profile', 'پروفائل');
  String get notifications => _t('الإشعارات', 'Notifications', 'اطلاعات');
  String get language => _t('اللغة', 'Language', 'زبان');
  String get theme => _t('الثيم', 'Theme', 'تھیم');
  String get darkMode => _t('الوضع الليلي', 'Dark Mode', 'ڈارک موڈ');
  String get lightMode => _t('الوضع النهاري', 'Light Mode', 'لائٹ موڈ');
  String get settings => _t('الإعدادات', 'Settings', 'ترتیبات');
  String get reason => _t('السبب', 'Reason', 'وجہ');
  String get approve => _t('موافقة', 'Approve', 'منظور');
  String get reject => _t('رفض', 'Reject', 'مسترد');
  String get submit => _t('إرسال', 'Submit', 'جمع کریں');
  String get draft => _t('مسودة', 'Draft', 'مسودہ');
  String get active => _t('نشط', 'Active', 'فعال');
  String get inactive => _t('غير نشط', 'Inactive', 'غیر فعال');
  String get capacity => _t('السعة', 'Capacity', 'گنجائش');
  String get available => _t('متاح', 'Available', 'دستیاب');
  String get used => _t('مستخدم', 'Used', 'استعمال شدہ');
  String get assign => _t('تعيين', 'Assign', 'تفویض');
  String get unassign => _t('إلغاء التعيين', 'Unassign', 'تفویض ختم');
  String get rate => _t('تقييم', 'Rate', 'درجہ بندی');
  String get rating => _t('التقييم', 'Rating', 'درجہ بندی');

  // ========== Roles ==========
  String get manager => _t('المدير', 'Manager', 'منیجر');
  String get operation => _t('العمليات', 'Operation', 'آپریشن');
  String get supervisor => _t('المشرف', 'Supervisor', 'سپروائزر');
  String get campBoss => _t('مسؤول الكامب', 'Camp Boss', 'کیمپ باس');
  String get driver => _t('سائق الباص', 'Bus Driver', 'بس ڈرائیور');
  String get employee => _t('الموظف', 'Employee', 'ملازم');

  // ========== Login & App Selection ==========
  String get selectApp => _t('اختر التطبيق', 'Select Application', 'ایپلیکیشن منتخب کریں');
  String get selectAppHint => _t(
      'اختر دورك للمتابعة', 'Choose your role to continue', 'اپنا کردار منتخب کریں');
  String get login => _t('تسجيل الدخول', 'Login', 'لاگ ان');
  String get username => _t('اسم المستخدم', 'Username', 'صارف نام');
  String get password => _t('كلمة المرور', 'Password', 'پاس ورڈ');
  String get invalidCredentials => _t(
      'اسم المستخدم أو كلمة المرور غير صحيحة',
      'Invalid credentials',
      'غلط معلومات');
  // 🔒 SECURITY: أُزيلت بيانات الدخول التجريبية (كانت تعلن الباب الخلفي).
  String get demoCredentials => _t('', '', '');

  // ========== Manager / Dashboard ==========
  String get dashboard => _t('لوحة التحكم', 'Dashboard', 'ڈیش بورڈ');
  String get totalEmployees =>
      _t('إجمالي الموظفين', 'Total Employees', 'کل ملازمین');
  String get activeEmployees =>
      _t('الموظفون النشطون', 'Active Employees', 'فعال ملازمین');
  String get inactiveEmployees => _t(
      'الموظفون غير النشطين', 'Inactive Employees', 'غیر فعال ملازمین');
  String get totalSites => _t('إجمالي المواقع', 'Total Sites', 'کل مقامات');
  String get activeSites => _t('المواقع النشطة', 'Active Sites', 'فعال مقامات');
  String get totalBuses => _t('إجمالي الباصات', 'Total Buses', 'کل بسیں');
  String get activeBuses => _t('الباصات النشطة', 'Active Buses', 'فعال بسیں');
  String get workingToday => _t('العاملون اليوم', 'Working Today', 'آج کام پر');
  String get offToday => _t('الإجازات اليوم', 'Off Today', 'آج چھٹی');
  String get todayTrips => _t('رحلات اليوم', 'Today Trips', 'آج کے سفر');
  String get pendingRosters =>
      _t('الورديات المعلقة', 'Pending Rosters', 'زیر التواء روسٹر');
  String get approvedRosters => _t(
      'الورديات الموافق عليها', 'Approved Rosters', 'منظور شدہ روسٹر');
  String get rejectedRosters =>
      _t('الورديات المرفوضة', 'Rejected Rosters', 'مسترد روسٹر');
  String get mostWorking => _t('الأكثر عملاً', 'Most Working', 'سب سے زیادہ کام');

  // ========== Sites ==========
  String get sites => _t('المواقع', 'Sites', 'مقامات');
  String get site => _t('الموقع', 'Site', 'مقام');
  String get siteName => _t('اسم الموقع', 'Site Name', 'مقام کا نام');
  String get companyName => _t('اسم الشركة', 'Company Name', 'کمپنی کا نام');
  String get businessType => _t('نوع النشاط', 'Business Type', 'کاروبار کی قسم');
  String get shortName => _t('الاسم المختصر', 'Short Name', 'مختصر نام');
  String get accountingName =>
      _t('الاسم المحاسبي', 'Accounting Name', 'اکاؤنٹنگ نام');
  String get location => _t('الموقع الجغرافي', 'Location', 'مقام');
  String get country => _t('الدولة', 'Country', 'ملک');
  String get state => _t('المنطقة', 'State / Province', 'صوبہ');
  String get city => _t('المدينة', 'City', 'شہر');
  String get fullAddress => _t('العنوان الكامل', 'Full Address', 'مکمل پتہ');
  String get taxId => _t('الرقم الضريبي', 'Tax ID', 'ٹیکس آئی ڈی');
  String get latitude => _t('خط العرض', 'Latitude', 'عرض البلد');
  String get longitude => _t('خط الطول', 'Longitude', 'طول البلد');

  // ========== Employees ==========
  String get employees => _t('الموظفون', 'Employees', 'ملازمین');
  String get employeeCode => _t('رمز الموظف', 'Employee Code', 'ملازم کوڈ');
  String get fullName => _t('الاسم الكامل', 'Full Name', 'پورا نام');
  String get jobTitle => _t('المسمى الوظيفي', 'Job Title', 'عہدہ');
  String get department => _t('القسم', 'Department', 'شعبہ');
  String get maritalStatus =>
      _t('الحالة الاجتماعية', 'Marital Status', 'ازدواجی حالت');
  String get birthDate => _t('تاريخ الميلاد', 'Birth Date', 'تاریخ پیدائش');
  String get nationality => _t('الجنسية', 'Nationality', 'قومیت');
  String get joiningDate =>
      _t('تاريخ الالتحاق', 'Joining Date', 'شمولیت کی تاریخ');
  String get passportNumber =>
      _t('رقم الجواز', 'Passport Number', 'پاسپورٹ نمبر');
  String get passportExpiry => _t(
      'تاريخ انتهاء الجواز', 'Passport Expiry', 'پاسپورٹ ختم ہونے کی تاریخ');
  String get idNumber => _t('رقم الهوية', 'ID Number', 'شناختی نمبر');
  String get visaType => _t('نوع التأشيرة', 'Visa Type', 'ویزا کی قسم');
  String get licenseNumber =>
      _t('رقم الرخصة', 'License Number', 'لائسنس نمبر');
  String get licenseIssue =>
      _t('تاريخ إصدار الرخصة', 'License Issue Date', 'لائسنس جاری تاریخ');
  String get licenseExpiry => _t(
      'تاريخ انتهاء الرخصة', 'License Expiry Date', 'لائسنس ختم تاریخ');
  String get basicSalary =>
      _t('الراتب الأساسي', 'Basic Salary', 'بنیادی تنخواہ');
  String get overtime => _t('الإضافي', 'Overtime', 'اضافی وقت');
  String get overtimeHourlyRate => _t(
      'سعر ساعة الأوفرتايم', 'Overtime Hourly Rate', 'اوور ٹائم گھنٹہ ریٹ');
  String get housingAllowance =>
      _t('بدل سكن', 'Housing Allowance', 'رہائش الاؤنس');
  String get transportAllowance =>
      _t('بدل مواصلات', 'Transport Allowance', 'ٹرانسپورٹ الاؤنس');
  String get totalSalary => _t('إجمالي الراتب', 'Total Salary', 'کل تنخواہ');
  String get iban => _t('IBAN', 'IBAN', 'IBAN');
  String get emergencyContact =>
      _t('جهة الاتصال للطوارئ', 'Emergency Contact', 'ہنگامی رابطہ');
  String get education => _t('التعليم', 'Education', 'تعلیم');

  // ========== Buses ==========
  String get buses => _t('الباصات', 'Buses', 'بسیں');
  String get busName => _t('اسم الباص', 'Bus Name', 'بس کا نام');
  String get plateNumber => _t('رقم اللوحة', 'Plate Number', 'پلیٹ نمبر');
  String get model => _t('الموديل', 'Model', 'ماڈل');
  String get year => _t('السنة', 'Year', 'سال');
  String get color => _t('اللون', 'Color', 'رنگ');
  String get insuranceExpiry =>
      _t('انتهاء التأمين', 'Insurance Expiry', 'بیمہ کی میعاد');
  String get maintenance => _t('في الصيانة', 'Maintenance', 'مرمت');
  String get liveTracking => _t('التتبع المباشر', 'Live Tracking', 'لائیو ٹریکنگ');
  String get lastUpdate => _t('آخر تحديث', 'Last Update', 'آخری اپڈیٹ');
  String get speed => _t('السرعة', 'Speed', 'رفتار');

  // ========== Roster ==========
  String get roster => _t('الروستر', 'Roster', 'روسٹر');
  String get rosters => _t('الورديات', 'Rosters', 'روسٹرز');
  String get weeklyRoster =>
      _t('الروستر الأسبوعي', 'Weekly Roster', 'ہفتہ وار روسٹر');
  String get rosterCreator =>
      _t('منشئ الروستر', 'Roster Creator', 'روسٹر بنانے والا');
  String get startTime => _t('وقت البدء', 'Start Time', 'شروع وقت');
  String get endTime => _t('وقت الانتهاء', 'End Time', 'اختتام وقت');
  String get shiftType => _t('نوع الوردية', 'Shift Type', 'شفٹ کی قسم');
  String get morning => _t('صباحية', 'Morning', 'صبح');
  String get evening => _t('مسائية', 'Evening', 'شام');
  String get night => _t('ليلية', 'Night', 'رات');
  String get off => _t('إجازة', 'Off', 'چھٹی');
  String get custom => _t('مخصصة', 'Custom', 'حسب ضرورت');
  String get duplicateDay => _t('تكرار اليوم', 'Duplicate Day', 'دن کاپی کریں');
  String get copyWeek => _t('نسخ الأسبوع', 'Copy Week', 'ہفتہ کاپی کریں');
  String get saveDraft => _t('حفظ كمسودة', 'Save as Draft', 'مسودہ محفوظ کریں');
  String get submitToOperation => _t(
      'إرسال إلى العمليات',
      'Submit to Operation',
      'آپریشن کو بھیجیں');
  String get submitted => _t('مُرسلة', 'Submitted', 'بھیج دیا');
  String get underReview => _t('قيد المراجعة', 'Under Review', 'زیر جائزہ');
  String get approved => _t('موافق عليها', 'Approved', 'منظور شدہ');
  String get rejected => _t('مرفوضة', 'Rejected', 'مسترد');
  String get rejectionReason =>
      _t('سبب الرفض', 'Rejection Reason', 'ردّ کی وجہ');
  String get totalHours => _t('إجمالي الساعات', 'Total Hours', 'کل گھنٹے');
  String get assignSupervisor =>
      _t('تعيين مشرف', 'Assign Supervisor', 'سپروائزر تفویض');
  String get reviewRoster =>
      _t('مراجعة الروستر', 'Review Roster', 'روسٹر کا جائزہ');
  String get actualRoster =>
      _t('الروستر الفعلي', 'Actual Roster', 'اصل روسٹر');

  // ========== Camp ==========
  String get camp => _t('الكامب', 'Camp', 'کیمپ');
  String get rooms => _t('الغرف', 'Rooms', 'کمرے');
  String get room => _t('الغرفة', 'Room', 'کمرہ');
  String get roomName => _t('اسم الغرفة', 'Room Name', 'کمرے کا نام');
  String get floor => _t('الطابق', 'Floor', 'منزل');
  String get beds => _t('الأسرّة', 'Beds', 'بستر');
  String get availableBeds =>
      _t('الأسرّة المتاحة', 'Available Beds', 'دستیاب بستر');
  String get usedBeds => _t('الأسرّة المستخدمة', 'Used Beds', 'استعمال شدہ بستر');
  String get assignToRoom =>
      _t('تعيين للغرفة', 'Assign to Room', 'کمرہ تفویض');

  // ========== Uniform ==========
  String get uniform => _t('الزي', 'Uniform', 'یونیفارم');
  String get uniformCatalog =>
      _t('كتالوج الزي', 'Uniform Catalog', 'یونیفارم کیٹلاگ');
  String get itemName => _t('اسم الصنف', 'Item Name', 'آئٹم کا نام');
  String get size => _t('المقاس', 'Size', 'سائز');
  String get quantity => _t('الكمية', 'Quantity', 'مقدار');
  String get price => _t('السعر', 'Price', 'قیمت');
  String get issueUniform => _t('صرف زي', 'Issue Uniform', 'یونیفارم جاری');
  String get returnUniform =>
      _t('استرجاع زي', 'Return Uniform', 'یونیفارم واپس');
  String get uniformHistory =>
      _t('سجل الزي', 'Uniform History', 'یونیفارم تاریخ');

  // ========== Laundry ==========
  String get laundry => _t('المغسلة', 'Laundry', 'لانڈری');
  String get laundryTicket =>
      _t('تذكرة مغسلة', 'Laundry Ticket', 'لانڈری ٹکٹ');
  String get ticketNumber => _t('رقم التذكرة', 'Ticket Number', 'ٹکٹ نمبر');
  String get receivedFromEmployee => _t(
      'استلام من الموظف',
      'Received from Employee',
      'ملازم سے وصول');
  String get sentToLaundry =>
      _t('إرسال للمغسلة', 'Sent to Laundry', 'لانڈری بھیجا');
  String get receivedFromLaundry => _t(
      'استلام من المغسلة',
      'Received from Laundry',
      'لانڈری سے وصول');
  String get deliveredToEmployee => _t(
      'تسليم للموظف', 'Delivered to Employee', 'ملازم کو ڈلیور');
  String get missingItems =>
      _t('أصناف ناقصة', 'Missing Items', 'غائب آئٹمز');

  // ========== Bus Plan ==========
  String get busPlan => _t('خطة الباصات', 'Bus Plan', 'بس پلان');
  String get busPlanning =>
      _t('تخطيط الباصات', 'Bus Planning', 'بس منصوبہ بندی');
  String get assignBus => _t('تعيين باص', 'Assign Bus', 'بس تفویض');
  String get capacityExceeded =>
      _t('السعة متجاوزة', 'Capacity exceeded', 'گنجائش سے زیادہ');
  String get noBus => _t('بدون باص', 'No bus', 'بس کے بغیر');

  // ========== Driver ==========
  String get todayTripsTitle =>
      _t('رحلات اليوم', "Today's Trips", 'آج کے سفر');
  String get weeklyTrips =>
      _t('الرحلات الأسبوعية', 'Weekly Trips', 'ہفتہ وار سفر');
  String get attendance => _t('الحضور', 'Attendance', 'حاضری');
  String get markPresent => _t('حاضر', 'Present', 'موجود');
  String get markMissing => _t('غائب', 'Missing', 'غیر حاضر');
  String get markChanged => _t('متغير', 'Changed', 'تبدیل');
  String get sendLocation =>
      _t('إرسال الموقع', 'Send Location', 'مقام بھیجیں');

  // ========== Deductions ==========
  String get deductions => _t('الخصومات', 'Deductions', 'کٹوتیاں');
  String get amount => _t('المبلغ', 'Amount', 'رقم');
  String get addedBy => _t('أُضيف بواسطة', 'Added by', 'شامل کردہ');

  // ========== Evaluation ==========
  String get evaluation => _t('التقييم', 'Evaluation', 'تشخیص');
  String get employeeEvaluation =>
      _t('تقييم الموظف', 'Employee Evaluation', 'ملازم کی تشخیص');
  String get driverEvaluation =>
      _t('تقييم السائق', 'Driver Evaluation', 'ڈرائیور کی تشخیص');

  // ========== Lookups & Settings ==========
  String get countries => _t('الدول', 'Countries', 'ممالک');
  String get country2 => _t('الدولة', 'Country', 'ملک');
  String get statesProvinces =>
      _t('المناطق/المحافظات', 'States / Provinces', 'صوبے');
  String get stateProvince =>
      _t('منطقة/محافظة', 'State / Province', 'صوبہ');
  String get cities => _t('المدن', 'Cities', 'شہر');
  String get city2 => _t('المدينة', 'City', 'شہر');
  String get areasList =>
      _t('الأحياء/المناطق الفرعية', 'Areas', 'علاقے');
  String get area => _t('الحي', 'Area', 'علاقہ');
  String get businessTypes =>
      _t('أنواع الأنشطة', 'Business Types', 'کاروبار کی اقسام');
  String get businessType2 =>
      _t('نوع النشاط', 'Business Type', 'کاروبار کی قسم');
  String get nameArabic =>
      _t('الاسم بالعربية', 'Name (Arabic)', 'نام (عربی)');
  String get nameEnglish =>
      _t('الاسم بالإنجليزية', 'Name (English)', 'نام (انگریزی)');
  String get countryCode => _t('رمز الدولة', 'Country Code', 'ملک کا کوڈ');
  String get selectCountryFirst => _t(
      'اختر الدولة أولاً', 'Select country first', 'پہلے ملک منتخب کریں');
  String get selectStateFirst => _t(
      'اختر المنطقة أولاً', 'Select state first', 'پہلے صوبہ منتخب کریں');
  String get selectCityFirst => _t(
      'اختر المدينة أولاً', 'Select city first', 'پہلے شہر منتخب کریں');
  String get cascadeWarning => _t(
      'سيتم حذف العناصر التابعة لهذا العنصر',
      'Linked sub-items will be deleted',
      'منسلک عناصر حذف ہو جائیں گے');
  String get customerInfo =>
      _t('بيانات العميل', 'Customer Information', 'گاہک کی معلومات');
  String get basicInfo =>
      _t('البيانات الأساسية', 'Basic Information', 'بنیادی معلومات');
  String get contactInfo =>
      _t('بيانات التواصل', 'Contact Information', 'رابطہ معلومات');
  String get locationInfo => _t('الموقع', 'Location', 'مقام');
  String get additionalInfo => _t(
      'بيانات إضافية', 'Additional Information', 'اضافی معلومات');
  String get filesAndDocs =>
      _t('الملفات والمستندات', 'Files & Documents', 'فائلیں اور دستاویزات');
  String get customerStatus =>
      _t('حالة العميل', 'Customer Status', 'گاہک کی حیثیت');
  String get manageLookups =>
      _t('إدارة القوائم', 'Manage Lookups', 'فہرستیں منظم کریں');
  // ===== Numbering System =====
  String get numberingSystem =>
      _t('نظام الترقيم', 'Numbering System', 'نمبرنگ سسٹم');
  String get numberingSettings =>
      _t('إعدادات الترقيم', 'Numbering Settings', 'نمبرنگ ترتیبات');
  String get unifiedView => _t('العرض الموحد', 'Unified View', 'متحدہ منظر');
  String get generateCode =>
      _t('توليد كود', 'Generate Code', 'کوڈ بنائیں');
  String get countriesManagement =>
      _t('إدارة الدول', 'Countries Management', 'ممالک کا انتظام');
  String get phoneCode => _t('مفتاح الهاتف', 'Phone Code', 'فون کوڈ');
  String get currency => _t('العملة', 'Currency', 'کرنسی');
  String get flagEmoji => _t('العلم (Emoji)', 'Flag (Emoji)', 'پرچم (Emoji)');
  String get isoCodeShort =>
      _t('الاختصار (ISO) (حرفان)', 'ISO Code (2 letters)', 'ISO کوڈ (2 حروف)');
  String get entityName => _t('اسم الكيان', 'Entity Name', 'ادارہ کا نام');
  String get technicalId =>
      _t('المعرّف الفني', 'Technical ID', 'تکنیکی شناخت');
  String get prefix => _t('البادئة', 'Prefix', 'سابقہ');
  String get separator => _t('الفاصل', 'Separator', 'جدا کنندہ');
  String get startNumber => _t('الرقم البدائي', 'Start Number', 'شروع نمبر');
  String get digitsCount => _t('عدد الخانات', 'Digits Count', 'ہندسوں کی تعداد');
  String get includeCountry => _t('تضمين كود الدولة في الكود',
      'Include country code', 'ملک کا کوڈ شامل کریں');
  String get nextCode => _t('التالي', 'Next', 'اگلا');
  String get currentValue => _t('الحالي', 'Current', 'موجودہ');
  String get last => _t('آخر', 'Last', 'آخری');
  String get notGenerated => _t('لم يُولّد', 'Not generated', 'نہیں بنایا');
  String get noPadding => _t('بدون', 'None', 'کوئی نہیں');
  String get previewGenerated => _t(
      'معاينة الأكواد المولّدة',
      'Generated codes preview',
      'تیار کردہ کوڈز کا پیش نظارہ');
  String get reset => _t('إعادة تعيين', 'Reset', 'ری سیٹ');
  String get saveSettings =>
      _t('حفظ الإعدادات', 'Save Settings', 'ترتیبات محفوظ کریں');
  String get codesGenerated =>
      _t('كود مولّد', 'codes generated', 'کوڈز بنائے گئے');
  String get currentCountry =>
      _t('الدولة الحالية', 'Current country', 'موجودہ ملک');
  String get definedNumberings => _t(
      'إعدادات الترقيم المعرّفة',
      'Defined numberings',
      'متعین نمبرنگز');
  String get allCountries => _t('جميع الدول', 'All countries', 'تمام ممالک');
  String get addNumbering =>
      _t('إضافة ترقيم', 'Add Numbering', 'نمبرنگ شامل کریں');
  String get addCountry => _t('إضافة دولة', 'Add Country', 'ملک شامل کریں');
  String get loginCountryHint =>
      _t('اختر الدولة', 'Select country', 'ملک منتخب کریں');
  // ===== Customer Wizard =====
  String get newCustomer =>
      _t('عميل جديد', 'New Customer', 'نیا گاہک');
  String get autoCodes => _t('أكواد تلقائية', 'AUTO CODES', 'خودکار کوڈز');
  String get auto => _t('تلقائي', 'AUTO', 'خودکار');
  String get masterStep => _t('Master', 'Master', 'Master');
  String get masterContract => _t('الاسم التجاري', 'Master', 'ٹریڈ نام');
  String get masterContractSub => _t('عقد', 'Contract', 'معاہدہ');
  String get clientStep => _t('Client', 'Client', 'Client');
  String get clientBranch => _t('الفرع', 'Client', 'برانچ');
  String get clientBranchSub => _t('فرع', 'Branch', 'شاخ');
  String get pointStep => _t('Point', 'Point', 'Point');
  String get pointLocation => _t('نقطة البيع', 'Point', 'سیلز پوائنٹ');
  String get pointLocationSub => _t('موقع', 'Location', 'مقام');
  String get step1Desc => _t(
      'إنشاء الاسم التجاري (Master)',
      'Create Master Customer',
      'ٹریڈ نام (Master) بنائیں');
  String get step2Desc => _t(
      'إنشاء فرع مرتبط بالاسم التجاري',
      'Create Client linked to Master',
      'Master سے منسلک Client بنائیں');
  String get step3Desc => _t(
      'إنشاء نقطة بيع مع الموقع',
      'Create Point with location',
      'مقام کے ساتھ Point بنائیں');
  String get masterCode =>
      _t('كود الاسم التجاري', 'Master Code', 'Master کوڈ');
  String get masterInformation => _t(
      'بيانات الاسم التجاري', 'Master Information', 'Master معلومات');
  String get masterName =>
      _t('اسم الاسم التجاري', 'Master Name', 'Master کا نام');
  String get masterNameHint => _t(
      'مثال: شركة الأمل التجارية',
      'e.g. Al Amal Trading Co.',
      'مثلاً: الامل ٹریڈنگ کمپنی');
  String get tradeLicense =>
      _t('السجل التجاري', 'Trade License', 'ٹریڈ لائسنس');
  String get taxVat => _t('الرقم الضريبي', 'Tax / VAT', 'ٹیکس / VAT');
  String get industry => _t('القطاع', 'Industry', 'صنعت');
  String get startDateLbl =>
      _t('تاريخ البدء', 'Start Date', 'شروع کی تاریخ');
  String get internalNotes =>
      _t('ملاحظات داخلية', 'Internal notes', 'اندرونی نوٹس');
  String get linkToMaster =>
      _t('الربط بالاسم التجاري', 'Link to Master', 'Master سے منسلک');
  String get linkToMasterDesc => _t(
      'كل فرع يجب أن يرتبط باسم تجاري.',
      'Each client must belong to a Master Customer.',
      'ہر کلائنٹ ایک Master سے منسلک ہونا چاہیے۔');
  String get selectMaster =>
      _t('— اختر اسم تجاري —', '— Select Master —', '— Master منتخب کریں —');
  String get singleBranchAuto => _t(
      'فرع وحيد - إنشاء Master تلقائياً',
      'Single branch — Auto-create Master',
      'واحد برانچ — خودکار Master');
  String get singleBranchAutoDesc => _t(
      'حدّد إن كان هذا فرع وحيد قائم بذاته. سيُنشئ النظام Master بنفس البيانات ويربطهما.',
      'Check if this is a standalone single branch. System will auto-create a Master with same data and link them.',
      'اگر یہ واحد برانچ ہے تو منتخب کریں۔ سسٹم Master خودکار بنائے گا۔');
  String get willCreate => _t('سيُنشأ', 'Will create', 'بنایا جائے گا');
  String get clientCode => _t('كود الفرع', 'Client Code', 'Client کوڈ');
  String get basicInformation =>
      _t('البيانات الأساسية', 'Basic Information', 'بنیادی معلومات');
  String get contact => _t('التواصل', 'Contact', 'رابطہ');
  String get additional => _t('إضافي', 'Additional', 'اضافی');
  String get pointCode =>
      _t('كود نقطة البيع', 'Point Code', 'Point کوڈ');
  String get pointInformation =>
      _t('بيانات نقطة البيع', 'Point Information', 'Point معلومات');
  String get pointName =>
      _t('اسم نقطة البيع', 'Point Name', 'Point کا نام');
  String get pointNameHint => _t(
      'مثال: مول العرب', 'e.g. Al Arab Mall', 'مثلاً: الاعرب مال');
  String get pointDescription =>
      _t('الوصف / ملاحظات', 'Description / Notes', 'تفصیل / نوٹس');
  String get pointDescriptionHint => _t(
      'وصف نقطة البيع: تفاصيل المبنى، معالم، تعليمات خاصة، إلخ.',
      'Describe this point: building details, landmarks, special instructions, etc.',
      'Point کی تفصیل: عمارت کی تفصیلات، نشانیاں، خصوصی ہدایات۔');
  String get pointInfoNote => _t(
      'نقطة البيع موقع جغرافي يحوي البيانات الجغرافية. يمكن لعدة فروع العمل فيها.',
      'A Point is a physical location holding all geographic data. One or more clients can operate at it.',
      'Point ایک جغرافیائی مقام ہے جس میں متعدد Clients کام کر سکتے ہیں۔');
  String get linkedClients =>
      _t('الفروع المرتبطة', 'Linked Clients', 'منسلک Clients');
  String get linkedClientsDesc => _t(
      'يمكن لعدة فروع العمل في نقطة البيع.',
      'Multiple clients can operate at this point.',
      'متعدد Clients اس Point پر کام کر سکتے ہیں۔');
  String get unitShop =>
      _t('الوحدة / المحل', 'Unit / Shop', 'یونٹ / شاپ');
  String get floorLbl => _t('الطابق', 'Floor', 'منزل');
  String get linkClient =>
      _t('ربط فرع', 'Link Client', 'Client منسلک');
  String get noClientsLinked => _t(
      'لا توجد فروع مرتبطة', 'No clients linked yet', 'کوئی Client منسلک نہیں');
  String get selectMasterFirst => _t(
      'اختر اسم تجاري أو فعّل إنشاء تلقائي',
      'Select or auto-create Master',
      'Master منتخب کریں یا خودکار بنائیں');
  String get saveCustomer =>
      _t('حفظ العميل', 'Save Customer', 'گاہک محفوظ کریں');
  String get savedSuccess =>
      _t('تم الحفظ بنجاح', 'Saved successfully', 'کامیابی سے محفوظ ہوا');
  String get masterRequired => _t(
      'اسم Master مطلوب', 'Master name required', 'Master کا نام درکار');
  String get companyNameRequired => _t(
      'اسم الشركة مطلوب',
      'Company name required',
      'کمپنی کا نام درکار');
  String get pointNameRequired => _t(
      'اسم نقطة البيع مطلوب',
      'Point name required',
      'Point کا نام درکار');
  String get tapToSelectFiles => _t(
      'انقر لاختيار ملفات', 'Tap to select files', 'فائلیں منتخب کرنے کے لیے ٹیپ کریں');
  String get filesAccepted => _t(
      'PDF، DOC، PNG، JPG (حتى 5 ميجا)',
      'PDF, DOC, PNG, JPG (max 5MB)',
      'PDF, DOC, PNG, JPG (زیادہ سے زیادہ 5MB)');
  String get chooseFile =>
      _t('+ اختر ملف', '+ Choose file', '+ فائل منتخب کریں');
  String get noFiles =>
      _t('لا توجد ملفات', 'No files', 'کوئی فائلیں نہیں');
  String get orDivider => _t('أو', 'OR', 'یا');
  String get createNewMaster => _t(
      'إنشاء اسم تجاري جديد', 'Create New Master', 'نیا Master بنائیں');
  String get countryRequired => _t(
      'الدولة غير محددة - سجّل دخولاً مع دولة',
      'Country not set — login with a country',
      'ملک متعین نہیں — ملک کے ساتھ لاگ ان کریں');
  // ===== Roster workflow =====
  String get draftRoster =>
      _t('روستر مسودة', 'Draft Roster', 'مسودہ روسٹر');
  String get approvedRosterTab =>
      _t('الروستر المعتمد', 'Approved Roster', 'منظور شدہ روسٹر');
  String get rosterStatus =>
      _t('حالة الروستر', 'Roster Status', 'روسٹر کی حیثیت');
  String get rejectedBanner =>
      _t('تم رفض هذا الروستر', 'This roster was rejected', 'یہ روسٹر مسترد ہوا');
  String get submittedBanner => _t(
      'تم إرسال الروستر — في انتظار الموافقة',
      'Roster submitted — awaiting approval',
      'روسٹر جمع کر دیا — منظوری کا انتظار');
  String get approvedBanner => _t(
      'تمت الموافقة على هذا الروستر',
      'This roster has been approved',
      'یہ روسٹر منظور ہو چکا ہے');
  String get draftBanner => _t(
      'مسودة — قابلة للتعديل والإرسال',
      'Draft — editable and submittable',
      'مسودہ — ترمیم اور جمع کے قابل');
  String get reEditAndResubmit => _t(
      'عدّل وأعد الإرسال', 'Edit & Resubmit', 'ترمیم اور دوبارہ جمع');
  String get effectiveFrom =>
      _t('سريان من', 'Effective From', 'سے نافذ');
  String get effectiveTo => _t('سريان إلى', 'Effective To', 'تک نافذ');
  String get noApprovedYet => _t('لا يوجد روستر معتمد بعد',
      'No approved roster yet', 'ابھی تک کوئی منظور شدہ روسٹر نہیں');
  String get approvedAt =>
      _t('تاريخ الاعتماد', 'Approved At', 'منظوری کی تاریخ');
  String get reviewedBy => _t('بواسطة', 'Reviewed By', 'کی طرف سے');
  String get pendingApproval => _t(
      'بانتظار موافقة Operation أو Manager',
      'Awaiting Operation/Manager approval',
      'Operation/Manager کی منظوری کا انتظار');
  String get viewDetails => _t('عرض التفاصيل', 'View Details', 'تفصیلات دیکھیں');
  // ===== Evaluation =====
  String get myRosters => _t('روستراتي', 'My Rosters', 'میرے روسٹرز');
  String get evaluationInstructions => _t(
      'تعليمات التقييم', 'Evaluation Instructions', 'تشخیص کی ہدایات');
  String get evaluationInstructionsBody => _t(
      'يرجى قراءة المعايير بعناية وتقييم الموظف بإنصاف. كل معيار من 1 (الأسوأ) إلى 5 (الأفضل). المعدل العام يُحسب تلقائياً من المعايير الـ 9.',
      'Please read each criterion carefully and rate fairly. Each is rated 1 (worst) to 5 (best). The overall rating is auto-calculated from the 9 criteria.',
      'براہ کرم معیارات احتیاط سے پڑھیں اور انصاف سے درجہ بندی کریں۔ ہر معیار 1 (بدترین) سے 5 (بہترین) تک ہے۔ مجموعی درجہ خودکار طور پر شمار ہوتا ہے۔');
  String get evalCategoryHygiene => _t(
      'النظافة الشخصية', 'Personal Hygiene', 'ذاتی صفائی');
  String get evalCategoryGrooming => _t(
      'المظهر والزي', 'Grooming & Uniform', 'ظاہری شکل اور یونیفارم');
  String get evalCategoryWorkArea => _t(
      'نظافة بيئة العمل', 'Work Area Hygiene', 'کام کی جگہ کی صفائی');
  // النظافة الشخصية
  String get evalHygieneSmell => _t('الرائحة', 'Smell', 'بدبو');
  String get evalHygieneSmellDesc => _t(
      'استخدام مزيل العرق بانتظام، وخلوه من روائح العرق أو الدخان المزعجة.',
      'Regular deodorant use, no offensive sweat or smoke odors.',
      'باقاعدہ ڈیوڈرینٹ، پسینے یا دھوئیں کی بدبو نہیں۔');
  String get evalHygieneOral =>
      _t('نظافة الفم', 'Oral Hygiene', 'منہ کی صفائی');
  String get evalHygieneOralDesc => _t(
      'خلو الفم من الروائح الكريهة أثناء التحدث مع العملاء.',
      'Fresh breath when speaking with customers.',
      'گاہکوں سے بات کرتے وقت تازہ سانس۔');
  String get evalHygieneHands =>
      _t('نظافة اليدين', 'Hand Cleanliness', 'ہاتھوں کی صفائی');
  String get evalHygieneHandsDesc => _t(
      'اليدان والأظافر نظيفة ومقلمة (مهم جداً عند استلام عجلة القيادة).',
      'Clean hands and trimmed nails (very important when handling steering wheels).',
      'صاف ہاتھ اور تراشے ہوئے ناخن۔');
  // المظهر والزي
  String get evalGroomingUniform => _t(
      'الزي الرسمي', 'Official Uniform', 'سرکاری یونیفارم');
  String get evalGroomingUniformDesc => _t(
      'ارتداء الزي المعتمد كاملاً، نظيفاً، ومكوياً، بما في ذلك البطاقة التعريفية.',
      'Full official uniform, clean, ironed, including Name Tag.',
      'مکمل سرکاری یونیفارم، صاف، استری شدہ، نام کے ٹیگ سمیت۔');
  String get evalGroomingHair =>
      _t('الشعر واللحية', 'Hair & Beard', 'بال اور داڑھی');
  String get evalGroomingHairDesc => _t(
      'الشعر مرتب ومصفف باحترافية، واللحية مهذبة أو محلوقة حسب سياسة العمل.',
      'Hair professionally styled; beard trimmed/shaved per work policy.',
      'بال پیشہ ورانہ انداز میں، داڑھی پالیسی کے مطابق۔');
  String get evalGroomingShoes => _t('الحذاء', 'Shoes', 'جوتے');
  String get evalGroomingShoesDesc => _t(
      'ارتداء الحذاء المخصص للعمل ويكون نظيفاً وملمعاً.',
      'Work-issued shoes, clean and polished.',
      'کام کے جوتے، صاف اور پالش شدہ۔');
  // بيئة العمل
  String get evalWorkPodium => _t(
      'نقطة الاستلام (Podium)', 'Podium Station', 'پوڈیم اسٹیشن');
  String get evalWorkPodiumDesc => _t(
      'الحفاظ على منصة الفاليه نظيفة، منظمة، وخالية من الأغراض الشخصية أو الأكواب الفارغة.',
      'Keep the valet podium clean, organized, free of personal items or empty cups.',
      'پوڈیم صاف، منظم، ذاتی اشیاء یا کپوں سے پاک۔');
  String get evalWorkTickets => _t(
      'نظام التذاكر والمفاتيح',
      'Tickets & Keys System',
      'ٹکٹ اور چابیاں');
  String get evalWorkTicketsDesc => _t(
      'التعامل مع التذاكر والمفاتيح بانتظام دون إحداث فوضى أو ضياع.',
      'Handle tickets and keys orderly without chaos or loss.',
      'ٹکٹ اور چابیوں کو منظم رکھیں، کوئی نقصان نہیں۔');
  String get evalWorkCar =>
      _t('سيارة العميل', 'Customer\'s Vehicle', 'گاہک کی گاڑی');
  String get evalWorkCarDesc => _t(
      'تسليم السيارة بنفس حالة استلامها (عدم ترك بصمات متسخة، عدم ترك أوراق داخل السيارة، وعدم العبث بالإعدادات).',
      'Return the vehicle in the same condition (no dirty fingerprints, no papers, no settings tampered).',
      'گاڑی اسی حالت میں واپس کریں (کوئی گندے انگوٹھے، کوئی کاغذات، کوئی چھیڑ چھاڑ نہیں)۔');
  // عام
  String get overallRating =>
      _t('المعدل العام', 'Overall Rating', 'مجموعی درجہ');
  String get readInstructionsFirst => _t(
      'اقرأ التعليمات قبل البدء',
      'Read instructions before starting',
      'شروع کرنے سے پہلے ہدایات پڑھیں');
  String get newEvaluation =>
      _t('تقييم جديد', 'New Evaluation', 'نئی تشخیص');
  String get selectEmployeeFirst => _t(
      'اختر الموظف أولاً', 'Select employee first', 'پہلے ملازم منتخب کریں');
  String get rateAllCriteria => _t(
      'قيّم جميع المعايير قبل الحفظ',
      'Rate all criteria before saving',
      'تمام معیارات کو محفوظ کرنے سے پہلے درجہ بندی کریں');
  String get scaleHint => _t(
      '1 = الأسوأ ، 5 = الأفضل', '1 = worst, 5 = best', '1 = بدترین، 5 = بہترین');
  String get pastEvaluations =>
      _t('التقييمات السابقة', 'Past Evaluations', 'پچھلی تشخیصات');
  // ===== Morning Checklist =====
  String get morningChecklist => _t(
      'الجرد الصباحي', 'Morning Checklist', 'صبح کی چیک لسٹ');
  String get checklistInstructions => _t(
      'تعليمات الجرد', 'Checklist Instructions', 'چیک لسٹ ہدایات');
  String get checklistInstructionsBody => _t(
      'يجب رفع 3 صور كل صباح قبل بدء استلام السيارات. كل صورة توثّق معياراً معيناً، ويُسجَّل وقت التقاط الصورة تلقائياً.',
      'Upload 3 photos every morning before starting vehicle reception. Each photo documents a specific criterion; capture time is recorded automatically.',
      'ہر صبح گاڑیوں کے استقبال سے پہلے 3 تصاویر اپ لوڈ کریں۔ ہر تصویر ایک مخصوص معیار کو دستاویز کرتی ہے۔');
  String get podiumPhoto =>
      _t('صورة البوديوم', 'The Podium', 'پوڈیم');
  String get podiumCriterion => _t(
      'معيار: نظافة بيئة العمل',
      'Covers: Work Area Hygiene',
      'معیار: کام کی جگہ کی صفائی');
  String get podiumDesc => _t(
      'نظافة المنصة، ترتيب لوحة المفاتيح، توفر التذاكر والأدوات، وعدم وجود أكواب قهوة، أو متعلقات شخصية، أو فوضى تشوه الواجهة التي يراها العميل.',
      'Clean podium, organized key board, tickets and tools available, no coffee cups, personal items, or clutter visible to customers.',
      'صاف پوڈیم، منظم چابی بورڈ، ٹکٹ اور اوزار دستیاب، کوئی کافی کپ، ذاتی اشیاء یا گندگی نہیں۔');
  String get employeesPhoto =>
      _t('صورة الموظفين', 'The Employees', 'ملازمین');
  String get employeesCriterion => _t(
      'معيار: المظهر والزي',
      'Covers: Grooming & Uniform',
      'معیار: ظاہری شکل اور یونیفارم');
  String get employeesDesc => _t(
      'توثيق اصطفاف فريق العمل بالزي الرسمي الكامل، والتأكد من التزامهم بمعايير الحلاقة، والترتيب العام للمظهر (الحذاء والبطاقة التعريفية) قبل استلام أي سيارة.',
      'Document the team lined up in full official uniform, confirming grooming standards (shoes, name tag) before receiving any vehicle.',
      'مکمل سرکاری یونیفارم میں ٹیم، گرومنگ کے معیارات (جوتے، نام ٹیگ) کی تصدیق۔');
  String get parkingPhoto =>
      _t('صورة البركنج', 'The Parking Lot', 'پارکنگ');
  String get parkingCriterion => _t(
      'معيار: الجاهزية والأمان التشغيلي',
      'Covers: Operational Readiness & Safety',
      'معیار: آپریشنل تیاری اور حفاظت');
  String get parkingDesc => _t(
      'خلو الممرات من العوائق، نظافة الأرضية، الإضاءة (إن لزم الأمر)، وجاهزية المواقف لاستيعاب سيارات العملاء بسلاسة وبدون مخاطر تؤدي لخدش السيارات.',
      'Aisles clear of obstacles, clean floor, adequate lighting, and parking ready to receive customer vehicles smoothly without scratch risks.',
      'راہداریاں رکاوٹوں سے پاک، صاف فرش، مناسب روشنی، پارکنگ تیار۔');
  String get capturedAt =>
      _t('وقت الالتقاط', 'Captured At', 'گرفت کا وقت');
  String get takePhoto =>
      _t('التقاط صورة', 'Take Photo', 'تصویر لیں');
  String get retakePhoto =>
      _t('إعادة التقاط', 'Retake', 'دوبارہ لیں');
  String get viewPhoto =>
      _t('عرض الصورة', 'View Photo', 'تصویر دیکھیں');
  String get photosUploaded =>
      _t('صور مرفوعة', 'photos uploaded', 'تصاویر اپ لوڈ ہوئیں');
  String get checklistComplete => _t(
      'اكتمل الجرد الصباحي ✓',
      'Morning checklist complete ✓',
      'صبح کی چیک لسٹ مکمل ✓');
  String get checklistPending => _t(
      'الجرد الصباحي غير مكتمل',
      'Morning checklist incomplete',
      'صبح کی چیک لسٹ نامکمل');
  String get pastChecklists =>
      _t('سجل الجرد', 'Checklist History', 'چیک لسٹ تاریخ');
  String get morningChecklistShort =>
      _t('الجرد', 'Checklist', 'چیک لسٹ');
  String get todayChecklist =>
      _t('جرد اليوم', "Today's Checklist", 'آج کی چیک لسٹ');
  String get jobTitles =>
      _t('المسميات الوظيفية', 'Job Titles', 'عہدے');
  String get jobTitle2 =>
      _t('المسمى الوظيفي', 'Job Title', 'عہدہ');
  String get departments => _t('الأقسام', 'Departments', 'شعبے');
  String get department2 => _t('القسم', 'Department', 'شعبہ');
  String get maritalStatuses => _t(
      'الحالات الاجتماعية', 'Marital Statuses', 'ازدواجی حالتیں');
  String get maritalStatus2 => _t(
      'الحالة الاجتماعية', 'Marital Status', 'ازدواجی حالت');
  String get nationalities =>
      _t('الجنسيات', 'Nationalities', 'قومیتیں');
  String get nationality2 => _t('الجنسية', 'Nationality', 'قومیت');
  String get visaTypes =>
      _t('أنواع التأشيرات', 'Visa Types', 'ویزا اقسام');
  String get visaType2 =>
      _t('نوع التأشيرة', 'Visa Type', 'ویزا کی قسم');
  // ===== Employee form sections =====
  String get personalInfo => _t(
      'البيانات الشخصية', 'Personal Information', 'ذاتی معلومات');
  String get passportIdInfo => _t(
      'بيانات الجواز والهوية',
      'Passport & ID Information',
      'پاسپورٹ اور شناختی معلومات');
  String get licenseInfo => _t(
      'بيانات الرخصة', 'License Information', 'لائسنس معلومات');
  String get financialInfo => _t(
      'البيانات المالية', 'Financial Information', 'مالی معلومات');
  String get emergencyAdditional => _t(
      'جهات الطوارئ ومعلومات إضافية',
      'Emergency Contact & Additional Information',
      'ہنگامی رابطہ اور اضافی معلومات');
  String get employeePhoto =>
      _t('صورة الموظف', 'Employee Photo', 'ملازم کی تصویر');
  String get uploadPhoto => _t(
      'ارفع صورة الموظف',
      'Upload employee profile photo',
      'ملازم کی پروفائل تصویر اپ لوڈ کریں');
  String get idCardDoc => _t(
      'بطاقة الهوية', 'ID / Nationality Card', 'شناختی کارڈ');
  String get uploadIdCard => _t(
      'ارفع بطاقة الهوية',
      'Upload ID or nationality card',
      'شناختی کارڈ اپ لوڈ کریں');
  String get licenseDoc => _t(
      'مستند الرخصة', 'License Document', 'لائسنس دستاویز');
  String get uploadLicense => _t(
      'ارفع مستند الرخصة',
      'Upload license document',
      'لائسنس دستاویز اپ لوڈ کریں');
  String get workLetter =>
      _t('خطاب العمل', 'Work Letter', 'کام کا خط');
  String get uploadWorkLetter => _t(
      'ارفع خطاب العمل',
      'Upload work letter document',
      'کام کا خط اپ لوڈ کریں');
  String get workLetterDate => _t(
      'تاريخ خطاب العمل', 'Work Letter Date', 'کام کے خط کی تاریخ');
  String get totalSalaryHint => _t(
      '(الأساسي + بدل سكن + بدل مواصلات + أخرى)',
      '(Basic + Housing + Transport + Other)',
      '(بنیادی + رہائش + ٹرانسپورٹ + دیگر)');
  String get emergencyContactName2 => _t(
      'اسم جهة الطوارئ',
      'Emergency Contact Name',
      'ہنگامی رابطہ نام');
  String get emergencyContactPhone2 => _t(
      'هاتف جهة الطوارئ',
      'Emergency Contact Phone',
      'ہنگامی رابطہ فون');
  String get fullAddress2 =>
      _t('العنوان الكامل', 'Address', 'پتہ');
  String get trainingFee =>
      _t('رسوم التدريب', 'Training Fee', 'تربیتی فیس');
  String get others => _t('أخرى', 'Others', 'دیگر');

  // ========== Employee Self ==========
  String get mySchedule => _t('جدولي', 'My Schedule', 'میرا شیڈول');
  String get myUniform => _t('زيي', 'My Uniform', 'میرا یونیفارم');
  String get myLaundry => _t('مغسلتي', 'My Laundry', 'میری لانڈری');
  String get myDeductions =>
      _t('خصوماتي', 'My Deductions', 'میری کٹوتیاں');
  String get myEvaluations =>
      _t('تقييماتي', 'My Evaluations', 'میری تشخیصات');
}

class AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const AppStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['ar', 'en', 'ur'].contains(locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) async => AppStrings(locale);

  @override
  bool shouldReload(AppStringsDelegate old) => false;
}
