"use client";

import { AlertTriangle, CheckCircle2, Plus, Power, Search } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";

import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { createMasterCatalogItemAction, toggleMasterCatalogItemAction } from "@/features/superadmin/master-actions";
import type { MasterCatalogData, MasterDomain, MasterOption } from "@/features/superadmin/master-catalog/types";

const tabs: Array<{ id: MasterDomain; label: string }> = [
  { id: "general", label: "General" }, { id: "cpu", label: "CPU" }, { id: "gpu", label: "GPU" },
  { id: "motherboard", label: "Motherboards" }, { id: "ram", label: "RAM" }, { id: "storage", label: "Almacenamiento" }, { id: "reception", label: "Recepción" },
];

export function MasterCatalogConsole({ data, search }: { data: MasterCatalogData; search: string }) {
  const router = useRouter();
  const [message, setMessage] = useState("");
  const [pending, startTransition] = useTransition();
  const query = (changes: Record<string, string>) => {
    const params = new URLSearchParams({ type: data.deviceType.id, domain: data.domain, q: search, ...changes });
    router.replace(`/superadmin/master?${params.toString()}`);
  };
  const run = (task: () => Promise<{ ok: boolean; message: string }>) => startTransition(async () => { const result = await task(); setMessage(result.message); if (result.ok) router.refresh(); });

  return <div className="space-y-6">
    <Card className="p-5 sm:p-6">
      <div className="grid gap-4 lg:grid-cols-[minmax(220px,320px)_1fr] lg:items-end">
        <label className="text-sm font-semibold text-primary">Tipo de dispositivo<select className="field-control mt-2" value={data.deviceType.id} onChange={(event) => query({ type: event.target.value, q: "" })}>{data.deviceTypes.map((type) => <option key={type.id} value={type.id}>{type.name}</option>)}</select></label>
        <div className="flex flex-wrap gap-2">{tabs.map((tab) => <button className={tab.id === data.domain ? "rounded-lg bg-accent px-4 py-2 text-sm font-semibold text-white" : "rounded-lg border border-border bg-surface-raised px-4 py-2 text-sm font-semibold text-primary hover:bg-surface-soft"} key={tab.id} onClick={() => query({ domain: tab.id, q: "" })} type="button">{tab.label}</button>)}</div>
      </div>
    </Card>

    <CatalogHealth data={data} />
    <CatalogEditor data={data} disabled={pending} run={run} />

    <Card className="overflow-hidden">
      <div className="flex flex-col gap-3 border-b border-border p-4 sm:flex-row sm:items-center sm:justify-between">
        <div><h2 className="font-bold text-primary">Registros del dominio</h2><p className="text-sm text-muted">Hasta 50 resultados, filtrados en PostgreSQL.</p></div>
        <form className="relative w-full sm:max-w-sm"><input name="type" type="hidden" value={data.deviceType.id} /><input name="domain" type="hidden" value={data.domain} /><Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted" /><input className="field-control pl-10" defaultValue={search} name="q" placeholder="Buscar por nombre…" /></form>
      </div>
      <div className="overflow-x-auto"><table className="w-full min-w-[720px] text-left text-sm"><thead className="bg-surface-soft text-xs uppercase tracking-wide text-muted"><tr><th className="px-5 py-3">Nombre</th><th className="px-5 py-3">Relación</th><th className="px-5 py-3">Detalle</th><th className="px-5 py-3">Estado</th><th className="px-5 py-3">Acción</th></tr></thead><tbody>{data.rows.length ? data.rows.map((row) => <tr className="border-t border-border" key={`${row.entity}-${row.id}`}><td className="px-5 py-3 font-semibold text-primary">{row.primary}</td><td className="px-5 py-3 text-muted">{row.secondary}</td><td className="px-5 py-3 text-muted">{row.tertiary ?? compatibility(row)}</td><td className="px-5 py-3"><span className={row.active ? "rounded-full bg-success-soft px-2 py-1 text-xs font-semibold text-success" : "rounded-full bg-surface-soft px-2 py-1 text-xs font-semibold text-muted"}>{row.active ? "Activo" : "Inactivo"}</span></td><td className="px-5 py-3"><Button disabled={pending} onClick={() => run(() => toggleMasterCatalogItemAction({ entity: row.entity, id: row.id, active: !row.active }))} variant="secondary"><Power className="size-4" />{row.active ? "Desactivar" : "Reactivar"}</Button></td></tr>) : <tr><td className="px-5 py-10 text-center text-muted" colSpan={5}>No existen registros para esta selección.</td></tr>}</tbody></table></div>
    </Card>
    {message ? <p aria-live="polite" className="rounded-lg border border-border bg-surface-raised px-4 py-3 text-sm text-primary">{message}</p> : null}
  </div>;
}

