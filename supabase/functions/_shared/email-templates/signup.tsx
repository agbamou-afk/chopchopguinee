/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { CTAButton, EmailLayout, H1, P, SupportSection } from '../email-components.tsx'

interface Props {
  siteName: string
  siteUrl: string
  confirmationUrl: string
}

export const SignupEmail = ({ confirmationUrl }: Props) => (
  <EmailLayout preview="Confirmez votre compte CHOPCHOP">
    <H1>Bienvenue sur CHOPCHOP 🇬🇳</H1>
    <P>
      Confirmez votre email pour continuer et activer votre compte CHOPCHOP.
    </P>
    <CTAButton href={confirmationUrl}>Confirmer mon compte</CTAButton>
    <P muted>
      Ce lien est valable 24 heures. Si vous n'êtes pas à l'origine de cette
      inscription, ignorez cet e-mail.
    </P>
    <P muted>Tout, partout, pour tous.</P>
    <SupportSection />
  </EmailLayout>
)

export default SignupEmail