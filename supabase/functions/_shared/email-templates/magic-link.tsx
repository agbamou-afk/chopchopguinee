/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { CTAButton, EmailLayout, H1, P, SupportSection } from '../email-components.tsx'

interface Props {
  siteName?: string
  confirmationUrl: string
}

export const MagicLinkEmail = ({ confirmationUrl }: Props) => (
  <EmailLayout preview="Connectez-vous à votre compte CHOPCHOP en toute sécurité.">
    <H1>Connexion à CHOPCHOP</H1>
    <P>
      Cliquez sur le bouton ci-dessous pour vous connecter à votre compte. Ce
      lien est personnel et temporaire.
    </P>
    <CTAButton href={confirmationUrl}>Me connecter</CTAButton>
    <P muted>
      Si vous n'êtes pas à l'origine de cette demande, ignorez cet e-mail.
    </P>
    <SupportSection />
  </EmailLayout>
)

export default MagicLinkEmail
