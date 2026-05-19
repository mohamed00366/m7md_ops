-- ============================================================
-- M7 W Management - بذور المدن والمناطق
-- شغّل هذا الملف في Supabase SQL Editor بعد m7w_full_schema.sql
-- لإضافة مدن ومناطق تجريبية لكل دولة
-- ============================================================

-- ===== Cities =====
insert into public.cities (country_id, name_ar, name_en)
select c.id, x.name_ar, x.name_en
from public.countries c
cross join (values
  ('SA','الرياض','Riyadh'),
  ('SA','جدة','Jeddah'),
  ('SA','الدمام','Dammam'),
  ('SA','مكة المكرمة','Makkah'),
  ('AE','دبي','Dubai'),
  ('AE','أبو ظبي','Abu Dhabi'),
  ('AE','الشارقة','Sharjah'),
  ('EG','القاهرة','Cairo'),
  ('EG','الإسكندرية','Alexandria'),
  ('EG','الجيزة','Giza'),
  ('KW','مدينة الكويت','Kuwait City'),
  ('KW','حولي','Hawalli')
) as x(country_code, name_ar, name_en)
where c.code = x.country_code;

-- ===== Areas =====
insert into public.areas (city_id, name_ar, name_en)
select ci.id, x.name_ar, x.name_en
from public.cities ci
inner join public.countries co on co.id = ci.country_id
cross join (values
  ('SA','Riyadh','حي الملز','Al Malaz'),
  ('SA','Riyadh','حي العليا','Olaya'),
  ('SA','Riyadh','حي السليمانية','Sulaimaniyah'),
  ('SA','Riyadh','حي الورود','Al Wurud'),
  ('SA','Jeddah','حي الروضة','Al Rawdah'),
  ('SA','Jeddah','حي الزهراء','Al Zahra'),
  ('SA','Jeddah','حي البساتين','Al Basateen'),
  ('SA','Dammam','حي الفيصلية','Al Faisaliyah'),
  ('SA','Dammam','حي البديع','Al Badi'),
  ('SA','Makkah','العزيزية','Al Aziziyah'),
  ('SA','Makkah','العوالي','Al Awali'),
  ('AE','Dubai','الديرة','Deira'),
  ('AE','Dubai','بر دبي','Bur Dubai'),
  ('AE','Dubai','مارينا دبي','Dubai Marina'),
  ('AE','Dubai','الجميرا','Jumeirah'),
  ('AE','Abu Dhabi','الكورنيش','Corniche'),
  ('AE','Abu Dhabi','المصفح','Mussafah'),
  ('AE','Sharjah','المجاز','Al Majaz'),
  ('AE','Sharjah','الناصرية','Al Nasiriyah'),
  ('EG','Cairo','مدينة نصر','Nasr City'),
  ('EG','Cairo','المعادي','Maadi'),
  ('EG','Cairo','الزمالك','Zamalek'),
  ('EG','Alexandria','سيدي بشر','Sidi Bishr'),
  ('EG','Alexandria','المنتزه','Al Montaza'),
  ('EG','Giza','الدقي','Dokki'),
  ('EG','Giza','المهندسين','Mohandessin'),
  ('KW','Kuwait City','شرق','Sharq'),
  ('KW','Kuwait City','الصالحية','Salhiyah'),
  ('KW','Hawalli','السالمية','Salmiya'),
  ('KW','Hawalli','الجابرية','Jabriya')
) as x(country_code, city_name, name_ar, name_en)
where co.code = x.country_code and ci.name_en = x.city_name;

-- ===== Lookups: Job Titles, Departments, etc. =====
insert into public.job_titles (name_ar, name_en) values
  ('مدير', 'Manager'),
  ('مشرف', 'Supervisor'),
  ('موظف خدمة عملاء', 'Customer Service'),
  ('سائق', 'Driver'),
  ('عامل', 'Worker'),
  ('محاسب', 'Accountant'),
  ('سكرتير', 'Secretary'),
  ('فني', 'Technician');

insert into public.departments (name_ar, name_en) values
  ('الإدارة', 'Management'),
  ('العمليات', 'Operations'),
  ('المبيعات', 'Sales'),
  ('الموارد البشرية', 'Human Resources'),
  ('المحاسبة', 'Accounting'),
  ('التقنية', 'IT'),
  ('الصيانة', 'Maintenance');

insert into public.marital_statuses (name_ar, name_en) values
  ('أعزب', 'Single'),
  ('متزوج', 'Married'),
  ('مطلق', 'Divorced'),
  ('أرمل', 'Widowed');

insert into public.nationalities (name_ar, name_en, iso_code) values
  ('سعودي', 'Saudi', 'SA'),
  ('إماراتي', 'Emirati', 'AE'),
  ('مصري', 'Egyptian', 'EG'),
  ('كويتي', 'Kuwaiti', 'KW'),
  ('باكستاني', 'Pakistani', 'PK'),
  ('هندي', 'Indian', 'IN'),
  ('فلبيني', 'Filipino', 'PH'),
  ('بنغلاديشي', 'Bangladeshi', 'BD'),
  ('سوداني', 'Sudanese', 'SD'),
  ('يمني', 'Yemeni', 'YE');

insert into public.visa_types (name_ar, name_en) values
  ('عمل', 'Work Visa'),
  ('زيارة', 'Visit Visa'),
  ('إقامة', 'Residence'),
  ('مواطن', 'Citizen');

insert into public.business_types (name_ar, name_en) values
  ('مطعم', 'Restaurant'),
  ('مقهى', 'Café'),
  ('سوبرماركت', 'Supermarket'),
  ('صيدلية', 'Pharmacy'),
  ('محل ملابس', 'Clothing Store'),
  ('صالون', 'Salon'),
  ('بنزينة', 'Gas Station'),
  ('فندق', 'Hotel');

-- التحقق
-- select count(*) from public.cities;
-- select count(*) from public.areas;
-- select count(*) from public.job_titles;
