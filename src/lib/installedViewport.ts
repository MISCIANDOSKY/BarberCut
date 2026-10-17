// Installed PWAs use an app-like gesture surface; ordinary browser zoom is unchanged.
const displayMode = window.matchMedia("(display-mode: standalone)");
const isInstalled = () =>
  displayMode.matches ||
  (navigator as Navigator & { standalone?: boolean }).standalone === true;
function syncMode() {
  document.documentElement.classList.toggle("installed-pwa", isInstalled());
}
syncMode();
displayMode.addEventListener("change", syncMode);

const preventInstalledZoom = (event: Event) => {
  if (isInstalled() && event.cancelable) event.preventDefault();
};
document.addEventListener("gesturestart", preventInstalledZoom, { passive: false });
document.addEventListener("gesturechange", preventInstalledZoom, { passive: false });
document.addEventListener("touchmove", (event: TouchEvent) => {
  if (event.touches.length > 1) preventInstalledZoom(event);
}, { passive: false });