function CatalogHealth({ data }: { data: MasterCatalogData }) {
  const entries = Object.entries(data.health.counts);
  return <section className="space-y-4"><div><p className="text-xs font-bold uppercase tracking-[.16em] text-accent">Estado del catálogo</p><h2 className="mt-1 text-xl font-bold text-primary">{data.deviceType.name}</h2></div><div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">{entries.map(([key,value])=><Card className="p-4" key={key}><p className="text-2xl font-bold text-primary">{value}</p><p className="mt-1 text-xs uppercase tracking-wide text-muted">{healthLabel(key)}</p></Card>)}</div>{data.health.warnings.length ? <Card className="border-warning/30 bg-warning/5 p-5"><div className="flex items-center gap-2 font-bold text-primary"><AlertTriangle className="size-5 text-warning" />Advertencias accionables</div><ul className="mt-3 space-y-2 text-sm text-muted">{data.health.warnings.slice(0,12).map((warning)=><li key={`${warning.kind}-${warning.targetId}`}>{warning.label}</li>)}</ul></Card> : <Card className="flex items-center gap-3 p-5"><CheckCircle2 className="size-5 text-success" /><p className="text-sm text-primary">No se detectaron relaciones vacías en los controles auditados.</p></Card>}</section>;
}

function CatalogEditor({ data, disabled, run }: { data: MasterCatalogData; disabled: boolean; run: (task:()=>Promise<{ok:boolean;message:string}>)=>void }) {
  const [kind,setKind]=useState(defaultKind(data.domain)); const [parentA,setParentA]=useState(""); const [parentB,setParentB]=useState("");
  const families=(data.options.families??[]).filter(x=>!parentA||x.parentId===parentA); const generations=(data.options.generations??[]).filter(x=>!parentB||x.parentId===parentB); const gpuFamilies=data.options.families??[];
  const submit=(event:React.FormEvent<HTMLFormElement>)=>{event.preventDefault();const form=new FormData(event.currentTarget);const selectedTypes=data.deviceTypes.filter(type=>form.get(`type-${type.id}`)==="on").map(type=>type.id);const common={kind,name:String(form.get("name")??"")};let payload:Record<string,unknown>=common;
    if(kind==="device_brand")payload={...common,deviceTypeIds:selectedTypes}; if(kind==="device_model")payload={...common,deviceTypeId:data.deviceType.id,brandId:parentA}; if(kind==="device_variant")payload={...common,modelId:parentA}; if(kind==="device_color")payload=common;
    if(kind==="processor_model")payload={...common,brandId:parentA,familyId:parentB,generationId:String(form.get("generationId")??""),notebook:form.get("notebook")==="on",desktop:form.get("desktop")==="on"};
    if(kind==="gpu_brand")payload=common;if(kind==="gpu_family")payload={...common,brandId:parentA};if(kind==="gpu_model")payload={...common,familyId:parentA,graphicsKind:String(form.get("graphicsKind")),notebook:form.get("notebook")==="on",desktop:form.get("desktop")==="on"};
    if(kind==="motherboard_manufacturer")payload=common;if(kind==="motherboard_model")payload={...common,manufacturerId:parentA,deviceTypeIds:selectedTypes};
    if(kind==="ram_type")payload={...common,code:String(form.get("code")??"")};if(kind==="ram_speed")payload={kind,ramTypeId:parentA,mhz:Number(form.get("mhz"))};
    if(kind==="storage_interface"||kind==="storage_form_factor")payload={kind:"storage_option",entity:kind,code:String(form.get("code")??""),name:String(form.get("name")??"")};
    if(kind==="reception_control")payload={kind,key:String(form.get("key")??""),label:String(form.get("name")??""),description:String(form.get("description")??""),critical:form.get("critical")==="on",deviceTypeIds:selectedTypes};
    run(()=>createMasterCatalogItemAction(payload));};
  const kinds=kindsFor(data.domain);return <Card className="p-5 sm:p-6"><div className="mb-4 flex items-center gap-2"><Plus className="size-5 text-accent"/><div><h2 className="font-bold text-primary">Nuevo registro</h2><p className="text-sm text-muted">La base valida duplicados, jerarquía y compatibilidad.</p></div></div><form className="grid gap-3 md:grid-cols-2 lg:grid-cols-4" onSubmit={submit}><select className="field-control" onChange={e=>{setKind(e.target.value);setParentA("");setParentB("");}} value={kind}>{kinds.map(x=><option key={x.id} value={x.id}>{x.label}</option>)}</select><EditorFields data={data} kind={kind} parentA={parentA} parentB={parentB} setParentA={setParentA} setParentB={setParentB} families={families} generations={generations} gpuFamilies={gpuFamilies}/><div className="flex items-end"><Button disabled={disabled} type="submit"><Plus className="size-4"/>Crear</Button></div></form></Card>;
}

