import { useCallback, useEffect, useRef, useState } from "react";
import { Loader2, MessageCircle, Send, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/hooks/use-toast";
import {
  listOrderMessages,
  markOrderMessagesRead,
  openOrderThread,
  QUICK_REPLIES,
  sendOrderMessage,
  type FoodOrderMessage,
  type FoodOrderSenderRole,
  type FoodOrderThreadType,
} from "@/lib/repas/orderMessaging";

interface Props {
  foodOrderId: string;
  threadType: FoodOrderThreadType;
  senderRole: FoodOrderSenderRole;
  /** Current user id, used to align messages right/left. */
  selfUserId: string | null;
  title?: string;
  /** Render the title row inline; defaults to true. */
  showHeader?: boolean;
  /** Optional: do not auto-open the thread on mount; require user click. */
  manualOpen?: boolean;
  emptyHint?: string;
}

const ROLE_LABEL: Record<FoodOrderSenderRole, string> = {
  client: "Client",
  restaurant: "Restaurant",
  courier: "Coursier",
  admin: "Support",
};

export function OrderMessagingPanel({
  foodOrderId,
  threadType,
  senderRole,
  selfUserId,
  title,
  showHeader = true,
  manualOpen = false,
  emptyHint = "Aucun message pour le moment.",
}: Props) {
  const [threadId, setThreadId] = useState<string | null>(null);
  const [opening, setOpening] = useState(false);
  const [messages, setMessages] = useState<FoodOrderMessage[]>([]);
  const [loading, setLoading] = useState(false);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const pollRef = useRef<number | null>(null);

  const quickReplies = QUICK_REPLIES[senderRole] ?? [];

  const ensureThread = useCallback(async () => {
    if (threadId || opening) return threadId;
    setOpening(true);
    setError(null);
    try {
      const id = await openOrderThread(foodOrderId, threadType);
      setThreadId(id);
      return id;
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Impossible d'ouvrir la conversation.";
      setError(msg);
      return null;
    } finally {
      setOpening(false);
    }
  }, [threadId, opening, foodOrderId, threadType]);

  const reload = useCallback(async (tid: string) => {
    setLoading(true);
    try {
      const list = await listOrderMessages(tid);
      setMessages(list);
      markOrderMessagesRead(tid).catch(() => {});
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Erreur de chargement.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (manualOpen) return;
    let alive = true;
    (async () => {
      const id = await ensureThread();
      if (!alive || !id) return;
      await reload(id);
    })();
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [foodOrderId, threadType, manualOpen]);

  useEffect(() => {
    if (!threadId) return;
    if (pollRef.current) window.clearInterval(pollRef.current);
    pollRef.current = window.setInterval(() => {
      reload(threadId);
    }, 20_000);
    return () => {
      if (pollRef.current) window.clearInterval(pollRef.current);
    };
  }, [threadId, reload]);

  const send = async (body: string) => {
    const tid = await ensureThread();
    if (!tid) return;
    const text = body.trim();
    if (!text) return;
    setSending(true);
    try {
      await sendOrderMessage({ threadId: tid, senderRole, body: text });
      setDraft("");
      await reload(tid);
    } catch (e: unknown) {
      toast({
        title: "Envoi impossible",
        description: e instanceof Error ? e.message : "Réessayez.",
      });
    } finally {
      setSending(false);
    }
  };

  if (manualOpen && !threadId) {
    return (
      <div className="rounded-xl border border-border/60 bg-muted/30 p-3">
        <Button
          size="sm"
          variant="outline"
          className="w-full"
          onClick={() => ensureThread().then((id) => id && reload(id))}
          disabled={opening}
        >
          {opening ? (
            <Loader2 className="w-4 h-4 animate-spin" />
          ) : (
            <>
              <MessageCircle className="w-4 h-4 mr-1.5" />
              {title ?? "Ouvrir la conversation"}
            </>
          )}
        </Button>
        {error && <p className="text-[11px] text-destructive mt-2">{error}</p>}
      </div>
    );
  }

  return (
    <div className="rounded-xl border border-border/60 bg-card/60 p-3">
      {showHeader && (
        <div className="flex items-center justify-between mb-2">
          <p className="text-xs font-semibold uppercase text-muted-foreground inline-flex items-center gap-1.5">
            <MessageCircle className="w-3.5 h-3.5" />
            {title ?? "Messages"}
          </p>
          <button
            type="button"
            onClick={() => threadId && reload(threadId)}
            className="text-muted-foreground hover:text-foreground"
            aria-label="Rafraîchir"
          >
            {loading ? (
              <Loader2 className="w-3.5 h-3.5 animate-spin" />
            ) : (
              <RefreshCw className="w-3.5 h-3.5" />
            )}
          </button>
        </div>
      )}

      <div className="max-h-56 overflow-y-auto space-y-1.5 mb-2">
        {opening || (loading && messages.length === 0) ? (
          <p className="text-xs text-muted-foreground py-2">Chargement…</p>
        ) : error ? (
          <p className="text-xs text-destructive py-2">{error}</p>
        ) : messages.length === 0 ? (
          <p className="text-xs text-muted-foreground py-2">{emptyHint}</p>
        ) : (
          messages.map((m) => {
            const mine = selfUserId && m.sender_user_id === selfUserId;
            return (
              <div
                key={m.id}
                className={`flex ${mine ? "justify-end" : "justify-start"}`}
              >
                <div
                  className={`max-w-[80%] rounded-2xl px-3 py-1.5 text-sm ${
                    mine
                      ? "bg-primary text-primary-foreground"
                      : "bg-muted text-foreground"
                  }`}
                >
                  {!mine && (
                    <p className="text-[10px] font-semibold opacity-70 mb-0.5">
                      {ROLE_LABEL[m.sender_role]}
                    </p>
                  )}
                  <p className="whitespace-pre-wrap break-words">{m.body}</p>
                  <p className="text-[10px] opacity-60 mt-0.5">
                    {new Date(m.created_at).toLocaleTimeString("fr-FR", {
                      hour: "2-digit",
                      minute: "2-digit",
                    })}
                  </p>
                </div>
              </div>
            );
          })
        )}
      </div>

      {quickReplies.length > 0 && (
        <div className="flex gap-1 flex-wrap mb-2">
          {quickReplies.map((q) => (
            <button
              key={q}
              type="button"
              onClick={() => send(q)}
              disabled={sending || opening}
              className="text-[11px] px-2 py-1 rounded-full bg-muted hover:bg-muted/80 border border-border/50 text-foreground disabled:opacity-50"
            >
              {q}
            </button>
          ))}
        </div>
      )}

      <div className="flex items-end gap-2">
        <Textarea
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="Écrire un message…"
          rows={1}
          className="min-h-[40px] max-h-32 text-sm flex-1"
          maxLength={2000}
        />
        <Button
          size="sm"
          onClick={() => send(draft)}
          disabled={sending || opening || !draft.trim()}
          aria-label="Envoyer"
        >
          {sending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
        </Button>
      </div>
    </div>
  );
}