/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { CTAButton, EmailLayout, H1, P, SupportSection } from '../email-components.tsx'

interface Props {
  siteName?: string
  oldEmail?: string
  email?: string
  newEmail?: string
  confirmationUrl: string
}

export const EmailChangeEmail = ({ oldEmail, newEmail, confirmationUrl }: Props) => (
  <EmailLayout preview="Vérifiez votre nouvelle adresse email pour continuer.">
    <H1>Confirmation de nouvelle adresse email</H1>
    <P>
      Vous avez demandé à changer l'adresse email associée à votre compte
      CHOPCHOP{oldEmail ? ` depuis ${oldEmail}` : ''}
      {newEmail ? ` vers ${newEmail}` : ''}. Confirmez cette nouvelle adresse
      pour finaliser le changement.
    </P>
    <CTAButton href={confirmationUrl}>Confirmer mon email</CTAButton>
    <P muted>
      Si vous n'êtes pas à l'origine de ce changement, ignorez cet e-mail et
      contactez immédiatement notre support pour sécuriser votre compte.
    </P>
    <SupportSection />
  </EmailLayout>
)

export default EmailChangeEmail
