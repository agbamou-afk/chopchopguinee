/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { CTAButton, EmailLayout, H1, P, SupportSection } from '../email-components.tsx'

interface Props {
  siteName: string
  siteUrl: string
  confirmationUrl: string
}

export const SignupEmail = ({ confirmationUrl }: Props) => (
  <EmailLayout preview="Confirmez votre compte CHOP CHOP">
    <H1>Bienvenue sur CHOP CHOP 🇬🇳</H1>
    <P>
      Merci d'avoir créé votre compte. Confirmez votre adresse e-mail pour activer
      votre profil et accéder à la mobilité, au paiement et au commerce dans toute
      la Guinée.
    </P>
    <CTAButton href={confirmationUrl}>Confirmer mon compte</CTAButton>
    <P muted>
      Ce lien est valable 24 heures. Si vous n'êtes pas à l'origine de cette
      inscription, ignorez cet e-mail.
    </P>
    <SupportSection />
  </EmailLayout>
)

export default SignupEmail