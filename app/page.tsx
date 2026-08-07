import { AuthGate } from "@/auth/AuthGate";
import { PublicHome } from "@/components/marketing/PublicHome";

export default function Page() {
  return (
    <AuthGate>
      <PublicHome />
    </AuthGate>
  );
}
