import type { Database } from "@/integrations/supabase/types";

type RideStatus = Database["public"]["Enums"]["ride_status"];

/**
 * Client-active ride statuses from the live rides.status enum.
 *
 * Important: `accepted` / `assigned` are not valid ride_status enum values in
 * this backend; assignment is represented by `status = 'pending'` plus
 * `driver_id` / `metadata.phase`.
 */
export const ACTIVE_CLIENT_RIDE_STATUSES = [
  "pending",
  "in_progress",
] as const satisfies readonly RideStatus[];

export type ActiveClientRideStatus = (typeof ACTIVE_CLIENT_RIDE_STATUSES)[number];

const ACTIVE_CLIENT_RIDE_STATUS_SET = new Set<string>(ACTIVE_CLIENT_RIDE_STATUSES);

export function isActiveClientRideStatus(status: string | null | undefined): status is ActiveClientRideStatus {
  return !!status && ACTIVE_CLIENT_RIDE_STATUS_SET.has(status);
}