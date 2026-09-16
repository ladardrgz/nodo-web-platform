"use client";

import { useEffect, useRef, useState, type ChangeEvent } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";
import { registerReceptionPhotoAction } from "@/features/repairs/reception/actions";
import { MAX_RECEPTION_PHOTO_SIZE, RECEPTION_PHOTO_TYPES } from "@/features/repairs/reception/constants/reception";
import type { EvidenceDraft } from "@/features/repairs/reception/types";

export function useReceptionPhotos({ setFieldError, notify }: {
  setFieldError: (key: string, value?: string) => void;
  notify: (message: string, variant: "success" | "error") => void;
}) {
  const [photos, setPhotos] = useState<EvidenceDraft[]>([]);
  const photosRef = useRef(photos);
  useEffect(() => {
    photosRef.current = photos;
  }, [photos]);

  function addPhotos(event: ChangeEvent<HTMLInputElement>) {
    const valid: EvidenceDraft[] = [];
    for (const file of [...(event.target.files ?? [])]) {
      if (!RECEPTION_PHOTO_TYPES.has(file.type)) { setFieldError("photos", "Solo se permiten fotografías PNG, JPG o WebP."); continue; }
      if (file.size > MAX_RECEPTION_PHOTO_SIZE) { setFieldError("photos", "Cada fotografía puede pesar hasta 5 MB."); continue; }
      valid.push({ id: crypto.randomUUID(), file, previewUrl: URL.createObjectURL(file), description: "", inspectionKey: "" });
    }
    if (valid.length) { setPhotos((current) => [...current, ...valid]); setFieldError("photos"); }
    event.target.value = "";
  }

  async function uploadPhotos(receptionId: string, prefix: string) {
    const supabase = createSupabaseBrowserClient();
    for (const photo of photos) {
      const extension = photo.file.type === "image/png" ? "png" : photo.file.type === "image/webp" ? "webp" : "jpg";
      const path = `${prefix}/${crypto.randomUUID()}.${extension}`;
      const upload = await supabase.storage.from("reception-photos").upload(path, photo.file, { contentType: photo.file.type, upsert: false });
      if (upload.error) { notify("No se pudo cargar la fotografía.", "error"); continue; }
      const metadata = await registerReceptionPhotoAction({ receptionId, storagePath: path, description: photo.description, inspectionKey: photo.inspectionKey });
      if (!metadata.ok) { await supabase.storage.from("reception-photos").remove([path]); notify(metadata.message, "error"); }
      else notify(metadata.message, "success");
    }
  }

  function disposePhotos() {
    photosRef.current.forEach((photo) => URL.revokeObjectURL(photo.previewUrl));
  }

  useEffect(() => disposePhotos, []);

  return { photos, setPhotos, addPhotos, uploadPhotos, disposePhotos };
}
