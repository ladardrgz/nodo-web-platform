-- Reconciles the repository with the migration already applied remotely.
-- Source of truth: supabase_migrations.schema_migrations, version 20260915214304.
create table public.device_color_families (
  id uuid primary key default gen_random_uuid(), name text not null,
  normalized_name text generated always as (normalizar_nombre_catalogo(name)) stored,
  is_active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint ck_device_color_families_name check (char_length(btrim(name)) between 2 and 80),
  constraint uq_device_color_families_normalized_name unique (normalized_name)
);
alter table public.device_color_families enable row level security;
create policy device_color_families_read on public.device_color_families for select to authenticated using (is_active);
create table public.device_color_family_memberships (
  color_id uuid not null references public.device_colors(id) on delete cascade,
  family_id uuid not null references public.device_color_families(id) on delete cascade,
  created_at timestamptz not null default now(), primary key(color_id,family_id)
);
create index ix_device_color_family_memberships_family_id on public.device_color_family_memberships(family_id);
alter table public.device_color_family_memberships enable row level security;
create policy device_color_family_memberships_read on public.device_color_family_memberships for select to authenticated using (
 exists(select 1 from public.device_colors c where c.id=color_id and c.is_active and (c.alcance='GLOBAL' or c.fk_organizacion_id=current_organization_id()))
 and exists(select 1 from public.device_color_families f where f.id=family_id and f.is_active)
);
create temporary table seed_device_colors(family_name text,color_name text) on commit drop;
insert into seed_device_colors values
('Negro','Negro'),('Negro','Black'),('Negro','Matte Black'),('Negro','Glossy Black'),('Negro','Midnight Black'),('Negro','Jet Black'),('Negro','Phantom Black'),('Negro','Obsidian'),('Negro','Onyx Black'),('Negro','Cosmic Black'),('Negro','Carbon Black'),
('Gris','Gris'),('Gris','Gray/Grey'),('Gris','Graphite'),('Gris','Graphite Gray'),('Gris','Space Gray'),('Gris','Slate Gray'),('Gris','Charcoal'),('Gris','Gunmetal'),('Gris','Titanium Gray'),('Gris','Meteor Gray'),('Gris','Mineral Gray'),
('Plata','Plata'),('Plata','Silver'),('Plata','Platinum Silver'),('Plata','Mystic Silver'),('Plata','Arctic Silver'),('Plata','Lunar Silver'),('Plata','Titanium Silver'),('Plata','Natural Silver'),
('Blanco','Blanco'),('Blanco','White'),('Blanco','Pure White'),('Blanco','Ceramic White'),('Blanco','Pearl White'),('Blanco','Arctic White'),('Blanco','Snow White'),('Blanco','Moonlight White'),('Blanco','Cloud White'),
('Azul','Azul'),('Azul','Blue'),('Azul','Navy Blue'),('Azul','Midnight Blue'),('Azul','Ocean Blue'),('Azul','Sky Blue'),('Azul','Ice Blue'),('Azul','Arctic Blue'),('Azul','Sapphire Blue'),('Azul','Cobalt Blue'),('Azul','Royal Blue'),('Azul','Pacific Blue'),('Azul','Titanium Blue'),
('Celeste','Celeste'),('Celeste','Light Blue'),('Celeste','Baby Blue'),('Celeste','Aqua Blue'),('Celeste','Ice Blue'),('Celeste','Cloud Blue'),('Celeste','Crystal Blue'),
('Verde','Verde'),('Verde','Green'),('Verde','Forest Green'),('Verde','Emerald Green'),('Verde','Mint Green'),('Verde','Sage Green'),('Verde','Olive Green'),('Verde','Alpine Green'),('Verde','Jade Green'),('Verde','Teal'),('Verde','Sea Green'),
('Rojo','Rojo'),('Rojo','Red'),('Rojo','Product Red'),('Rojo','Crimson'),('Rojo','Burgundy'),('Rojo','Ruby Red'),('Rojo','Coral Red'),('Rojo','Flame Red'),
('Bordó','Bordó'),('Bordó','Burgundy'),('Bordó','Wine'),('Bordó','Wine Red'),('Bordó','Maroon'),('Bordó','Deep Red'),
('Rosa','Rosa'),('Rosa','Pink'),('Rosa','Rose'),('Rosa','Rose Pink'),('Rosa','Blush Pink'),('Rosa','Sakura Pink'),('Rosa','Flamingo Pink'),('Rosa','Pearl Pink'),
('Rosa dorado','Rose Gold'),('Rosa dorado','Pink Gold'),('Rosa dorado','Blush Gold'),
('Violeta','Violeta'),('Violeta','Purple'),('Violeta','Violet'),('Violeta','Lavender'),('Violeta','Lilac'),('Violeta','Orchid'),('Violeta','Deep Purple'),('Violeta','Awesome Violet'),
('Dorado','Dorado'),('Dorado','Gold'),('Dorado','Champagne Gold'),('Dorado','Pale Gold'),('Dorado','Satin Gold'),('Dorado','Mystic Gold'),
('Champagne','Champagne'),('Champagne','Champagne Gold'),('Champagne','Champagne Silver'),('Champagne','Soft Gold'),
('Bronce','Bronze'),('Bronce','Mystic Bronze'),('Bronce','Copper Bronze'),('Bronce','Titanium Bronze'),
('Cobre','Copper'),('Cobre','Copper Gold'),('Cobre','Copper Orange'),('Cobre','Metallic Copper'),
('Naranja','Orange'),('Naranja','Coral'),('Naranja','Peach'),('Naranja','Sunset Orange'),('Naranja','Amber'),('Naranja','Tangerine'),
('Amarillo','Yellow'),('Amarillo','Lemon Yellow'),('Amarillo','Canary Yellow'),('Amarillo','Sunshine Yellow'),
('Beige','Beige'),('Beige','Cream'),('Beige','Sand'),('Beige','Desert Sand'),('Beige','Porcelain'),('Beige','Ivory'),
('Marrón','Brown'),('Marrón','Chocolate'),('Marrón','Mocha'),('Marrón','Coffee'),('Marrón','Walnut'),
('Turquesa','Turquoise'),('Turquesa','Aqua'),('Turquesa','Cyan'),('Turquesa','Teal'),('Turquesa','Mint Blue'),
('Verde azulado','Teal'),('Verde azulado','Blue Green'),('Verde azulado','Ocean Green'),('Verde azulado','Aqua Green'),
('Transparente','Transparent'),('Transparente','Clear'),
('Multicolor','Multicolor'),('Multicolor','Gradient'),('Multicolor','Iridescent'),('Multicolor','Prism'),('Multicolor','Aurora');
insert into public.device_color_families(name) select distinct family_name from seed_device_colors on conflict(normalized_name) do nothing;
insert into public.device_colors(name,alcance,fk_organizacion_id) select distinct color_name,'GLOBAL',null::uuid from seed_device_colors on conflict(normalized_name,fk_organizacion_id) do nothing;
insert into public.device_color_family_memberships(color_id,family_id)
select c.id,f.id from seed_device_colors s
join public.device_colors c on c.normalized_name=normalizar_nombre_catalogo(s.color_name) and c.fk_organizacion_id is null
join public.device_color_families f on f.normalized_name=normalizar_nombre_catalogo(s.family_name)
on conflict do nothing;
