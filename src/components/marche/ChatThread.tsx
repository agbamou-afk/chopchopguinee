import { useEffect, useRef, useState } from "react";
import { ArrowLeft, Send, Phone, MessageCircle, Truck } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { QUICK_REPLIES } from "@/lib/marche";
import { toast } from "@/hooks/use-toast";
import { RequestMarcheDeliverySheet } from "./RequestMarcheDeliverySheet";
import { MISSION_STATE_LABEL, isTerminalState, type Mission } from "@/lib/missions/types";

interface Msg {
  id: string;
  sender_id: string;
  body: string | null;
  created_at: string;
}

export function ChatThread({
  conversationId,
  selfId,
  peerName,
  peerPhone,
  listingTitle,
  listingPrice,
  listingAvailability,
  listingId,
  sellerId,
  listingCategory,
  listingNeighborhood,
  listingCommune,
  listingLandmark,
  storeId,
  storeName,
  deliveryEligible,
  onBack,
}: {
  conversationId: string;
  selfId: string;
  peerName: string;
  peerPhone?: string | null;
  listingTitle: string;
  listingPrice?: number | null;
  listingAvailability?: string | null;
  listingId?: string;
  sellerId?: string;
  listingCategory?: string | null;
  listingNeighborhood?: string | null;
  listingCommune?: string | null;
  listingLandmark?: string | null;
  storeId?: string | null;
  storeName?: string | null;
  deliveryEligible?: boolean;
  onBack: () => void;
}) {
  const [msgs, setMsgs] = useState<Msg[]>([]);
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [deliveryOpen, setDeliveryOpen] = useState(false);
  const [activeMission, setActiveMission] = useState<Pick<Mission, "id" | "state"> | null>(null);
  const endRef = useRef<HTMLDivElement>(null);

  const isBuyer = !!sellerId && selfId !== sellerId;
  const canRequestDelivery = !!deliveryEligible && !!listingId && isBuyer;

  useEffect(() => {
    if (!listingId || !selfId) return;
    let alive = true;
    (async () => {
      const { data } = await supabase
        .from("missions")
        .select("id, state")
        .eq("type", "marketplace_delivery")
        .eq("customer_id", selfId)
        .order("created_at", { ascending: false })
        .limit(5);
      if (!alive || !data) return;
      // best-effort match — payload_summary contains the listing title.
      const candidate = (data as Pick<Mission, "id" | "state">[]).find((m) => !isTerminalState(m.state));
      if (candidate) setActiveMission(candidate);
    })();
    return () => {
      alive = false;
    };
  }, [listingId, selfId]);

  useEffect(() => {
    let mounted = true;
    (async () => {
      const { data } = await supabase
        .from("messages")
        .select("id, sender_id, body, created_at")
        .eq("conversation_id", conversationId)
        .order("created_at", { ascending: true });
      if (mounted && data) setMsgs(data as Msg[]);
    })();
    const ch = supabase
      .channel(`conv:${conversationId}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "messages", filter: `conversation_id=eq.${conversationId}` },
        (payload) => {
          setMsgs((prev) => [...prev, payload.new as Msg]);
        }
      )
      .subscribe();
    return () => {
      mounted = false;
      supabase.removeChannel(ch);
    };
  }, [conversationId]);

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [msgs]);

  const send = async (body: string) => {
    const trimmed = body.trim();
    if (!trimmed) return;
    setBusy(true);
    const { error } = await supabase
      .from("messages")
      .insert({ conversation_id: conversationId, sender_id: selfId, body: trimmed, kind: "text" });
    setBusy(false);
    if (error) {
      toast({ title: "Erreur", description: error.message });
      return;
    }
    setText("");
  };

  const sendDeliverySystemMsg = async () => {
    try {
      await supabase.from("messages").insert({
        conversation_id: conversationId,
        sender_id: selfId,
        body: "Livraison CHOP demandée. En attente d’un coursier.",
        kind: "text",
      });
    } catch {
      /* non-blocking */
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-background flex flex-col max-w-md mx-auto">
      <header className="flex items-center gap-3 p-4 border-b">
        <button onClick={onBack} className="p-2 -ml-2 rounded-full hover:bg-muted">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div className="flex-1 min-w-0">
          <p className="font-semibold truncate">{peerName}</p>
          <p className="text-xs text-muted-foreground truncate">
            {listingTitle}
            {listingPrice ? ` · ${new Intl.NumberFormat("fr-FR").format(listingPrice)} GNF` : ""}
            {listingAvailability ? ` · ${listingAvailability}` : ""}
          </p>
        </div>
        {peerPhone && (
          <div className="flex items-center gap-0.5">
            <a
              href={`tel:${peerPhone}`}
              aria-label="Appeler le vendeur"
              className="p-2 rounded-full hover:bg-muted text-muted-foreground"
            >
              <Phone className="w-[18px] h-[18px]" />
            </a>
            <a
              href={`https://wa.me/${peerPhone.replace(/[^0-9]/g, "")}`}
              target="_blank"
              rel="noreferrer"
              aria-label="Continuer sur WhatsApp (optionnel)"
              title="WhatsApp (optionnel)"
              className="p-2 rounded-full hover:bg-muted text-muted-foreground"
            >
              <MessageCircle className="w-[18px] h-[18px]" />
            </a>
          </div>
        )}
      </header>
      {(canRequestDelivery || activeMission) && (
        <div className="px-4 py-2 border-b bg-muted/40 flex items-center gap-2">
          {activeMission ? (
            <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-primary/10 text-primary text-[11px] font-medium">
              <Truck className="w-3 h-3" />
              Livraison CHOP · {MISSION_STATE_LABEL[activeMission.state]}
            </span>
          ) : (
            <Button
              size="sm"
              variant="outline"
              className="h-8 rounded-full text-xs"
              onClick={() => setDeliveryOpen(true)}
            >
              <Truck className="w-3.5 h-3.5 mr-1" />
              Demander livraison CHOP
            </Button>
          )}
        </div>
      )}
      <div className="flex-1 overflow-y-auto p-4 space-y-2">
        {msgs.map((m, i) => {
          const mine = m.sender_id === selfId;
          const prev = msgs[i - 1];
          const showStamp =
            !prev ||
            new Date(m.created_at).getTime() - new Date(prev.created_at).getTime() > 5 * 60 * 1000;
          const stamp = new Date(m.created_at).toLocaleTimeString([], {
            hour: "2-digit",
            minute: "2-digit",
          });
          const isLastOwn =
            mine && !msgs.slice(i + 1).some((x) => x.sender_id === selfId);
          return (
            <div key={m.id}>
              {showStamp && (
                <p className="text-[10px] text-muted-foreground text-center my-2">{stamp}</p>
              )}
              <div className={`flex ${mine ? "justify-end" : "justify-start"}`}>
              <div
                className={`max-w-[75%] px-3 py-2 rounded-2xl text-sm ${
                  mine ? "bg-primary text-primary-foreground rounded-br-sm" : "bg-muted text-foreground rounded-bl-sm"
                }`}
              >
                {m.body}
              </div>
              </div>
              {isLastOwn && (
                <p className="text-[10px] text-muted-foreground text-right mt-0.5 mr-1">
                  Envoyé
                </p>
              )}
            </div>
          );
        })}
        <div ref={endRef} />
      </div>
      <div className="px-4 pb-2 flex gap-2 overflow-x-auto scrollbar-none">
        {QUICK_REPLIES.map((q) => (
          <button
            key={q}
            onClick={() => send(q)}
            className="shrink-0 px-3 py-1.5 rounded-full bg-muted text-xs text-foreground hover:bg-muted/80"
          >
            {q}
          </button>
        ))}
      </div>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          send(text);
        }}
        className="flex items-center gap-2 p-3 border-t"
      >
        <Input
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Écrire un message…"
          maxLength={1000}
        />
        <Button type="submit" size="icon" disabled={busy || !text.trim()}>
          <Send className="w-4 h-4" />
        </Button>
      </form>
      {canRequestDelivery && listingId && (
        <RequestMarcheDeliverySheet
          open={deliveryOpen}
          onOpenChange={setDeliveryOpen}
          listing={{
            id: listingId,
            title: listingTitle,
            category: listingCategory ?? null,
            price_gnf: listingPrice ?? null,
            neighborhood: listingNeighborhood ?? null,
            commune: listingCommune ?? null,
            landmark: listingLandmark ?? null,
          }}
          buyerId={selfId}
          sellerName={peerName}
          storeId={storeId ?? null}
          storeName={storeName ?? null}
          onRequested={(missionId) => {
            setActiveMission({ id: missionId, state: "assigned" });
            sendDeliverySystemMsg();
          }}
        />
      )}
    </div>
  );
}