import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft, Camera, Loader2, Shield, KeyRound, ScrollText, Lock, ChevronRight, Trash2, X } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast } from "@/hooks/use-toast";
import { BrandLogo } from "@/components/brand/BrandLogo";
import { Seo } from "@/components/Seo";
import { GuineaPhoneInput } from "@/components/ui/guinea-phone-input";
import { SelfDeleteAccountSheet } from "@/components/account/SelfDeleteAccountSheet";
import {
  GUINEA_PHONE_INVALID_MESSAGE,
  extractGuineaLocal,
  isValidGuineaLocal,
  normalizeGuineaPhone,
} from "@/lib/phone/guinea";

export default function ProfileInfo() {
  const navigate = useNavigate();
  const { refresh } = useAuth();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [email, setEmail] = useState("");
  const [fullName, setFullName] = useState("");
  const [phone, setPhone] = useState("");
  const [avatarUrl, setAvatarUrl] = useState<string | null>(null);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const [newPassword, setNewPassword] = useState("");
  const [deleteOpen, setDeleteOpen] = useState(false);

  useEffect(() => {
    (async () => {
      const { data } = await supabase.auth.getSession();
      if (!data.session) {
        navigate("/auth", { replace: true });
        return;
      }
      setEmail(data.session.user.email ?? "");
      const { data: prof } = await supabase
        .from("profiles")
        .select("full_name, phone, avatar_url")
        .eq("user_id", data.session.user.id)
        .maybeSingle();
      if (prof) {
        setFullName(prof.full_name ?? "");
        setPhone(extractGuineaLocal(prof.phone ?? ""));
        setAvatarUrl((prof as any).avatar_url ?? null);
      }
      setLoading(false);
    })();
  }, [navigate]);

  const saveProfile = async () => {
    if (phone && !isValidGuineaLocal(phone)) {
      toast({ title: "Erreur", description: GUINEA_PHONE_INVALID_MESSAGE });
      return;
    }
    setSaving(true);
    const { data: sess } = await supabase.auth.getSession();
    if (!sess.session) return;
    const { error } = await supabase
      .from("profiles")
      .update({ full_name: fullName, phone: phone ? normalizeGuineaPhone(phone) : null })
      .eq("user_id", sess.session.user.id);
    setSaving(false);
    if (error) toast({ title: "Erreur", description: error.message });
    else toast({ title: "Profil mis à jour" });
  };

  const updatePassword = async () => {
    if (newPassword.length < 6) {
      toast({ title: "Mot de passe trop court", description: "6 caractères minimum" });
      return;
    }
    const { error } = await supabase.auth.updateUser({ password: newPassword });
    if (error) toast({ title: "Erreur", description: error.message });
    else {
      setNewPassword("");
      toast({ title: "Mot de passe modifié" });
    }
  };

  const ALLOWED_AVATAR_TYPES = ["image/jpeg", "image/png", "image/webp"];
  const MAX_AVATAR_BYTES = 5 * 1024 * 1024; // 5 MB

  const handleAvatarFile = async (file: File) => {
    if (!ALLOWED_AVATAR_TYPES.includes(file.type)) {
      toast({ title: "Format non supporté", description: "Format d'image non supporté. Choisissez JPG, PNG ou WEBP." });
      return;
    }
    if (file.size > MAX_AVATAR_BYTES) {
      toast({ title: "Image trop lourde", description: "Image trop lourde. Choisissez une image plus légère (max 5 Mo)." });
      return;
    }
    setUploadingAvatar(true);
    try {
      const { data: sess } = await supabase.auth.getSession();
      const uid = sess.session?.user.id;
      if (!uid) return;
      const ext = file.type === "image/png" ? "png" : file.type === "image/webp" ? "webp" : "jpg";
      const path = `${uid}/avatar-${Date.now()}.${ext}`;
      const { error: upErr } = await supabase.storage
        .from("profile-avatars")
        .upload(path, file, { contentType: file.type, upsert: true, cacheControl: "3600" });
      if (upErr) throw upErr;
      const { data: signed, error: sErr } = await supabase.storage
        .from("profile-avatars")
        .createSignedUrl(path, 60 * 60 * 24 * 365);
      if (sErr || !signed?.signedUrl) throw sErr ?? new Error("no signed url");
      const { error: updErr } = await supabase
        .from("profiles")
        .update({ avatar_url: signed.signedUrl })
        .eq("user_id", uid);
      if (updErr) throw updErr;
      setAvatarUrl(signed.signedUrl);
      await refresh();
      toast({ title: "Photo de profil mise à jour" });
    } catch (e) {
      const msg = e instanceof Error ? e.message : "";
      console.error("[avatar-upload]", msg);
      toast({ title: "Échec", description: "Impossible d'envoyer la photo pour le moment." });
    } finally {
      setUploadingAvatar(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  };

  const removeAvatar = async () => {
    setUploadingAvatar(true);
    try {
      const { data: sess } = await supabase.auth.getSession();
      const uid = sess.session?.user.id;
      if (!uid) return;
      // Best-effort: remove all files in the user's folder.
      const { data: list } = await supabase.storage.from("profile-avatars").list(uid);
      if (list && list.length > 0) {
        await supabase.storage
          .from("profile-avatars")
          .remove(list.map((f) => `${uid}/${f.name}`));
      }
      const { error: updErr } = await supabase
        .from("profiles")
        .update({ avatar_url: null })
        .eq("user_id", uid);
      if (updErr) throw updErr;
      setAvatarUrl(null);
      await refresh();
      toast({ title: "Photo supprimée" });
    } catch {
      toast({ title: "Échec", description: "Impossible de supprimer la photo pour le moment." });
    } finally {
      setUploadingAvatar(false);
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="w-6 h-6 animate-spin text-primary" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background pb-12">
      <Seo
        title="Mon profil — CHOPCHOP"
        description="Gérez vos informations personnelles, votre photo de profil et la sécurité de votre compte CHOPCHOP."
        canonical="/profile"
      />
      <header className="gradient-primary text-primary-foreground rounded-b-3xl px-4 pt-6 pb-8">
        <div className="flex items-center gap-3">
          <button onClick={() => navigate(-1)} className="p-2 -ml-2 rounded-full hover:bg-white/10">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <BrandLogo size="md" loading="lazy" />
          <h1 className="text-lg font-bold">Mon profil</h1>
        </div>
      </header>

      <div className="px-4 -mt-6 max-w-md mx-auto space-y-4">
        <div className="bg-card rounded-2xl shadow-card p-5 flex flex-col items-center">
          <div className="relative">
            <div className="w-24 h-24 rounded-full bg-muted flex items-center justify-center text-3xl font-bold text-primary overflow-hidden">
              {avatarUrl ? (
                <img loading="lazy" decoding="async" src={avatarUrl} alt="Photo de profil de l'utilisateur" className="w-full h-full object-cover" />
              ) : (
                (fullName || email)[0]?.toUpperCase() ?? "?"
              )}
              {uploadingAvatar && (
                <div className="absolute inset-0 bg-background/60 flex items-center justify-center rounded-full">
                  <Loader2 className="w-5 h-5 animate-spin text-primary" />
                </div>
              )}
            </div>
            <button
              type="button"
              aria-label="Changer la photo de profil"
              onClick={() => fileInputRef.current?.click()}
              disabled={uploadingAvatar}
              className="absolute bottom-0 right-0 p-2 rounded-full bg-primary text-primary-foreground shadow disabled:opacity-60"
            >
              <Camera className="w-4 h-4" />
            </button>
            <input
              ref={fileInputRef}
              type="file"
              accept="image/jpeg,image/png,image/webp"
              className="hidden"
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) void handleAvatarFile(f);
              }}
            />
          </div>
          <p className="mt-3 text-sm text-muted-foreground">{email}</p>
          <p className="mt-1 text-[11px] text-muted-foreground text-center px-2">
            Ajoutez une photo pour personnaliser votre profil CHOPCHOP. JPG, PNG ou WEBP, 5 Mo max.
            <br />
            <span className="text-[10px] opacity-80">
              Votre photo de profil est différente des documents de vérification chauffeur.
            </span>
          </p>
          <div className="mt-3 flex gap-2">
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={uploadingAvatar}
              onClick={() => fileInputRef.current?.click()}
            >
              <Camera className="w-4 h-4 mr-2" />
              {avatarUrl ? "Changer la photo" : "Ajouter une photo"}
            </Button>
            {avatarUrl && (
              <Button
                type="button"
                variant="ghost"
                size="sm"
                disabled={uploadingAvatar}
                onClick={removeAvatar}
              >
                <X className="w-4 h-4 mr-2" />
                Supprimer
              </Button>
            )}
          </div>
        </div>

        <div className="bg-card rounded-2xl shadow-card p-5 space-y-3">
          <h2 className="font-semibold text-foreground">Informations personnelles</h2>
          <div className="space-y-2">
            <Label htmlFor="name">Nom complet</Label>
            <Input id="name" value={fullName} onChange={(e) => setFullName(e.target.value)} maxLength={100} />
          </div>
          <div className="space-y-2">
            <Label htmlFor="phone">Téléphone</Label>
            <GuineaPhoneInput id="phone" value={phone} onChange={setPhone} />
          </div>
          <Button onClick={saveProfile} disabled={saving} className="w-full">
            {saving && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
            Enregistrer
          </Button>
        </div>

        <div className="bg-card rounded-2xl shadow-card p-5 space-y-3">
          <h2 className="font-semibold text-foreground flex items-center gap-2">
            <Shield className="w-4 h-4 text-primary" /> Sécurité du compte
          </h2>
          <div className="space-y-2">
            <Label htmlFor="pw">Nouveau mot de passe</Label>
            <Input
              id="pw"
              type="password"
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              maxLength={72}
              placeholder="6 caractères minimum"
            />
          </div>
          <Button variant="secondary" onClick={updatePassword} className="w-full">
            <KeyRound className="w-4 h-4 mr-2" />
            Modifier le mot de passe
          </Button>
        </div>

        <div className="bg-card rounded-2xl shadow-card p-5 space-y-1">
          <h2 className="font-semibold text-foreground flex items-center gap-2 mb-2">
            <ScrollText className="w-4 h-4 text-primary" /> Légal & confidentialité
          </h2>
          <button
            onClick={() => navigate("/terms")}
            className="w-full flex items-center justify-between py-3 text-sm hover:bg-muted/40 rounded-lg px-2"
          >
            <span>Conditions d'utilisation</span>
            <ChevronRight className="w-4 h-4 text-muted-foreground" />
          </button>
          <button
            onClick={() => navigate("/privacy")}
            className="w-full flex items-center justify-between py-3 text-sm hover:bg-muted/40 rounded-lg px-2"
          >
            <span>Politique de confidentialité</span>
            <ChevronRight className="w-4 h-4 text-muted-foreground" />
          </button>
          <button
            onClick={() => navigate("/settings/permissions")}
            className="w-full flex items-center justify-between py-3 text-sm hover:bg-muted/40 rounded-lg px-2"
          >
            <span className="flex items-center gap-2"><Lock className="w-4 h-4 text-muted-foreground" /> Permissions & données</span>
            <ChevronRight className="w-4 h-4 text-muted-foreground" />
          </button>
        </div>

        <div className="bg-card rounded-2xl shadow-card p-5 space-y-3 border border-destructive/20">
          <h2 className="font-semibold text-foreground flex items-center gap-2">
            <Trash2 className="w-4 h-4 text-destructive" /> Supprimer mon compte
          </h2>
          <p className="text-[12.5px] leading-snug text-muted-foreground">
            Vous pouvez demander la suppression de votre compte. Les données nécessaires à la
            sécurité, aux paiements et aux obligations légales peuvent être conservées.
          </p>
          <Button
            variant="destructive"
            className="w-full"
            onClick={() => setDeleteOpen(true)}
          >
            <Trash2 className="w-4 h-4 mr-2" />
            Supprimer mon compte
          </Button>
        </div>
      </div>

      <SelfDeleteAccountSheet open={deleteOpen} onOpenChange={setDeleteOpen} />
    </div>
  );
}