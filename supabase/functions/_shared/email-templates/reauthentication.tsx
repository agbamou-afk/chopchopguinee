/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'
import { Text } from 'npm:@react-email/components@0.0.22'
import { EmailLayout, H1, P, SupportSection } from '../email-components.tsx'
import { COLORS, FONT_STACK } from '../email-brand.ts'

interface Props { token: string }

export const ReauthenticationEmail = ({ token }: Props) => (
  <EmailLayout preview="Une vérification rapide pour protéger votre compte CHOPCHOP.">
    <H1>Vérification de sécurité</H1>
    <P>
      Pour continuer, utilisez le code ci-dessous afin de confirmer votre
      identité.
    </P>
    <Text style={codeStyle}>{token}</Text>
    <P muted>
      Ce code expire dans quelques minutes. Si vous n'êtes pas à l'origine de
      cette demande, ignorez cet e-mail ou contactez le support.
    </P>
    <SupportSection />
  </EmailLayout>
)

export default ReauthenticationEmail

const codeStyle = {
  fontFamily: FONT_STACK,
  fontSize: '28px',
  fontWeight: 700 as const,
  letterSpacing: '0.4em',
  color: COLORS.green,
  textAlign: 'center' as const,
  margin: '8px 0 18px',
}
