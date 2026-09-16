-- Global, idempotent data completion for Notebook intake.  It only feeds
-- existing catalog tables; no device history or schema is rewritten.
begin;

-- Graphics: manufacturer -> family -> mobile/integrated model.  Names are
-- commercial identifiers only; no VRAM, TGP or CPU/GPU coupling is implied.
insert into public.gpu_brands (code, name) values
  ('intel', 'Intel'), ('amd', 'AMD'), ('nvidia', 'NVIDIA')
on conflict (code) do update set name = excluded.name, is_active = true;

with family_data(brand_code, code, name) as (values
  ('intel','hd_graphics','HD Graphics'), ('intel','uhd_graphics','UHD Graphics'),
  ('intel','iris_graphics','Iris Graphics'), ('intel','iris_xe','Iris Xe'), ('intel','arc_graphics','Arc Graphics'),
  ('amd','radeon_graphics','Radeon Graphics'), ('amd','vega','Radeon Vega'),
  ('amd','radeon_600m','Radeon 600M'), ('amd','radeon_700m','Radeon 700M'),
  ('amd','radeon_800m','Radeon 800M'), ('amd','radeon_rx_5000m','Radeon RX 5000M'),
  ('amd','radeon_rx_6000m','Radeon RX 6000M'), ('amd','radeon_rx_7000m','Radeon RX 7000M'),
  ('nvidia','geforce_900m','GeForce 900M'), ('nvidia','geforce_mx','GeForce MX'),
  ('nvidia','geforce_gtx_10','GeForce GTX 10 Series'), ('nvidia','geforce_gtx_16','GeForce GTX 16 Series'),
  ('nvidia','geforce_rtx_20','GeForce RTX 20 Series'), ('nvidia','rtx_30','GeForce RTX 30 Series'),
  ('nvidia','geforce_rtx_40','GeForce RTX 40 Series'), ('nvidia','geforce_rtx_50','GeForce RTX 50 Series')
)
insert into public.gpu_families (fk_gpu_brand_id, code, name)
select b.id, f.code, f.name from family_data f join public.gpu_brands b on b.code = f.brand_code
on conflict (fk_gpu_brand_id, code) do update set name = excluded.name, is_active = true;

