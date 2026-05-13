import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";
import { registerPwa } from "./lib/pwa/registerPwa";
import { initPerfTelemetry } from "./lib/analytics/perfEvents";

createRoot(document.getElementById("root")!).render(<App />);

initPerfTelemetry();
void registerPwa();
