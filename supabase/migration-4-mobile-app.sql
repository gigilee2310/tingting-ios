-- Ting Ting — migration 4: quyền cho app iPhone (chạy MỘT LẦN trong Supabase → SQL Editor).
-- App iPhone nói chuyện thẳng với Supabase bằng tài khoản của bạn (không qua server web),
-- nên cần thêm 2 nhóm quyền mà trước đây web làm bằng "secret key" trên server:
--   1) Ghi giá thị trường (bảng market_prices dùng chung).
--   2) Xoá dữ liệu CỦA CHÍNH MÌNH (tài sản, giao dịch, sổ tiết kiệm, snapshot).
-- An toàn khi chạy lại nhiều lần.

do $$
begin
  -- 1) market_prices: người đã đăng nhập được thêm/sửa giá
  if not exists (select 1 from pg_policies where tablename = 'market_prices' and policyname = 'mp_insert_auth') then
    create policy "mp_insert_auth" on market_prices for insert to authenticated with check (true);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'market_prices' and policyname = 'mp_update_auth') then
    create policy "mp_update_auth" on market_prices for update to authenticated using (true) with check (true);
  end if;
end $$;

-- 2) Xoá dòng của chính mình
do $$
declare t text;
begin
  foreach t in array array['assets','transactions','savings_accounts','daily_snapshots']
  loop
    if not exists (select 1 from pg_policies where tablename = t and policyname = 'own_delete') then
      execute format('create policy "own_delete" on %I for delete using (auth.uid() = user_id)', t);
    end if;
  end loop;
end $$;
