/// 🔧 مكتبة قوالب سير الموافقات (Session 15)
///
/// قوالب جاهزة لخطوات الموافقة الشائعة، يستطيع المسؤول تطبيقها بنقرة واحدة
/// على أيّ FormTemplate بدلاً من بناء الخطوات يدوياً.
///
/// كلّ قالب هو `List<Map<String, dynamic>>` متوافق مع `FormTemplate.workflow`.
class WorkflowTemplates {
  WorkflowTemplates._();

  /// قائمة كلّ القوالب المتاحة
  static final List<WorkflowPreset> all = [
    _directManager(),
    _managerThenHr(),
    _managerThenDeptThenHr(),
    _campBossWorkflow(),
    _financeApproval(),
    _autoEscalating(),
    _emergencyExpress(),
  ];

  // ============================================================
  // القوالب
  // ============================================================

  /// 1️⃣ المدير المباشر فقط (auto-chain بقوّة 2)
  static WorkflowPreset _directManager() {
    return WorkflowPreset(
      key: 'direct_manager',
      nameAr: 'المدير المباشر فقط',
      nameEn: 'Direct Manager Only',
      descriptionAr: 'خطوة واحدة — المدير المباشر للمُقدِّم',
      descriptionEn: 'Single step — submitter\'s direct manager',
      stepCount: 1,
      icon: '👤',
      steps: [
        {
          'step': 0,
          'actor_type': 'auto_chain',
          'min_approval_power': 2,
          'label_ar': 'المدير المباشر',
          'label_en': 'Direct Manager',
          'require_signature': true,
        },
      ],
    );
  }

  /// 2️⃣ المدير → HR (سير شائع)
  static WorkflowPreset _managerThenHr() {
    return WorkflowPreset(
      key: 'manager_hr',
      nameAr: 'المدير ثم HR',
      nameEn: 'Manager → HR',
      descriptionAr: 'موافقة المدير ثم تأكيد HR',
      descriptionEn: 'Manager approval, then HR confirmation',
      stepCount: 2,
      icon: '👥',
      steps: [
        {
          'step': 0,
          'actor_type': 'auto_chain',
          'min_approval_power': 2,
          'label_ar': 'المدير المباشر',
          'label_en': 'Direct Manager',
          'require_signature': true,
        },
        {
          'step': 1,
          'actor_type': 'role',
          'role': 'hr',
          'label_ar': 'HR',
          'label_en': 'HR',
          'require_signature': true,
        },
      ],
    );
  }

  /// 3️⃣ المدير → رئيس القسم → HR (سير 3 طبقات)
  static WorkflowPreset _managerThenDeptThenHr() {
    return WorkflowPreset(
      key: 'manager_dept_hr',
      nameAr: 'المدير → رئيس القسم → HR',
      nameEn: 'Manager → Dept Head → HR',
      descriptionAr: 'سير ثلاثيّ للحالات الحسّاسة',
      descriptionEn: '3-tier workflow for sensitive cases',
      stepCount: 3,
      icon: '🏛️',
      steps: [
        {
          'step': 0,
          'actor_type': 'auto_chain',
          'min_approval_power': 2,
          'label_ar': 'المدير المباشر',
          'label_en': 'Direct Manager',
          'require_signature': true,
        },
        {
          'step': 1,
          'actor_type': 'auto_chain',
          'min_approval_power': 4,
          'label_ar': 'رئيس القسم',
          'label_en': 'Department Head',
          'require_signature': true,
        },
        {
          'step': 2,
          'actor_type': 'role',
          'role': 'hr',
          'label_ar': 'HR',
          'label_en': 'HR',
          'require_signature': true,
        },
      ],
    );
  }

