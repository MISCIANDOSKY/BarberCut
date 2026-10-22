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
    <App />
    <AppDialogs />
  </React.StrictMode>,
);
