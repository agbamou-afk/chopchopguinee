import { useEffect, useState } from "react";
import { ArrowLeft, MessageSquare } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { ChatThread } from "./ChatThread";
import { timeAgo } from "@/lib/marche";

interface Conv {
  id: string;
  listing_id: string;
  buyer_id: string;
  seller_id: string;
  last_message_at: string;
  listing: { title: string } | null;
  buyer: { full_name: string | null } | null;
  seller: { full_name: string | null } | null;
}

export function InboxView({ onBack }: { onBack: () => void }) {
  const [convs, setConvs] = useState<Conv[]>([]);
  const [selfId, setSelfId] = useState<string | null>(null);
  const [openId, setOpenId] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      const { data: sess } = await supabase.auth.getSession();
      const uid = sess.session?.user.id ?? null;
      setSelfId(uid);
      if (!uid) return;
      const { data } = await supabase
        .from("conversations")
        .select("id, listing_id, buyer_id, seller_id, last_message_at, listing:marketplace_listings(title)")
        .or(`buyer_id.eq.${uid},seller_id.eq.${uid}`)
        .order("last_message_at", { ascending: false });
      const rows = (data ?? []) as unknown as Conv[];
      // fetch peer names in batch
      const peerIds = Array.from(new Set(rows.map((r) => (r.buyer_id === uid ? r.seller_id : r.buyer_id))));
      const { data: profs } = peerIds.length
        ? await supabase.from("profiles").select("user_id, full_name").in("user_id", peerIds)
        : { data: [] as { user_id: string; full_name: string | null }[] };
      const map = new Map((profs ?? []).map((p) => [p.user_id, p.full_name]));
      setConvs(
        rows.map((r) => ({
          ...r,
          buyer: r.buyer_id === uid ? null : { full_name: map.get(r.buyer_id) ?? null },
          seller: r.seller_id === uid ? null : { full_name: map.get(r.seller_id) ?? null },
        }))
      );
    })();
  }, []);

  const open = convs.find((c) => c.id === openId);

  return (
    <div className="max-w-md mx-auto min-h-screen bg-background">
      <header className="flex items-center gap-3 p-4 border-b sticky top-0 bg-background z-10">
        <button onClick={onBack} className="p-2 -ml-2 rounded-full hover:bg-muted">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <h1 className="font-semibold">Messages Marché</h1>
      </header>
      {!selfId ? (
        <div className="p-8 text-center text-muted-foreground">Connectez-vous pour voir vos messages.</div>
      ) : convs.length === 0 ? (
        <div className="p-8 text-center text-muted-foreground">
          <MessageSquare className="w-10 h-10 mx-auto mb-2 opacity-50" />
          Aucune conversation pour le moment.
        </div>
      ) : (
        <ul className="divide-y">
          {convs.map((c) => {
            const peerName = (c.buyer?.full_name ?? c.seller?.full_name) || "Utilisateur CHOP CHOP";
            return (
              <li key={c.id}>
                <button onClick={() => setOpenId(c.id)} className="w-full text-left p-4 hover:bg-muted/50">
                  <div className="flex items-center justify-between gap-2">
                    <p className="font-medium truncate">{peerName}</p>
                    <span className="text-[10px] text-muted-foreground shrink-0">{timeAgo(c.last_message_at)}</span>
                  </div>
                  <p className="text-sm text-muted-foreground truncate">{c.listing?.title ?? "Annonce"}</p>
                </button>
              </li>
            );
          })}
        </ul>
      )}
      {open && selfId && (
        <ChatThread
          conversationId={open.id}
          selfId={selfId}
          peerName={(open.buyer?.full_name ?? open.seller?.full_name) || "Utilisateur"}
          listingTitle={open.listing?.title ?? "Annonce"}
          onBack={() => setOpenId(null)}
        />
      )}
    </div>
  );
}