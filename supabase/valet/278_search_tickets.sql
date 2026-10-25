-- 278 · vv_search_tickets(p_token, p_query, p_days=60): up to 15 tickets of the point of the last p_days days
-- (any status: on the board, previous shifts, paid / out, finished) by ticket code / number, plate (part of it) or card.
-- Active first, then newest. Used by the accident report to link the customer car.
create or replace function public.vv_search_tickets(p_token text, p_query text, p_days int default 60)
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions' as $f$
declare v_s public.valet_sessions; v_err text; v_q text := trim(coalesce(p_query, '')); v_num text; v_card text;
begin
  v_s := public.vv_session(p_token);
  v_err := public.vv__need_point(v_s, false);
  if v_err is not null then return public.vv__err(v_err); end if;
  if length(v_q) < 2 then return public.vv__err('Type at least 2 characters of the plate or ticket number.'); end if;
  v_num := substring(v_q from '^(?:[Tt]-)?0*([0-9]{1,9})$');
  v_card := public.vv__norm(v_q);
  return jsonb_build_object('ok', true, 'error', null, 'tickets', coalesce((
    select jsonb_agg(public.vv__ticket_json(x.id) order by x.rk, x.entry_time desc)
    from (
      select t.id, t.entry_time, case when t.ticket_status = 'Active' then 0 else 1 end rk
        from public.valet_tickets t
       where t.point_id = v_s.point_id
         and t.entry_time >= now() - make_interval(days => greatest(coalesce(p_days, 60), 1))
         and (upper(t.ticket_code) = upper(v_q)
              or (v_num is not null and t.ticket_code like 'T-' || lpad(v_num, greatest(4, length(v_num)), '0') || '-%')
              or (v_card <> '' and public.vv__norm(t.plate_number) like '%' || v_card || '%')
              or (v_card <> '' and public.vv__norm(t.qr_card) = v_card))
       order by rk, t.entry_time desc
       limit 15) x), '[]'::jsonb));
end $f$;
grant execute on function public.vv_search_tickets(text, text, int) to anon, authenticated;