with model_data(brand_code, family_code, code, name, graphics_kind) as (values
  ('intel','hd_graphics','hd_graphics','Intel HD Graphics','INTEGRATED'),
  ('intel','hd_graphics','hd_3000','Intel HD Graphics 3000','INTEGRATED'),
  ('intel','hd_graphics','hd_4000','Intel HD Graphics 4000','INTEGRATED'),
  ('intel','hd_graphics','hd_4400','Intel HD Graphics 4400','INTEGRATED'),
  ('intel','hd_graphics','hd_4600','Intel HD Graphics 4600','INTEGRATED'),
  ('intel','hd_graphics','hd_5000','Intel HD Graphics 5000','INTEGRATED'),
  ('intel','hd_graphics','hd_520','Intel HD Graphics 520','INTEGRATED'),
  ('intel','hd_graphics','hd_530','Intel HD Graphics 530','INTEGRATED'),
  ('intel','uhd_graphics','uhd_graphics','Intel UHD Graphics','INTEGRATED'),
  ('intel','uhd_graphics','uhd_600','Intel UHD Graphics 600','INTEGRATED'),
  ('intel','uhd_graphics','uhd_605','Intel UHD Graphics 605','INTEGRATED'),
  ('intel','uhd_graphics','uhd_610','Intel UHD Graphics 610','INTEGRATED'),
  ('intel','uhd_graphics','uhd_620','Intel UHD Graphics 620','INTEGRATED'),
  ('intel','uhd_graphics','uhd_630','Intel UHD Graphics 630','INTEGRATED'),
  ('intel','uhd_graphics','uhd_710','Intel UHD Graphics 710','INTEGRATED'),
  ('intel','iris_graphics','iris_5100','Intel Iris Graphics 5100','INTEGRATED'),
  ('intel','iris_graphics','iris_540','Intel Iris Graphics 540','INTEGRATED'),
  ('intel','iris_graphics','iris_550','Intel Iris Graphics 550','INTEGRATED'),
  ('intel','iris_graphics','iris_6100','Intel Iris Graphics 6100','INTEGRATED'),
  ('intel','iris_graphics','iris_650','Intel Iris Plus Graphics 650','INTEGRATED'),
  ('intel','iris_xe','iris_xe_graphics','Intel Iris Xe Graphics','INTEGRATED'),
  ('intel','arc_graphics','arc_graphics','Intel Arc Graphics','INTEGRATED'),
  ('intel','arc_graphics','arc_130v','Intel Arc 130V','INTEGRATED'),
  ('intel','arc_graphics','arc_140v','Intel Arc 140V','INTEGRATED'),
  ('intel','arc_graphics','arc_140t','Intel Arc 140T','INTEGRATED'),
  ('amd','radeon_graphics','radeon_graphics','AMD Radeon Graphics','INTEGRATED'),
  ('amd','vega','vega_3','AMD Radeon Vega 3','INTEGRATED'), ('amd','vega','vega_6','AMD Radeon Vega 6','INTEGRATED'),
  ('amd','vega','vega_7','AMD Radeon Vega 7','INTEGRATED'), ('amd','vega','vega_8','AMD Radeon Vega 8','INTEGRATED'),
  ('amd','vega','vega_10','AMD Radeon Vega 10','INTEGRATED'), ('amd','vega','vega_11','AMD Radeon Vega 11','INTEGRATED'),
  ('amd','radeon_600m','radeon_610m','AMD Radeon 610M','INTEGRATED'), ('amd','radeon_600m','radeon_660m','AMD Radeon 660M','INTEGRATED'),
  ('amd','radeon_600m','radeon_680m','AMD Radeon 680M','INTEGRATED'),
  ('amd','radeon_700m','radeon_740m','AMD Radeon 740M','INTEGRATED'), ('amd','radeon_700m','radeon_760m','AMD Radeon 760M','INTEGRATED'),
  ('amd','radeon_700m','radeon_780m','AMD Radeon 780M','INTEGRATED'),
  ('amd','radeon_800m','radeon_840m','AMD Radeon 840M','INTEGRATED'), ('amd','radeon_800m','radeon_860m','AMD Radeon 860M','INTEGRATED'),
  ('amd','radeon_800m','radeon_880m','AMD Radeon 880M','INTEGRATED'), ('amd','radeon_800m','radeon_890m','AMD Radeon 890M','INTEGRATED'),
  ('amd','radeon_rx_5000m','rx_5300m','AMD Radeon RX 5300M','DEDICATED'), ('amd','radeon_rx_5000m','rx_5500m','AMD Radeon RX 5500M','DEDICATED'),
  ('amd','radeon_rx_5000m','rx_5600m','AMD Radeon RX 5600M','DEDICATED'),
  ('amd','radeon_rx_6000m','rx_6600m','AMD Radeon RX 6600M','DEDICATED'), ('amd','radeon_rx_6000m','rx_6700m','AMD Radeon RX 6700M','DEDICATED'),
  ('amd','radeon_rx_6000m','rx_6800m','AMD Radeon RX 6800M','DEDICATED'), ('amd','radeon_rx_6000m','rx_6850m_xt','AMD Radeon RX 6850M XT','DEDICATED'),
  ('amd','radeon_rx_7000m','rx_7600m_xt','AMD Radeon RX 7600M XT','DEDICATED'), ('amd','radeon_rx_7000m','rx_7600s','AMD Radeon RX 7600S','DEDICATED'),
  ('amd','radeon_rx_7000m','rx_7700s','AMD Radeon RX 7700S','DEDICATED'),
  ('nvidia','geforce_900m','920m','NVIDIA GeForce 920M','DEDICATED'), ('nvidia','geforce_900m','930m','NVIDIA GeForce 930M','DEDICATED'),
  ('nvidia','geforce_900m','940m','NVIDIA GeForce 940M','DEDICATED'), ('nvidia','geforce_900m','950m','NVIDIA GeForce 950M','DEDICATED'),
  ('nvidia','geforce_900m','960m','NVIDIA GeForce 960M','DEDICATED'), ('nvidia','geforce_900m','970m','NVIDIA GeForce 970M','DEDICATED'),
  ('nvidia','geforce_900m','980m','NVIDIA GeForce GTX 980M','DEDICATED'),
  ('nvidia','geforce_mx','mx110','NVIDIA GeForce MX110','DEDICATED'), ('nvidia','geforce_mx','mx130','NVIDIA GeForce MX130','DEDICATED'),
  ('nvidia','geforce_mx','mx150','NVIDIA GeForce MX150','DEDICATED'), ('nvidia','geforce_mx','mx230','NVIDIA GeForce MX230','DEDICATED'),
  ('nvidia','geforce_mx','mx250','NVIDIA GeForce MX250','DEDICATED'), ('nvidia','geforce_mx','mx330','NVIDIA GeForce MX330','DEDICATED'),
  ('nvidia','geforce_mx','mx350','NVIDIA GeForce MX350','DEDICATED'), ('nvidia','geforce_mx','mx450','NVIDIA GeForce MX450','DEDICATED'),
  ('nvidia','geforce_mx','mx550','NVIDIA GeForce MX550','DEDICATED'), ('nvidia','geforce_mx','mx570','NVIDIA GeForce MX570','DEDICATED'),
  ('nvidia','geforce_gtx_10','gtx_1050','NVIDIA GeForce GTX 1050','DEDICATED'), ('nvidia','geforce_gtx_10','gtx_1050_ti','NVIDIA GeForce GTX 1050 Ti','DEDICATED'),
  ('nvidia','geforce_gtx_10','gtx_1060','NVIDIA GeForce GTX 1060','DEDICATED'), ('nvidia','geforce_gtx_10','gtx_1070','NVIDIA GeForce GTX 1070','DEDICATED'),
  ('nvidia','geforce_gtx_10','gtx_1080','NVIDIA GeForce GTX 1080','DEDICATED'),
  ('nvidia','geforce_gtx_16','gtx_1650','NVIDIA GeForce GTX 1650','DEDICATED'), ('nvidia','geforce_gtx_16','gtx_1650_ti','NVIDIA GeForce GTX 1650 Ti','DEDICATED'),
  ('nvidia','geforce_gtx_16','gtx_1660_ti','NVIDIA GeForce GTX 1660 Ti','DEDICATED'),
  ('nvidia','geforce_rtx_20','rtx_2050','NVIDIA GeForce RTX 2050','DEDICATED'), ('nvidia','geforce_rtx_20','rtx_2060','NVIDIA GeForce RTX 2060','DEDICATED'),
  ('nvidia','geforce_rtx_20','rtx_2070','NVIDIA GeForce RTX 2070','DEDICATED'), ('nvidia','geforce_rtx_20','rtx_2080','NVIDIA GeForce RTX 2080','DEDICATED'),
  ('nvidia','rtx_30','rtx_3050','NVIDIA GeForce RTX 3050','DEDICATED'), ('nvidia','rtx_30','rtx_3050_ti','NVIDIA GeForce RTX 3050 Ti','DEDICATED'),
  ('nvidia','rtx_30','rtx_3060','NVIDIA GeForce RTX 3060','DEDICATED'), ('nvidia','rtx_30','rtx_3070','NVIDIA GeForce RTX 3070','DEDICATED'),
  ('nvidia','rtx_30','rtx_3070_ti','NVIDIA GeForce RTX 3070 Ti','DEDICATED'), ('nvidia','rtx_30','rtx_3080','NVIDIA GeForce RTX 3080','DEDICATED'),
  ('nvidia','rtx_30','rtx_3080_ti','NVIDIA GeForce RTX 3080 Ti','DEDICATED'),
  ('nvidia','geforce_rtx_40','rtx_4050','NVIDIA GeForce RTX 4050 Laptop GPU','DEDICATED'), ('nvidia','geforce_rtx_40','rtx_4060','NVIDIA GeForce RTX 4060 Laptop GPU','DEDICATED'),
  ('nvidia','geforce_rtx_40','rtx_4070','NVIDIA GeForce RTX 4070 Laptop GPU','DEDICATED'), ('nvidia','geforce_rtx_40','rtx_4080','NVIDIA GeForce RTX 4080 Laptop GPU','DEDICATED'),
  ('nvidia','geforce_rtx_40','rtx_4090','NVIDIA GeForce RTX 4090 Laptop GPU','DEDICATED'),
  ('nvidia','geforce_rtx_50','rtx_5050','NVIDIA GeForce RTX 5050 Laptop GPU','DEDICATED'), ('nvidia','geforce_rtx_50','rtx_5060','NVIDIA GeForce RTX 5060 Laptop GPU','DEDICATED'),
  ('nvidia','geforce_rtx_50','rtx_5070','NVIDIA GeForce RTX 5070 Laptop GPU','DEDICATED'), ('nvidia','geforce_rtx_50','rtx_5070_ti','NVIDIA GeForce RTX 5070 Ti Laptop GPU','DEDICATED'),
  ('nvidia','geforce_rtx_50','rtx_5080','NVIDIA GeForce RTX 5080 Laptop GPU','DEDICATED'), ('nvidia','geforce_rtx_50','rtx_5090','NVIDIA GeForce RTX 5090 Laptop GPU','DEDICATED')
)
insert into public.gpu_models (fk_gpu_family_id, code, name, graphics_kind, notebook_supported)
select f.id, m.code, m.name, m.graphics_kind, true
from model_data m join public.gpu_brands b on b.code = m.brand_code
join public.gpu_families f on f.fk_gpu_brand_id = b.id and f.code = m.family_code
on conflict (fk_gpu_family_id, code) do update set name = excluded.name, graphics_kind = excluded.graphics_kind, notebook_supported = true, is_active = true;

