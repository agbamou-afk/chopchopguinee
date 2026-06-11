import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { getStoreBySlug, type MerchantStore } from "@/lib/marche/stores";
import { StoreProfile } from "@/components/marche/StoreProfile";
import { LoadingState } from "@/components/ui/LoadingState";
import { EmptyState } from "@/components/ui/EmptyState";

export default function PublicStorefront() {
  const { slug } = useParams<{ slug: string }>();
  const navigate = useNavigate();
  const [store, setStore] = useState<MerchantStore | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    (async () => {
      if (!slug) { setLoading(false); return; }
      const s = await getStoreBySlug(slug);
      if (!alive) return;
      setStore(s);
      setLoading(false);
    })();
    return () => { alive = false; };
  }, [slug]);

  if (loading) return <div className="max-w-md mx-auto p-6"><LoadingState variant="cards" rows={3} /></div>;
  if (!store) {
    return (
      <div className="max-w-md mx-auto p-6">
        <EmptyState
          title="Boutique introuvable"
          description="Cette boutique n'est pas disponible publiquement."
        />
      </div>
    );
  }
  return (
    <StoreProfile
      storeId={store.id}
      onBack={() => navigate(-1)}
      onOpenListing={(id) => navigate(`/?listing=${id}`)}
    />
  );
}