  /// 4️⃣ سير الكامب: مدير الكامب → HR
  static WorkflowPreset _campBossWorkflow() {
    return WorkflowPreset(
      key: 'camp_workflow',
      nameAr: 'سير الكامب: Camp Boss → HR',
      nameEn: 'Camp: Camp Boss → HR',
      descriptionAr: 'لطلبات الكامب (إذونات، إجازات، انتهاكات)',
      descriptionEn: 'For camp requests (permits, leaves, violations)',
      stepCount: 2,
      icon: '🏕️',
      steps: [
        {
          'step': 0,
          'actor_type': 'role',
          'role': 'camp_boss',
          'label_ar': 'مدير الكامب',
          'label_en': 'Camp Boss',
          'require_signature': true,
        },
        {
          'step': 1,
          'actor_type': 'role',
          'role': 'hr',
          'label_ar': 'HR',
          'label_en': 'HR',
          'require_signature': true,
        },
      ],
    );
  }

  /// 5️⃣ موافقة ماليّة: مدير → مدير ماليّ
  static WorkflowPreset _financeApproval() {
    return WorkflowPreset(
      key: 'finance_approval',
      nameAr: 'موافقة ماليّة',
      nameEn: 'Finance Approval',
      descriptionAr: 'للقروض، السلف، المصاريف',
      descriptionEn: 'For loans, advances, expenses',
      stepCount: 2,
      icon: '💰',
      steps: [
        {
          'step': 0,
          'actor_type': 'auto_chain',
          'min_approval_power': 3,
          'label_ar': 'المدير المباشر',
          'label_en': 'Direct Manager',
          'require_signature': true,
        },
        {
          'step': 1,
          'actor_type': 'role',
          'role': 'finance_manager',
          'label_ar': 'المدير المالي',
          'label_en': 'Finance Manager',
          'require_signature': true,
        },
      ],
    );
  }

  /// 6️⃣ تصاعديّ تلقائي (قوّة 2 → 4 → 5)
  static WorkflowPreset _autoEscalating() {
    return WorkflowPreset(
      key: 'auto_escalating',
      nameAr: 'تصاعديّ تلقائي (هرم كامل)',
      nameEn: 'Auto-Escalating (full chain)',
      descriptionAr: 'يصعد الهرم تلقائياً بثلاث طبقات',
      descriptionEn: 'Auto-walks chain in 3 power levels',
      stepCount: 3,
      icon: '📈',
      steps: [
        {
          'step': 0,
          'actor_type': 'auto_chain',
          'min_approval_power': 2,
          'label_ar': 'المستوى الأوّل',
          'label_en': 'Level 1',
          'require_signature': true,
        },
        {
          'step': 1,
          'actor_type': 'auto_chain',
          'min_approval_power': 4,
          'label_ar': 'المستوى الثاني',
          'label_en': 'Level 2',
          'require_signature': true,
        },
        {
          'step': 2,
          'actor_type': 'auto_chain',
          'min_approval_power': 5,
          'label_ar': 'المستوى الأعلى',
          'label_en': 'Top Level',
          'require_signature': true,
        },
      ],
    );
  }

  /// 7️⃣ موافقة سريعة (مشرف واحد بقوّة 3)
  static WorkflowPreset _emergencyExpress() {
    return WorkflowPreset(
      key: 'emergency_express',
      nameAr: 'موافقة سريعة (طوارئ)',
      nameEn: 'Express Approval (urgent)',
      descriptionAr: 'خطوة واحدة عاجلة بقوّة 3+',
      descriptionEn: 'Single urgent step at power 3+',
      stepCount: 1,
      icon: '⚡',
      steps: [
        {
          'step': 0,
          'actor_type': 'auto_chain',
          'min_approval_power': 3,
          'label_ar': 'مشرف معتمَد',
          'label_en': 'Authorized Supervisor',
          'require_signature': false,
        },
      ],
    );
  }
}

/// نموذج قالب workflow
class WorkflowPreset {
  final String key;
  final String nameAr;
  final String nameEn;
  final String descriptionAr;
  final String descriptionEn;
  final int stepCount;
  final String icon; // emoji
  final List<Map<String, dynamic>> steps;

  WorkflowPreset({
    required this.key,
    required this.nameAr,
    required this.nameEn,
    required this.descriptionAr,
    required this.descriptionEn,
    required this.stepCount,
    required this.icon,
    required this.steps,
  });

  /// نسخة من steps قابلة للتعديل (deep copy)
  List<Map<String, dynamic>> stepsCopy() {
    return steps.map((s) => Map<String, dynamic>.from(s)).toList();
  }
}