-- Complete frequent speeds and capacities used by notebooks.  Capacity remains
-- a numeric catalog, rather than a duplicated list per storage model.
with speed_data(ram_code, mhz) as (values
  ('ddr',200),('ddr',266),('ddr',333),('ddr',400),
  ('ddr2',400),('ddr2',533),('ddr2',667),('ddr2',800),('ddr2',1066),
  ('ddr3',1066),('ddr3',1333),('ddr3',1600),('ddr3',1866),('ddr3',2133),
  ('ddr4',2133),('ddr4',2400),('ddr4',2666),('ddr4',2933),('ddr4',3200),
  ('ddr5',4800),('ddr5',5200),('ddr5',5600),('ddr5',6000),('ddr5',6400),('ddr5',7200),
  ('lpddr3',1600),('lpddr3',1866),('lpddr4',2133),('lpddr4',2400),('lpddr4',2666),('lpddr4',3200),
  ('lpddr4x',3200),('lpddr4x',3733),('lpddr4x',4266),('lpddr5',4800),('lpddr5',5500),('lpddr5',6400),
  ('lpddr5x',6400),('lpddr5x',7467),('lpddr5x',8533)
)
insert into public.ram_speeds (fk_ram_type_id, mhz)
select r.id, s.mhz from speed_data s join public.ram_types r on r.code = s.ram_code
on conflict (fk_ram_type_id, mhz) do update set is_active = true;