function EditorFields({data,kind,parentA,parentB,setParentA,setParentB,families,generations,gpuFamilies}:{data:MasterCatalogData;kind:string;parentA:string;parentB:string;setParentA:(v:string)=>void;setParentB:(v:string)=>void;families:MasterOption[];generations:MasterOption[];gpuFamilies:MasterOption[]}) {
  const typeChecks=(kind==="device_brand"||kind==="motherboard_model"||kind==="reception_control")?<fieldset className="rounded-lg border border-border p-3"><legend className="px-1 text-xs font-semibold text-muted">Tipos relacionados</legend><div className="flex flex-wrap gap-3">{data.deviceTypes.map(type=><label className="text-sm text-primary" key={type.id}><input defaultChecked={type.id===data.deviceType.id} className="mr-2" name={`type-${type.id}`} type="checkbox"/>{type.name}</label>)}</div></fieldset>:null;
  if(kind==="device_model")return <><Select value={parentA} set={setParentA} label="Marca" options={data.options.brands}/><NameInput/></>; if(kind==="device_variant")return <><Select value={parentA} set={setParentA} label="Modelo" options={data.options.models}/><NameInput/></>; if(kind==="device_brand"||kind==="device_color")return <><NameInput/>{typeChecks}</>;
  if(kind==="processor_model")return <><Select value={parentA} set={v=>{setParentA(v);setParentB("");}} label="Fabricante" options={data.options.brands}/><Select value={parentB} set={setParentB} label="Familia" options={families}/><Select name="generationId" label="Serie / generación" options={generations}/><NameInput/><Compatibility/></>;
  if(kind==="gpu_family")return <><Select value={parentA} set={setParentA} label="Fabricante GPU" options={data.options.brands}/><NameInput/></>;if(kind==="gpu_model")return <><Select value={parentA} set={setParentA} label="Familia GPU" options={gpuFamilies}/><NameInput/><select className="field-control" name="graphicsKind"><option value="INTEGRATED">Integrada</option><option value="DEDICATED">Dedicada</option></select><Compatibility/></>;if(kind==="gpu_brand")return <NameInput/>;
  if(kind==="motherboard_model")return <><Select value={parentA} set={setParentA} label="Fabricante" options={data.options.manufacturers}/><NameInput/>{typeChecks}</>;if(kind==="motherboard_manufacturer")return <NameInput/>;
  if(kind==="ram_speed")return <><Select value={parentA} set={setParentA} label="Tipo RAM" options={data.options.ramTypes}/><input className="field-control" min="100" name="mhz" placeholder="Frecuencia MHz" required type="number"/></>;if(kind==="ram_type")return <><input className="field-control" name="code" placeholder="Código, ej. ddr5" required/><NameInput/></>;
  if(kind==="storage_interface"||kind==="storage_form_factor")return <><input className="field-control" name="code" placeholder="Código" required/><NameInput/></>;
  if(kind==="reception_control")return <><input className="field-control" name="key" pattern="[a-z][a-z0-9_]+" placeholder="clave_tecnica" required/><NameInput label="Etiqueta"/><input className="field-control" name="description" placeholder="Descripción opcional"/><label className="flex items-center gap-2 text-sm text-primary"><input name="critical" type="checkbox"/>Crítico</label>{typeChecks}</>;
  return <NameInput/>;
}

