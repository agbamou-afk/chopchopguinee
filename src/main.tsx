import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";
import { registerPwa } from "./lib/pwa/registerPwa";
import { initPerfTelemetry } from "./lib/analytics/perfEvents";
import { initTheme } from "./hooks/useTheme";
import { preloadClientOnboardingAssets } from "./lib/assets/preloadOnboardingAssets";

initTheme();

createRoot(document.getElementById("root")!).render(<App />);

initPerfTelemetry();
void registerPwa();
// Opportunistically warm the onboarding image cache. Resolves quickly on
// returning visitors (assets already cached) and never blocks the UI.
void preloadClientOnboardingAssets();