insert into public.storage_capacities (capacity_gb, label) values
  (16,'16 GB'),(160,'160 GB'),(320,'320 GB'),(640,'640 GB'),(768,'768 GB'),
  (1536,'1.5 TB'),(3072,'3 TB'),(6144,'6 TB'),(12288,'12 TB'),(16384,'16 TB')
on conflict (capacity_gb) do update set is_active = true;

insert into public.operating_systems (code, name, organization_id, is_active) values
  ('windows_xp','Windows XP',null,true),('windows_vista','Windows Vista',null,true),
  ('windows_7','Windows 7',null,true),('windows_8','Windows 8',null,true),('windows_8_1','Windows 8.1',null,true),
  ('windows_10_home','Windows 10 Home',null,true),('windows_10_pro','Windows 10 Pro',null,true),
  ('windows_11_home','Windows 11 Home',null,true),('windows_11_pro','Windows 11 Pro',null,true),
  ('windows_server','Windows Server',null,true),('macos','macOS',null,true),('chromeos','ChromeOS',null,true),
  ('ubuntu_22_04','Ubuntu 22.04 LTS',null,true),('linux_mint','Linux Mint',null,true),
  ('fedora','Fedora Linux',null,true),('arch_linux','Arch Linux',null,true),('other_linux','Otro Linux',null,true),
  ('freebsd','FreeBSD',null,true),('no_operating_system','Sin sistema operativo',null,true),
  ('unknown_operating_system','No determinado',null,true)
on conflict (code) where code is not null do update set name = excluded.name, is_active = true;

