import { Link } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
import { Seo } from "@/components/Seo";
import { BrandLogo } from "@/components/brand/BrandLogo";
import { TERMS_VERSION, LEGAL_LAST_UPDATED } from "@/lib/legal";

export default function Terms() {
  return (
    <div className="min-h-screen bg-background pb-16">
      <Seo
        title="Conditions d'utilisation — CHOPCHOP"
        description="Conditions d'utilisation de l'application CHOPCHOP, opérée par CHOP GUINEE LTD."
        canonical="/terms"
      />
      <header className="gradient-primary text-primary-foreground rounded-b-3xl px-4 pt-6 pb-8">
        <div className="flex items-center gap-3">
          <Link to="/" className="p-2 -ml-2 rounded-full hover:bg-white/10" aria-label="Retour">
            <ArrowLeft className="w-5 h-5" />
          </Link>
          <BrandLogo size="md" loading="lazy" />
          <h1 className="text-lg font-bold">Conditions d'utilisation</h1>
        </div>
      </header>

      <main className="px-4 -mt-4 max-w-2xl mx-auto">
        <article className="bg-card rounded-2xl shadow-card p-5 text-sm leading-relaxed text-foreground/90 space-y-5">
          <div className="text-xs text-muted-foreground">
            Version : <span className="font-semibold text-foreground">{TERMS_VERSION}</span> ·
            Dernière mise à jour : {LEGAL_LAST_UPDATED}
          </div>

          <div className="rounded-xl bg-amber-500/10 border border-amber-500/30 px-3 py-2 text-xs text-foreground/80">
            Ces conditions sont une version de lancement et doivent être
            revues par un conseil juridique avant le lancement public à
            grande échelle. <em>(Launch draft — to be reviewed by counsel
            before broad public launch.)</em>
          </div>

          <section>
            <h2 className="font-semibold text-foreground">1. Introduction</h2>
            <p>
              CHOPCHOP est une plateforme technologique opérée par CHOP GUINEE
              LTD (ou l'entité opérationnelle compétente). CHOPCHOP met en
              relation des utilisateurs, chauffeurs, coursiers, commerçants,
              restaurants et prestataires de services.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">2. Éligibilité</h2>
            <p>
              Les utilisateurs doivent fournir des informations exactes et
              sont responsables de leur compte. Les mineurs doivent obtenir
              l'autorisation d'un tuteur lorsque la loi l'exige.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">3. Création de compte</h2>
            <p>
              Inscription par email et mot de passe. Le numéro de téléphone
              est collecté à des fins opérationnelles et de support.
              L'utilisateur est responsable de la sécurité de son compte.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">4. Rôle de la plateforme</h2>
            <p>
              CHOPCHOP agit comme intermédiaire. Les chauffeurs, coursiers,
              commerçants et restaurants sont indépendants et responsables de
              leur propre conduite, de leurs produits et de leurs services.
              CHOPCHOP peut faciliter les transactions, communications,
              support et coordination opérationnelle.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">5. Services</h2>
            <p>
              Courses, livraisons, repas, marché, portefeuille/paiements,
              scanner, support. Les services peuvent varier selon le
              quartier, la phase pilote et la capacité opérationnelle.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">6. Paiements</h2>
            <p>
              Les prix peuvent inclure des frais de service, de livraison, des
              commissions ou des charges opérationnelles. Pendant la phase
              pilote, les paiements peuvent être en espèces, via portefeuille
              ou confirmés par l'administration. Les intégrations Mobile
              Money peuvent être indisponibles ou limitées jusqu'à
              l'activation du prestataire. CHOPCHOP peut retenir, examiner,
              annuler, rembourser ou réconcilier les paiements selon ses
              règles opérationnelles. Aucun utilisateur ne doit se fier à
              une confirmation de paiement non autorisée.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">7. ChopWallet</h2>
            <p>
              ChopWallet est un système de portefeuille/registre opérationnel
              dans l'application, et n'est pas un compte bancaire (sauf
              licence légale ultérieure). Les soldes et transactions sont
              sujets à vérification, réconciliation et correction. Toute
              fraude, abus, contestation ou erreur technique peut entraîner
              suspension ou révision.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">8. Courses et livraisons</h2>
            <p>
              Les utilisateurs doivent fournir des informations exactes de
              prise en charge et de destination. Les chauffeurs/coursiers
              doivent respecter les règles de sécurité et de service.
              CHOPCHOP peut annuler, réassigner ou refuser des missions
              pour des raisons de sécurité, de fraude, d'échec opérationnel
              ou de violation des règles.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">9. Repas et Marché</h2>
            <p>
              Les commerçants sont responsables de leurs produits,
              descriptions, prix, disponibilité, qualité, légalité et
              exécution. CHOPCHOP peut retirer des annonces ou des
              commerçants. Les litiges sont traités par le support.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">10. Chauffeurs / coursiers</h2>
            <p>
              Les comptes chauffeurs/coursiers sont soumis à approbation.
              CHOPCHOP peut suspendre, limiter ou révoquer l'accès. Les
              chauffeurs/coursiers sont des opérateurs indépendants sauf
              contrat écrit séparé. Aucune auto-approbation ni élévation
              de privilèges n'est autorisée.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">11. Usage acceptable</h2>
            <p>L'utilisateur s'interdit notamment de :</p>
            <ul className="list-disc pl-5 space-y-1 mt-1">
              <li>commettre une fraude,</li>
              <li>abuser du support,</li>
              <li>harceler d'autres utilisateurs, chauffeurs ou commerçants,</li>
              <li>contourner les systèmes de paiement,</li>
              <li>manipuler la localisation / GPS,</li>
              <li>créer de faux comptes,</li>
              <li>envoyer du spam,</li>
              <li>publier des contenus illégaux,</li>
              <li>récupérer ou rétro-ingénier l'application.</li>
            </ul>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">12. Sécurité</h2>
            <p>
              Les utilisateurs et chauffeurs doivent agir en sécurité.
              CHOPCHOP peut restreindre des comptes pour des raisons de
              sécurité. Les urgences doivent être signalées aux autorités
              locales compétentes.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">13. Localisation et autorisations</h2>
            <p>
              La localisation est utilisée pour la prestation des services,
              les cartes, l'itinéraire, la prévention de la fraude, le
              support et l'amélioration agrégée. La caméra est utilisée
              pour le scan de QR codes. Les notifications servent aux mises
              à jour opérationnelles. Les autorisations peuvent être gérées
              dans les réglages de l'appareil et de l'application.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">14. Données urbaines agrégées</h2>
            <p>
              CHOPCHOP peut utiliser des données opérationnelles agrégées et
              anonymisées pour améliorer les services, la qualité des cartes,
              la planification de la demande, la fiabilité par quartier et
              de futures analyses urbaines. CHOPCHOP n'expose pas
              publiquement les historiques individuels de déplacement.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">15. Confidentialité</h2>
            <p>
              Le traitement des données est régi par la{" "}
              <Link to="/privacy" className="text-primary underline">
                Politique de confidentialité
              </Link>
              .
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">16. Suspension / résiliation</h2>
            <p>
              CHOPCHOP peut suspendre un compte en cas de fraude, abus,
              risque de sécurité, non-paiement, violation des règles ou
              risque opérationnel.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">17. Avertissements</h2>
            <p>
              Services fournis « tels que disponibles ». Aucune garantie sur
              la disponibilité des chauffeurs, des commerçants, le temps de
              livraison, l'exactitude des itinéraires, la continuité ou
              l'absence d'erreurs. Les services pilotes peuvent être limités.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">18. Limitation de responsabilité</h2>
            <p>
              La responsabilité de CHOPCHOP est limitée dans toute la mesure
              permise par la loi. Aucun dommage indirect ou consécutif. Les
              litiges de transaction sont traités via le processus de
              support.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">19. Indemnisation</h2>
            <p>
              L'utilisateur s'engage à indemniser CHOPCHOP en cas d'usage
              abusif, de fraude, d'activité illégale ou de violation des
              présentes conditions.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">20. Modifications</h2>
            <p>
              CHOPCHOP peut mettre à jour les présentes conditions. La
              poursuite de l'utilisation vaut acceptation.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">21. Loi applicable / résolution des litiges</h2>
            <p>
              Juridiction de la République de Guinée / CHOP GUINEE LTD
              <em> (à confirmer par revue juridique)</em>.
            </p>
          </section>

          <section>
            <h2 className="font-semibold text-foreground">22. Contact</h2>
            <p>
              <a href="mailto:support@chopchopguinee.com" className="text-primary underline">
                support@chopchopguinee.com
              </a>
            </p>
          </section>

          <div className="pt-3 text-xs text-muted-foreground border-t border-border">
            Voir aussi la{" "}
            <Link to="/privacy" className="text-primary underline">
              Politique de confidentialité
            </Link>
            .
          </div>
        </article>
      </main>
    </div>
  );
}