function NameInput({label="Nombre"}:{label?:string}){return <input aria-label={label} className="field-control" name="name" placeholder={label} required/>}function Select({label,options=[],name,value,set}:{label:string;options?:MasterOption[];name?:string;value?:string;set?:(v:string)=>void}){return <select className="field-control" name={name} onChange={set?e=>set(e.target.value):undefined} required value={value}><option value="">{label}</option>{options.map(x=><option key={x.id} value={x.id}>{x.name}</option>)}</select>}function Compatibility(){return <fieldset className="flex items-center gap-4 rounded-lg border border-border px-3"><legend className="sr-only">Compatibilidad</legend><label className="text-sm"><input className="mr-2" name="notebook" type="checkbox"/>Notebook</label><label className="text-sm"><input className="mr-2" name="desktop" type="checkbox"/>Desktop PC</label></fieldset>}
function defaultKind(domain:MasterDomain){return kindsFor(domain)[0].id}function kindsFor(domain:MasterDomain){const map:Record<MasterDomain,Array<{id:string;label:string}>>={general:[{id:"device_brand",label:"Marca"},{id:"device_model",label:"Modelo"},{id:"device_variant",label:"Variante"},{id:"device_color",label:"Color"}],cpu:[{id:"processor_model",label:"Modelo CPU"}],gpu:[{id:"gpu_brand",label:"Fabricante GPU"},{id:"gpu_family",label:"Familia GPU"},{id:"gpu_model",label:"Modelo GPU"}],motherboard:[{id:"motherboard_manufacturer",label:"Fabricante"},{id:"motherboard_model",label:"Modelo"}],ram:[{id:"ram_type",label:"Tipo RAM"},{id:"ram_speed",label:"Frecuencia RAM"}],storage:[{id:"storage_interface",label:"Interfaz"},{id:"storage_form_factor",label:"Factor de forma"}],reception:[{id:"reception_control",label:"Control de recepción"}]};return map[domain]}
function compatibility(row:{notebook?:boolean;desktop?:boolean}){const parts=[];if(row.notebook)parts.push("Notebook");if(row.desktop)parts.push("Desktop PC");return parts.join(" · ")||"—"}function healthLabel(key:string){return ({brands:"Marcas",models:"Modelos",variants:"Variantes",colors:"Colores",processor_brands:"Fabricantes CPU",processor_models:"Modelos CPU",gpu_brands:"Fabricantes GPU",gpu_models:"Modelos GPU",motherboard_models:"Motherboards",checklist_controls:"Controles"} as Record<string,string>)[key]??key}
