import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "app.dimo.expenses",
  appName: "Dimo",
  webDir: "out",
  backgroundColor: "#f5f8f6",
  server: {
    androidScheme: "https",
    iosScheme: "https",
  },
  ios: {
    contentInset: "never",
    preferredContentMode: "mobile",
    backgroundColor: "#f5f8f6",
  },
};

export default config;
