-- Align the last dynamic-form dependency columns with the English API contract.
begin;

alter table public.device_field_dependencies rename column operador to operator;
alter table public.device_field_dependencies rename column valor_esperado to expected_value;

commit;
