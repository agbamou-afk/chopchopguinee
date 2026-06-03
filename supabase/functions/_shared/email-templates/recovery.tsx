/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { CTAButton, EmailLayout, H1, P, SupportSection } from '../email-components.tsx'

interface Props {
  siteName?: string
  confirmationUrl: string
}

export const RecoveryEmail = ({ confirmationUrl }: Props) => (
  <EmailLayout preview="Un lien sécurisé pour récupérer l'accès à votre compte CHOPCHOP.">
    <H1>Réinitialisation du mot de passe</H1>
    <P>
      Nous avons reçu une demande de réinitialisation pour votre compte
      CHOPCHOP. Cliquez sur le bouton ci-dessous pour choisir un nouveau mot
      de passe.
    </P>
    <CTAButton href={confirmationUrl}>Réinitialiser mon mot de passe</CTAButton>
    <P muted>
      Ce lien est valable 1 heure. Si vous n'êtes pas à l'origine de cette
      demande, ignorez cet e-mail — votre mot de passe restera inchangé.
    </P>
    <SupportSection />
  </EmailLayout>
)

export default RecoveryEmail
