-- Global commercial brands for device type Celular, from the supplied catalogue.
-- ROG is deliberately excluded: the source defines it as an ASUS line, not a separate brand.
begin;

with source(name) as (
  select value
  from jsonb_array_elements_text($cell_phone_brands$["Samsung","Motorola","Apple","Xiaomi","Redmi","POCO","TCL","Alcatel","ZTE","Nubia","RedMagic","Honor","Huawei","OPPO","Realme","OnePlus","Vivo","Tecno","Infinix","itel","Nokia","HMD","LG","Sony","Sony Ericsson","Lenovo","ASUS","Google","BlackBerry","Microsoft","HTC","BLU","BGH","Noblex","Philco","Positivo","Quantum","Meizu","Nothing","CMF","Blackview","UMIDIGI","Ulefone","Oukitel","Doogee","CAT","Hisense","Zuum","Senwa","Sky Devices","Wiko","Gionee","LeEco","Coolpad","ZUK","Essential","Fairphone","Sharp","Panasonic","Sagem","Siemens","BenQ","Palm","Kyocera","Razer"]$cell_phone_brands$::jsonb)
)
insert into public.device_brands (name, alcance, fk_organizacion_id, is_active)
select s.name, 'GLOBAL', null, true
from source s
where not exists (
  select 1 from public.device_brands b
  where b.fk_organizacion_id is null
    and b.normalized_name = public.normalizar_nombre_catalogo(s.name)
);

with source(name) as (
  select value
  from jsonb_array_elements_text($cell_phone_brands$["Samsung","Motorola","Apple","Xiaomi","Redmi","POCO","TCL","Alcatel","ZTE","Nubia","RedMagic","Honor","Huawei","OPPO","Realme","OnePlus","Vivo","Tecno","Infinix","itel","Nokia","HMD","LG","Sony","Sony Ericsson","Lenovo","ASUS","Google","BlackBerry","Microsoft","HTC","BLU","BGH","Noblex","Philco","Positivo","Quantum","Meizu","Nothing","CMF","Blackview","UMIDIGI","Ulefone","Oukitel","Doogee","CAT","Hisense","Zuum","Senwa","Sky Devices","Wiko","Gionee","LeEco","Coolpad","ZUK","Essential","Fairphone","Sharp","Panasonic","Sagem","Siemens","BenQ","Palm","Kyocera","Razer"]$cell_phone_brands$::jsonb)
), cell_phone_type as (
  select id from public.device_types
  where code = 'cell_phone' and is_active
)
insert into public.device_type_brands (fk_tipo_dispositivo_id, fk_marca_dispositivo_id)
select t.id, b.id
from cell_phone_type t
join source s on true
join public.device_brands b
  on b.fk_organizacion_id is null
 and b.normalized_name = public.normalizar_nombre_catalogo(s.name)
on conflict do nothing;

commit;
