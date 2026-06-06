import { Link } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
import { Seo } from "@/components/Seo";
import { BrandLogo } from "@/components/brand/BrandLogo";
import { PRIVACY_VERSION, LEGAL_LAST_UPDATED } from "@/lib/legal";

export default function Privacy() {
  return (
    <div className="min-h-screen bg-background pb-16">
      <Seo
        title="Politique de confidentialité — CHOPCHOP"
        description="Comment CHOPCHOP collecte, utilise et protège vos données : compte, localisation, paiements, support, données urbaines agrégées."
        canonical="/privacy"
      />
      <header className="gradient-primary text-primary-foreground rounded-b-3xl px-4 pt-6 pb-8">
        <div className="flex items-center gap-3">
          <Link to="/" className="p-2 -ml-2 rounded-full hover:bg-white/10" aria-label="Retour">
            <ArrowLeft className="w-5 h-5" />
          </Link>
          <BrandLogo size="md" loading="lazy" />
          <h1 className="text-lg font-bold">Confidentialité</h1>
        </div>
      </header>

      <main className="px-4 -mt-4 max-w-2xl mx-auto">
        <article className="bg-card rounded-2xl shadow-card p-5 text-sm leading-relaxed text-foreground/90 space-y-5">
          <div className="text-xs text-muted-foreground">
            Version : <span className="font-semibold text-foreground">{PRIVACY_VERSION}</span> ·
            Dernière mise à jour : {LEGAL_LAST_UPDATED}
          </div>

          <div className="rounded-xl bg-amber-500/10 border border-amber-500/30 px-3 py-2 text-xs text-foreground/80">
            Cette politique est une version de lancement et doit être revue
            par un conseil juridique avant le lancement public à grande
            échelle.
          </div>

          <section>
            <h2 className="font-semibold text-foreground">Données que nous collectons</h2>
            <ul className="list-disc pl-5 space-y-1 mt-1">
              <li>Compte : nom, email, mot de passe (haché), téléphone.</li>
              <li>Profil : photo, préférences.</li>
              <li>Localisation : position GPS, point de départ, destination.</li>
              <li>
                Trajets opérationnels : lorsqu'un chauffeur est en mission
                active, l'itinéraire réellement parcouru peut être enregistré
                afin de compléter la course, d'améliorer les ETA et la fiabilité
                du routage local. CHOPCHOP ne suit pas les utilisateurs en
                dehors des périodes d'utilisation active du service.
              </li>
              <li>
                Analyses d'itinéraires : les trajets terminés sont agrégés par
                district, créneau horaire et type de jour afin d'améliorer les
                temps estimés et la fiabilité du service. Ces analyses ne sont
                jamais affichées publiquement comme l'historique personnel d'un
                chauffeur.
              </li>
              <li>Courses, livraisons et commandes Repas / Marché.</li>
              <li>Portefeuille et historique de paiements.</li>
              <li>Demandes de support et pièces jointes éventuelles.</li>
              <li>Données de candidature chauffeur / commerçant.</li>
              <li>Données techniques de l'appareil et du navigateur.</li>
              <li>Événements analytiques agrégés.</li>
            </ul>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">Comment nous utilisons vos données</h2>
            <ul className="list-disc pl-5 space-y-1 mt-1">
              <li>Fournir le service (courses, repas, marché, paiements).</li>
              <li>Prévenir la fraude et assurer la sécurité.</li>
              <li>Améliorer la qualité du service et du support.</li>
              <li>Réconcilier les paiements.</li>
              <li>
                Comprendre la demande agrégée par quartier et améliorer la
                fiabilité opérationnelle à Conakry.
              </li>
            </ul>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">Notifications</h2>
            <p>
              Utilisées pour les mises à jour de courses, commandes,
              paiements et support. Vous pouvez gérer les notifications
              depuis votre appareil et l'application.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">Caméra et QR</h2>
            <p>
              La caméra n'est utilisée que pour scanner des QR codes
              CHOPCHOP et confirmer certaines actions.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">Données urbaines agrégées</h2>
            <p>
              CHOPCHOP peut utiliser des données opérationnelles agrégées et
              anonymisées pour comprendre les zones de forte demande,
              améliorer les livraisons, identifier les problèmes d'adressage
              et rendre les services plus fiables à Conakry. Aucun
              historique individuel de déplacement n'est exposé publiquement
              ni vendu.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">Partage de données</h2>
            <p>
              Vos données ne sont partagées qu'avec :
            </p>
            <ul className="list-disc pl-5 space-y-1 mt-1">
              <li>
                les chauffeurs, coursiers et commerçants impliqués dans
                votre course/commande (uniquement ce qui est nécessaire à
                l'exécution) ;
              </li>
              <li>
                des prestataires techniques : hébergement, authentification,
                email, cartes, paiements.
              </li>
            </ul>
            <p className="mt-2">
              CHOPCHOP n'utilise pas le suivi publicitaire inter-apps,
              n'intègre pas de réseaux publicitaires tiers au lancement, et
              ne vend pas vos données personnelles.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">Vos droits</h2>
            <p>
              Vous pouvez nous contacter pour accéder, corriger ou supprimer
              vos données dans la mesure prévue par la loi applicable.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">Contact</h2>
            <p>
              <a href="mailto:support@chopchopguinee.com" className="text-primary underline">
                support@chopchopguinee.com
              </a>
            </p>
          </section>

          <div className="pt-3 text-xs text-muted-foreground border-t border-border">
            Voir aussi les{" "}
            <Link to="/terms" className="text-primary underline">
              Conditions d'utilisation
            </Link>
            .
          </div>
        </article>
      </main>
    </div>
  );
}