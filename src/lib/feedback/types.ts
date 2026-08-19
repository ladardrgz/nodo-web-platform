export type ToastVariant = "success" | "error" | "warning" | "info";

export interface ToastOptions {
  title: string;
  description?: string;
  variant?: ToastVariant;
  duration?: number;
}

export interface ActionFeedbackState {
  status: "idle" | "error" | "success";
  feedback?: ToastOptions;
}
