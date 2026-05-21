import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";
import { registerPwa } from "./lib/pwa/registerPwa";
import { initPerfTelemetry } from "./lib/analytics/perfEvents";
import { initTheme } from "./hooks/useTheme";

initTheme();

createRoot(document.getElementById("root")!).render(<App />);

initPerfTelemetry();
void registerPwa();
