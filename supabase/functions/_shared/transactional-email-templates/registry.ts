/// <reference types="npm:@types/react@18.3.1" />
import * as React from 'npm:react@18.3.1'

export interface TemplateEntry {
  component: React.ComponentType<any>
  subject: string | ((data: Record<string, any>) => string)
  to?: string
  displayName?: string
  previewData?: Record<string, any>
}

import { template as welcome } from './welcome.tsx'
import { template as otpFallback } from './otp-fallback.tsx'
import { template as securityAlert } from './security-alert.tsx'
import { template as topupSuccess } from './topup-success.tsx'
import { template as paymentReceipt } from './payment-receipt.tsx'
import { template as refundProcessed } from './refund-processed.tsx'
import { template as rideReceipt } from './ride-receipt.tsx'
import { template as orderConfirmed } from './order-confirmed.tsx'
import { template as orderDelivered } from './order-delivered.tsx'
import { template as driverApproved } from './driver-approved.tsx'

export const TEMPLATES: Record<string, TemplateEntry> = {
  welcome,
  'otp-fallback': otpFallback,
  'security-alert': securityAlert,
  'topup-success': topupSuccess,
  'payment-receipt': paymentReceipt,
  'refund-processed': refundProcessed,
  'ride-receipt': rideReceipt,
  'order-confirmed': orderConfirmed,
  'order-delivered': orderDelivered,
  'driver-approved': driverApproved,
}