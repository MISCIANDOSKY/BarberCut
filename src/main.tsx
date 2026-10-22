import { BrandProvider } from "./lib/branding";
import React from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import { AppDialogs } from "./components/AppDialogs";
import "./styles.css";
import "./lib/installedViewport";
import { initializeTheme } from "./lib/theme.mjs";
initializeTheme();
createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <BrandProvider><App /></BrandProvider>
    <AppDialogs />
  </React.StrictMode>,
);
