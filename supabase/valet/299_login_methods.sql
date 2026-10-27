-- 299 – (app 2.5.3) staff sign-in may allow several methods at once: any of password, NFC card, QR card
-- (valet_point_settings.staff_login = 'password,nfc,qr', comma list). Ticket cards may be read with NFC and QR
-- together (card_reader = 'both').
alter table public.valet_point_settings drop constraint if exists valet_point_settings_staff_login_check;
alter table public.valet_point_settings add constraint valet_point_settings_staff_login_check
  check (staff_login is null or staff_login ~ '^(password|nfc|qr)(,(password|nfc|qr))*$');
alter table public.valet_point_settings drop constraint if exists valet_point_settings_card_reader_check;
alter table public.valet_point_settings add constraint valet_point_settings_card_reader_check
  check (card_reader is null or card_reader in ('nfc', 'qr', 'both'));

do $$
declare d text := pg_get_functiondef('public.vv_staff_login(text,text,text,text)'::regprocedure);
begin
  if position('vv299' in d) > 0 then return; end if;
  d := regexp_replace(d,
    '\n(\s*)if coalesce\(\(select coalesce\(s\.staff_login, case when coalesce\(s\.sinin_w_card, true\) then ''password'' else ''card'' end\)(.*?)staff card only\.''\);\n\s*end if;',
    E'\n\\1-- vv299: the point may allow several sign-in methods (password / NFC / QR)\n'
    || E'\\1v_methods := string_to_array(coalesce((select coalesce(s.staff_login, case when coalesce(s.sinin_w_card, true) then ''password'' else ''card'' end)\n'
    || E'\\1               from public.valet_point_settings s where s.point_id = v_s.point_id), ''password''), '','');\n'
    || E'\\1if p_password is not null and not (''password'' = any(v_methods)) then\n'
    || E'\\1  return public.vv__err(''On this point staff sign in with their staff card only.'');\n'
    || E'\\1end if;\n'
    || E'\\1if p_password is null and not (v_methods && array[''nfc'', ''qr'', ''card'']) then\n'
    || E'\\1  return public.vv__err(''On this point staff sign in with the user name and password.'');\n'
    || E'\\1end if;');
  d := regexp_replace(d, '\n(\s*)v_dev(\s+)uuid;', E'\n\\1v_dev\\2uuid;\n\\1v_methods text[];');
  if position('vv299' in d) = 0 or position('v_methods text[]' in d) = 0 then raise exception 'vv_staff_login patch did not apply'; end if;
  execute d;
end $$;