-- These are intake accessories, deliberately generic and global.
insert into public.device_accessories (nombre, alcance, fk_organizacion_id, activo)
select v.nombre, 'GLOBAL', null, true
from (values
  ('Cargador'),('Cable de alimentación'),('Adaptador USB-C'),('Adaptador de corriente'),
  ('Batería externa'),('Mouse'),('Mousepad'),('Teclado externo'),('Funda'),('Maletín'),
  ('Mochila'),('Base refrigerante'),('Dock / estación de acoplamiento'),('Adaptador HDMI'),
  ('Adaptador DisplayPort'),('Adaptador VGA'),('Adaptador Ethernet'),('Hub USB'),
  ('Pendrive'),('Disco externo'),('Tarjeta SD'),('Receptor USB'),('Lápiz óptico'),
  ('Manual'),('Caja original')
) as v(nombre)
where not exists (
  select 1 from public.device_accessories a
  where a.fk_organizacion_id is null and a.nombre_normalizado = public.normalizar_nombre_catalogo(v.nombre)
);

-- Existing hardware catalog consumed by the Notebook display/connectivity/ports
-- fields.  Each item is a neutral observable attribute, not a compatibility claim.
insert into public.hardware_catalog_items (category, code, name) values
  ('DISPLAY_SIZE','11in','11"'),('DISPLAY_SIZE','12_3in','12.3"'),('DISPLAY_SIZE','12_4in','12.4"'),
  ('DISPLAY_SIZE','12_9in','12.9"'),('DISPLAY_SIZE','13_4in','13.4"'),('DISPLAY_SIZE','13_5in','13.5"'),
  ('DISPLAY_SIZE','13_9in','13.9"'),('DISPLAY_SIZE','14_1in','14.1"'),('DISPLAY_SIZE','15_4in','15.4"'),
  ('DISPLAY_SIZE','15_8in','15.8"'),('DISPLAY_SIZE','16_2in','16.2"'),('DISPLAY_SIZE','17_0in','17.0"'),
  ('DISPLAY_RESOLUTION','1280x720','1280×720'),('DISPLAY_RESOLUTION','1280x800','1280×800'),
  ('DISPLAY_RESOLUTION','1440x900','1440×900'),('DISPLAY_RESOLUTION','1920x1280','1920×1280'),
  ('DISPLAY_RESOLUTION','2160x1350','2160×1350'),('DISPLAY_RESOLUTION','2240x1400','2240×1400'),
  ('DISPLAY_RESOLUTION','2400x1600','2400×1600'),('DISPLAY_RESOLUTION','2736x1824','2736×1824'),
  ('DISPLAY_RESOLUTION','2880x1920','2880×1920'),('DISPLAY_RESOLUTION','3024x1964','3024×1964'),
  ('DISPLAY_RESOLUTION','3072x1920','3072×1920'),('DISPLAY_RESOLUTION','3456x2160','3456×2160'),
  ('DISPLAY_TECHNOLOGY','lcd','LCD'),('DISPLAY_TECHNOLOGY','amoled','AMOLED'),('DISPLAY_TECHNOLOGY','wva','WVA'),
  ('DISPLAY_REFRESH_RATE','50_Hz','50 Hz'),('DISPLAY_REFRESH_RATE','100_Hz','100 Hz'),
  ('DISPLAY_REFRESH_RATE','180_Hz','180 Hz'),('DISPLAY_REFRESH_RATE','300_Hz','300 Hz'),
  ('DISPLAY_REFRESH_RATE','360_Hz','360 Hz'),('DISPLAY_REFRESH_RATE','480_Hz','480 Hz'),
  ('CONNECTIVITY','wwan_lte','WWAN / 4G LTE'),('CONNECTIVITY','wwan_5g','WWAN / 5G'),('CONNECTIVITY','nfc','NFC'),
  ('PORT_CONNECTOR','thunderbolt_3','Thunderbolt 3'),('PORT_CONNECTOR','thunderbolt_4','Thunderbolt 4'),
  ('PORT_CONNECTOR','thunderbolt_5','Thunderbolt 5'),('PORT_CONNECTOR','usb4','USB4'),
  ('PORT_CONNECTOR','expresscard','ExpressCard'),('PORT_CONNECTOR','smart_card','Lector de tarjeta inteligente'),
  ('PORT_CONNECTOR','sim','SIM'),('PORT_CONNECTOR','kensington_lock','Ranura Kensington')
on conflict (category, code) do update set name = excluded.name, is_active = true;

commit;
