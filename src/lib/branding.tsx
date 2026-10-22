import { createContext, useContext, useEffect, useState } from "react";
import type { ReactNode } from "react";
import { supabase } from "./api";
const BrandContext = createContext("BarberUp");
let activeName = "BarberUp";
export const getBrandName = () => activeName;
export const useBrandName = () => useContext(BrandContext);
export function BrandProvider({ children }: { children: ReactNode }) {
  const [name, setName] = useState(activeName);
  useEffect(() => {
    let stopped = false, revision = 0;
    let activation: ReturnType<typeof setTimeout> | undefined;
    const load = async () => {
      const request = ++revision;
      const { data, error } = await supabase.rpc("app_branding");
      if (stopped || request !== revision || error || typeof data?.name !== "string") return;
      activeName = data.name;
      setName(data.name);
      document.documentElement.dataset.appName = data.name;
      document.title = data.name + " · Il tuo tempo, il tuo stile";
      document.querySelector('meta[name="description"]')?.setAttribute("content",data.name + " — prenota il tuo prossimo taglio, in pochi gesti.");
      document.querySelector('meta[name="apple-mobile-web-app-title"]')?.setAttribute("content",data.name);
      clearTimeout(activation);
      if (data.changes_at) {
        const delay = Date.parse(data.changes_at) - Date.parse(data.server_time);
        activation = setTimeout(() => void load(), Math.max(100, delay + 100));
      }
    };
    const resume = () => { if (!document.hidden) void load(); };
    void load();
    const timer = setInterval(resume, 30000);
    window.addEventListener("focus",resume);
    window.addEventListener("online",resume);
    document.addEventListener("visibilitychange",resume);
    return () => {
      stopped = true; revision++; clearInterval(timer); clearTimeout(activation);
      window.removeEventListener("focus",resume); window.removeEventListener("online",resume);
      document.removeEventListener("visibilitychange",resume);
    };
  }, []);
  return <BrandContext.Provider value={name}>{children}</BrandContext.Provider>;
}
