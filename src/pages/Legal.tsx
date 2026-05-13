import { useNavigate } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
import logo from "@/assets/logo.png";
import { Seo } from "@/components/Seo";

export default function Legal() {
  const navigate = useNavigate();
  return (
    <div className="min-h-screen bg-background pb-12">
      <Seo
        title="Mentions légales & CGU — CHOP CHOP"
        description="Conditions générales d'utilisation de CHOP GUINEE LTD : nature du service, responsabilités, données personnelles et droit applicable en Guinée."
        canonical="/legal"
      />
      <header className="gradient-primary text-primary-foreground rounded-b-3xl px-4 pt-6 pb-8">
        <div className="flex items-center gap-3">
          <button onClick={() => navigate(-1)} className="p-2 -ml-2 rounded-full hover:bg-white/10">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <img src={logo} alt="CHOP CHOP" className="h-10 w-auto" />
          <h1 className="text-lg font-bold">Mentions légales</h1>
        </div>
      </header>

      <article className="px-5 -mt-4 max-w-md mx-auto bg-card rounded-2xl shadow-card p-6 space-y-4 text-sm text-foreground leading-relaxed">
        <h2 className="text-base font-bold">Conditions Générales d'Utilisation — CHOP GUINEE LTD</h2>
        <p className="text-xs text-muted-foreground">
          Dernière mise à jour : 12 mai 2026. Éditeur : <strong>CHOP GUINEE LTD</strong>
          {" "}(« CHOP CHOP », « la Société », « nous »). Marque commerciale : « CHOP CHOP ».
        </p>

        <section className="space-y-2">
          <h3 className="font-semibold">1. Acceptation des conditions</h3>
          <p>
            En créant un compte, en accédant à l'application CHOP CHOP ou en utilisant l'un quelconque de ses services
            (transport, livraison de repas, place de marché, portefeuille électronique, transferts d'argent, services
            d'agent, et toute fonctionnalité future), l'Utilisateur reconnaît avoir lu, compris et accepté sans
            réserve l'intégralité des présentes Conditions Générales d'Utilisation. Tout usage de l'application vaut
            acceptation pleine et entière de ces conditions.
          </p>
        </section>

        <section className="space-y-2">
          <h3 className="font-semibold">2. Nature du service — simple intermédiaire technique</h3>
          <p>
            CHOP GUINEE LTD agit exclusivement en tant qu'<strong>intermédiaire technologique</strong> mettant en
            relation des utilisateurs, des chauffeurs indépendants, des marchands, des restaurants, des livreurs et
            des agents. CHOP GUINEE LTD <strong>n'est pas</strong> transporteur, restaurateur, vendeur, livreur,
            établissement de crédit, ni prestataire de services de paiement au sens réglementaire. Les prestations
            sont fournies par des tiers indépendants et CHOP GUINEE LTD n'est partie à aucun contrat de transport,
            de vente ou de livraison conclu via l'application.
          </p>
        </section>

        <section className="space-y-2">
          <h3 className="font-semibold">3. Exclusion totale de responsabilité</h3>
          <p>
            DANS TOUTE LA MESURE PERMISE PAR LA LOI APPLICABLE, CHOP GUINEE LTD, SES DIRIGEANTS, ACTIONNAIRES,
            EMPLOYÉS, AGENTS, FILIALES, PARTENAIRES, FOURNISSEURS ET SOUS-TRAITANTS SONT INTÉGRALEMENT DÉGAGÉS DE
            TOUTE RESPONSABILITÉ, DE QUELQUE NATURE QUE CE SOIT (CONTRACTUELLE, DÉLICTUELLE, QUASI-DÉLICTUELLE OU
            AUTRE), POUR TOUT DOMMAGE DIRECT, INDIRECT, ACCESSOIRE, SPÉCIAL, CONSÉCUTIF, PUNITIF OU EXEMPLAIRE,
            INCLUANT NOTAMMENT, SANS LIMITATION :
          </p>
          <ul className="list-disc pl-5 space-y-1">
            <li>tout accident, blessure, décès, vol, perte ou dommage corporel ou matériel survenu pendant une course, une livraison ou toute interaction avec un chauffeur, livreur, marchand, restaurant ou agent ;</li>
            <li>la qualité, la sécurité, la légalité, la disponibilité, la fraîcheur ou la conformité des biens, repas, courses ou services proposés par des tiers ;</li>
            <li>tout retard, annulation, indisponibilité, interruption ou dysfonctionnement de l'application, du réseau, des services bancaires, mobiles ou de paiement ;</li>
            <li>toute perte financière, perte de fonds, fraude, détournement, erreur de saisie, transfert vers le mauvais destinataire, recharge erronée ou litige entre utilisateurs et agents ;</li>
            <li>tout vol, piratage, accès non autorisé, perte ou corruption de données, mots de passe ou identifiants ;</li>
            <li>tout comportement (légal ou illégal) d'un autre utilisateur, chauffeur, livreur, marchand ou agent ;</li>
            <li>toute conséquence d'un cas de force majeure (panne réseau, coupure d'électricité, intempérie, conflit, décision administrative, etc.).</li>
          </ul>
          <p>
            L'Utilisateur reconnaît expressément utiliser l'application <strong>à ses seuls risques et périls</strong>.
            La responsabilité maximale cumulée de CHOP GUINEE LTD, si elle devait être engagée malgré les présentes,
            est strictement limitée au montant de la dernière transaction litigieuse, plafonnée à
            <strong> 100 000 GNF</strong>.
          </p>
        </section>

        <section className="space-y-2">
          <h3 className="font-semibold">4. Garantie d'indemnisation</h3>
          <p>
            L'Utilisateur s'engage à <strong>indemniser, défendre et tenir indemnes</strong> CHOP GUINEE LTD et ses
            affiliés de toute réclamation, plainte, action, demande, perte, dommage, coût ou frais (y compris les
            honoraires d'avocats raisonnables) résultant de ou liés à : (i) son utilisation de l'application,
            (ii) toute violation des présentes conditions, (iii) toute violation d'un droit de tiers, ou
            (iv) tout contenu qu'il publie ou transmet via l'application.
          </p>
        </section>

        <section className="space-y-2">
          <h3 className="font-semibold">5. Portefeuille et transactions</h3>
          <p>
            Les soldes en GNF affichés représentent une créance de l'Utilisateur exclusivement utilisable au sein
            de l'écosystème CHOP CHOP. Les recharges effectuées via un agent sont définitives une fois confirmées
            par le code à 6 chiffres ; aucun remboursement ne peut être exigé pour une recharge confirmée. Les
            transferts entre utilisateurs sont irrévocables une fois validés.
          </p>
        </section>

        <section className="space-y-2">
          <h3 className="font-semibold">6. Comportement de l'utilisateur</h3>
          <p>
            L'Utilisateur s'engage à fournir des informations exactes, à ne pas utiliser l'application à des fins
            frauduleuses, illégales ou contraires aux bonnes mœurs, et à respecter les chauffeurs, livreurs,
            marchands et agents. Tout manquement entraîne la suspension ou la suppression immédiate du compte,
            sans préavis ni remboursement.
          </p>
        </section>

        <section className="space-y-2">
          <h3 className="font-semibold">7. Données personnelles</h3>
          <p>
            CHOP GUINEE LTD collecte et traite les données nécessaires au fonctionnement du service (identité,
            téléphone, géolocalisation, transactions). Ces données peuvent être partagées avec des prestataires
            techniques, des autorités compétentes ou en cas de fusion/cession. L'Utilisateur dispose d'un droit
            d'accès, de rectification et de suppression via le formulaire de contact.
          </p>
        </section>

        <section className="space-y-2">
          <h3 className="font-semibold">8. Modification des conditions</h3>
          <p>
            CHOP GUINEE LTD se réserve le droit de modifier à tout moment et sans préavis les présentes conditions.
            Les modifications entrent en vigueur dès leur publication dans l'application. La poursuite de
            l'utilisation vaut acceptation des nouvelles conditions.
          </p>
        </section>

        <section className="space-y-2">
          <h3 className="font-semibold">9. Droit applicable et juridiction</h3>
          <p>
            Les présentes conditions sont régies par le droit de la République de Guinée. Tout litige relatif à
            leur interprétation ou leur exécution sera soumis à la compétence exclusive des tribunaux de Conakry,
            après tentative préalable de règlement amiable.
          </p>
        </section>

        <section className="space-y-2">
          <h3 className="font-semibold">10. Divisibilité</h3>
          <p>
            Si l'une quelconque des dispositions des présentes était jugée nulle ou inapplicable, les autres
            dispositions resteraient pleinement en vigueur.
          </p>
        </section>

        <p className="pt-4 text-xs text-muted-foreground border-t border-border">
          © 2026 CHOP GUINEE LTD. Tous droits réservés. Pour toute question, contactez-nous via la rubrique Aide.
        </p>
      </article>
    </div>
  );
}