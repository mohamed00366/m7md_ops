/// Search text: lower case, Arabic marks (تشكيل) and tatweel removed, alef / taa marbuta / yaa forms unified —
/// so «الشبكة» finds «الشَبَكة».
String searchNorm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[ً-ْٰـ]'), '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي');
