export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      account_bans: {
        Row: {
          banned_at: string
          banned_by: string
          created_at: string
          email: string | null
          email_lc: string | null
          expires_at: string | null
          id: string
          lift_reason: string | null
          lifted_at: string | null
          lifted_by: string | null
          metadata: Json
          phone_e164: string | null
          reason: string
          status: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          banned_at?: string
          banned_by: string
          created_at?: string
          email?: string | null
          email_lc?: string | null
          expires_at?: string | null
          id?: string
          lift_reason?: string | null
          lifted_at?: string | null
          lifted_by?: string | null
          metadata?: Json
          phone_e164?: string | null
          reason: string
          status?: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          banned_at?: string
          banned_by?: string
          created_at?: string
          email?: string | null
          email_lc?: string | null
          expires_at?: string | null
          id?: string
          lift_reason?: string | null
          lifted_at?: string | null
          lifted_by?: string | null
          metadata?: Json
          phone_e164?: string | null
          reason?: string
          status?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: []
      }
      account_deletion_requests: {
        Row: {
          created_at: string
          id: string
          metadata: Json
          processed_at: string | null
          processed_by: string | null
          reason: string | null
          request_type: string
          requested_by: string | null
          status: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          metadata?: Json
          processed_at?: string | null
          processed_by?: string | null
          reason?: string | null
          request_type: string
          requested_by?: string | null
          status?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          metadata?: Json
          processed_at?: string | null
          processed_by?: string | null
          reason?: string | null
          request_type?: string
          requested_by?: string | null
          status?: string
          user_id?: string
        }
        Relationships: []
      }
      account_freezes: {
        Row: {
          created_at: string
          expires_at: string | null
          freeze_type: string
          frozen_at: string
          frozen_by: string
          id: string
          lift_reason: string | null
          lifted_at: string | null
          lifted_by: string | null
          metadata: Json
          reason: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          expires_at?: string | null
          freeze_type?: string
          frozen_at?: string
          frozen_by: string
          id?: string
          lift_reason?: string | null
          lifted_at?: string | null
          lifted_by?: string | null
          metadata?: Json
          reason: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          expires_at?: string | null
          freeze_type?: string
          frozen_at?: string
          frozen_by?: string
          id?: string
          lift_reason?: string | null
          lifted_at?: string | null
          lifted_by?: string | null
          metadata?: Json
          reason?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      admin_users: {
        Row: {
          admin_role: Database["public"]["Enums"]["admin_role"]
          created_at: string
          created_by: string | null
          id: string
          notes: string | null
          status: Database["public"]["Enums"]["admin_user_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          admin_role: Database["public"]["Enums"]["admin_role"]
          created_at?: string
          created_by?: string | null
          id?: string
          notes?: string | null
          status?: Database["public"]["Enums"]["admin_user_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          admin_role?: Database["public"]["Enums"]["admin_role"]
          created_at?: string
          created_by?: string | null
          id?: string
          notes?: string | null
          status?: Database["public"]["Enums"]["admin_user_status"]
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      agent_profiles: {
        Row: {
          business_name: string
          commission_rate: number
          created_at: string
          daily_limit_gnf: number
          id: string
          latitude: number | null
          location: string | null
          longitude: number | null
          prepaid_float_gnf: number
          status: Database["public"]["Enums"]["wallet_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          business_name: string
          commission_rate?: number
          created_at?: string
          daily_limit_gnf?: number
          id?: string
          latitude?: number | null
          location?: string | null
          longitude?: number | null
          prepaid_float_gnf?: number
          status?: Database["public"]["Enums"]["wallet_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          business_name?: string
          commission_rate?: number
          created_at?: string
          daily_limit_gnf?: number
          id?: string
          latitude?: number | null
          location?: string | null
          longitude?: number | null
          prepaid_float_gnf?: number
          status?: Database["public"]["Enums"]["wallet_status"]
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      ai_insights: {
        Row: {
          confidence: Database["public"]["Enums"]["insight_confidence"]
          created_at: string
          generated_by_user_id: string | null
          generated_for_date: string
          id: string
          metrics: Json
          recommendation: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          section: Database["public"]["Enums"]["insight_section"]
          status: string
          summary: string
          title: string
        }
        Insert: {
          confidence?: Database["public"]["Enums"]["insight_confidence"]
          created_at?: string
          generated_by_user_id?: string | null
          generated_for_date?: string
          id?: string
          metrics?: Json
          recommendation?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          section: Database["public"]["Enums"]["insight_section"]
          status?: string
          summary: string
          title: string
        }
        Update: {
          confidence?: Database["public"]["Enums"]["insight_confidence"]
          created_at?: string
          generated_by_user_id?: string | null
          generated_for_date?: string
          id?: string
          metrics?: Json
          recommendation?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          section?: Database["public"]["Enums"]["insight_section"]
          status?: string
          summary?: string
          title?: string
        }
        Relationships: []
      }
      ai_rate_limits: {
        Row: {
          count: number
          user_id: string
          window_kind: string
          window_start: string
        }
        Insert: {
          count?: number
          user_id: string
          window_kind: string
          window_start: string
        }
        Update: {
          count?: number
          user_id?: string
          window_kind?: string
          window_start?: string
        }
        Relationships: []
      }
      ai_request_log: {
        Row: {
          action: string
          assistant: Database["public"]["Enums"]["ai_assistant_kind"]
          created_at: string
          error_message: string | null
          id: string
          input: Json
          latency_ms: number | null
          model: string
          output: Json | null
          prompt_summary: string | null
          provider: string
          status: Database["public"]["Enums"]["ai_request_status"]
          tokens_input: number | null
          tokens_output: number | null
          user_id: string | null
        }
        Insert: {
          action: string
          assistant: Database["public"]["Enums"]["ai_assistant_kind"]
          created_at?: string
          error_message?: string | null
          id?: string
          input?: Json
          latency_ms?: number | null
          model: string
          output?: Json | null
          prompt_summary?: string | null
          provider: string
          status?: Database["public"]["Enums"]["ai_request_status"]
          tokens_input?: number | null
          tokens_output?: number | null
          user_id?: string | null
        }
        Update: {
          action?: string
          assistant?: Database["public"]["Enums"]["ai_assistant_kind"]
          created_at?: string
          error_message?: string | null
          id?: string
          input?: Json
          latency_ms?: number | null
          model?: string
          output?: Json | null
          prompt_summary?: string | null
          provider?: string
          status?: Database["public"]["Enums"]["ai_request_status"]
          tokens_input?: number | null
          tokens_output?: number | null
          user_id?: string | null
        }
        Relationships: []
      }
      analytics_events: {
        Row: {
          anonymous_session_id: string | null
          app_version: string | null
          created_at: string
          device_type: string | null
          event_category: string
          event_name: string
          event_type: string
          id: string
          language: string | null
          metadata: Json
          os: string | null
          route: string | null
          service_area: string | null
          user_id: string | null
          zone_city: string | null
          zone_commune: string | null
          zone_country: string | null
          zone_neighborhood: string | null
        }
        Insert: {
          anonymous_session_id?: string | null
          app_version?: string | null
          created_at?: string
          device_type?: string | null
          event_category: string
          event_name: string
          event_type: string
          id?: string
          language?: string | null
          metadata?: Json
          os?: string | null
          route?: string | null
          service_area?: string | null
          user_id?: string | null
          zone_city?: string | null
          zone_commune?: string | null
          zone_country?: string | null
          zone_neighborhood?: string | null
        }
        Update: {
          anonymous_session_id?: string | null
          app_version?: string | null
          created_at?: string
          device_type?: string | null
          event_category?: string
          event_name?: string
          event_type?: string
          id?: string
          language?: string | null
          metadata?: Json
          os?: string | null
          route?: string | null
          service_area?: string | null
          user_id?: string | null
          zone_city?: string | null
          zone_commune?: string | null
          zone_country?: string | null
          zone_neighborhood?: string | null
        }
        Relationships: []
      }
      app_settings: {
        Row: {
          description: string | null
          key: string
          updated_at: string
          updated_by: string | null
          value: Json
        }
        Insert: {
          description?: string | null
          key: string
          updated_at?: string
          updated_by?: string | null
          value?: Json
        }
        Update: {
          description?: string | null
          key?: string
          updated_at?: string
          updated_by?: string | null
          value?: Json
        }
        Relationships: []
      }
      approval_requests: {
        Row: {
          action: string
          created_at: string
          id: string
          module: string
          payload: Json
          requested_by: string
          requested_role: Database["public"]["Enums"]["admin_role"] | null
          review_note: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: Database["public"]["Enums"]["approval_status"]
        }
        Insert: {
          action: string
          created_at?: string
          id?: string
          module: string
          payload?: Json
          requested_by: string
          requested_role?: Database["public"]["Enums"]["admin_role"] | null
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["approval_status"]
        }
        Update: {
          action?: string
          created_at?: string
          id?: string
          module?: string
          payload?: Json
          requested_by?: string
          requested_role?: Database["public"]["Enums"]["admin_role"] | null
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["approval_status"]
        }
        Relationships: []
      }
      audit_logs: {
        Row: {
          action: string
          actor_role: Database["public"]["Enums"]["admin_role"] | null
          actor_user_id: string | null
          after: Json | null
          before: Json | null
          created_at: string
          id: string
          ip: string | null
          module: string
          note: string | null
          target_id: string | null
          target_type: string | null
          user_agent: string | null
        }
        Insert: {
          action: string
          actor_role?: Database["public"]["Enums"]["admin_role"] | null
          actor_user_id?: string | null
          after?: Json | null
          before?: Json | null
          created_at?: string
          id?: string
          ip?: string | null
          module: string
          note?: string | null
          target_id?: string | null
          target_type?: string | null
          user_agent?: string | null
        }
        Update: {
          action?: string
          actor_role?: Database["public"]["Enums"]["admin_role"] | null
          actor_user_id?: string | null
          after?: Json | null
          before?: Json | null
          created_at?: string
          id?: string
          ip?: string | null
          module?: string
          note?: string | null
          target_id?: string | null
          target_type?: string | null
          user_agent?: string | null
        }
        Relationships: []
      }
      conversations: {
        Row: {
          buyer_id: string
          created_at: string
          id: string
          last_message_at: string
          listing_id: string
          seller_id: string
        }
        Insert: {
          buyer_id: string
          created_at?: string
          id?: string
          last_message_at?: string
          listing_id: string
          seller_id: string
        }
        Update: {
          buyer_id?: string
          created_at?: string
          id?: string
          last_message_at?: string
          listing_id?: string
          seller_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "conversations_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "marketplace_listings"
            referencedColumns: ["id"]
          },
        ]
      }
      district_hubs: {
        Row: {
          address: string | null
          available_services: string[]
          created_at: string
          district: string
          id: string
          lat: number | null
          lng: number | null
          merchant_id: string | null
          name: string
          partner_type: string
          phone: string | null
          status: string
          updated_at: string
        }
        Insert: {
          address?: string | null
          available_services?: string[]
          created_at?: string
          district: string
          id?: string
          lat?: number | null
          lng?: number | null
          merchant_id?: string | null
          name: string
          partner_type?: string
          phone?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          address?: string | null
          available_services?: string[]
          created_at?: string
          district?: string
          id?: string
          lat?: number | null
          lng?: number | null
          merchant_id?: string | null
          name?: string
          partner_type?: string
          phone?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      driver_applications: {
        Row: {
          created_at: string
          decided_at: string | null
          decided_by: string | null
          decision: Database["public"]["Enums"]["driver_application_decision"]
          decision_reason: string | null
          id: string
          payload: Json
          user_id: string
        }
        Insert: {
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision?: Database["public"]["Enums"]["driver_application_decision"]
          decision_reason?: string | null
          id?: string
          payload?: Json
          user_id: string
        }
        Update: {
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision?: Database["public"]["Enums"]["driver_application_decision"]
          decision_reason?: string | null
          id?: string
          payload?: Json
          user_id?: string
        }
        Relationships: []
      }
      driver_cash_ledger: {
        Row: {
          cash_collected_gnf: number
          commission_owed_gnf: number
          created_at: string
          driver_id: string
          id: string
          note: string | null
          ride_id: string | null
          settled_amount_gnf: number
          settled_at: string | null
        }
        Insert: {
          cash_collected_gnf?: number
          commission_owed_gnf?: number
          created_at?: string
          driver_id: string
          id?: string
          note?: string | null
          ride_id?: string | null
          settled_amount_gnf?: number
          settled_at?: string | null
        }
        Update: {
          cash_collected_gnf?: number
          commission_owed_gnf?: number
          created_at?: string
          driver_id?: string
          id?: string
          note?: string | null
          ride_id?: string | null
          settled_amount_gnf?: number
          settled_at?: string | null
        }
        Relationships: []
      }
      driver_group_commissions: {
        Row: {
          approved_at: string | null
          commission_amount_gnf: number
          commission_percent: number
          created_at: string
          driver_user_id: string
          gross_driver_earning_gnf: number
          group_id: string
          id: string
          leader_user_id: string | null
          notes: string | null
          paid_at: string | null
          risk_reason: string | null
          risk_status: string
          source_id: string | null
          source_type: string
          status: string
          updated_at: string
          wallet_transaction_id: string | null
        }
        Insert: {
          approved_at?: string | null
          commission_amount_gnf?: number
          commission_percent?: number
          created_at?: string
          driver_user_id: string
          gross_driver_earning_gnf?: number
          group_id: string
          id?: string
          leader_user_id?: string | null
          notes?: string | null
          paid_at?: string | null
          risk_reason?: string | null
          risk_status?: string
          source_id?: string | null
          source_type: string
          status?: string
          updated_at?: string
          wallet_transaction_id?: string | null
        }
        Update: {
          approved_at?: string | null
          commission_amount_gnf?: number
          commission_percent?: number
          created_at?: string
          driver_user_id?: string
          gross_driver_earning_gnf?: number
          group_id?: string
          id?: string
          leader_user_id?: string | null
          notes?: string | null
          paid_at?: string | null
          risk_reason?: string | null
          risk_status?: string
          source_id?: string | null
          source_type?: string
          status?: string
          updated_at?: string
          wallet_transaction_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "driver_group_commissions_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "driver_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      driver_group_contracts: {
        Row: {
          bonus_pool_gnf: number | null
          commission_percent_override: number | null
          created_at: string
          created_by: string | null
          group_id: string
          id: string
          leader_user_id: string | null
          name: string
          notes: string | null
          period_end: string | null
          period_start: string | null
          status: string
          target_active_driver_count: number
          target_completed_rides: number
          target_driver_count: number
          target_gross_earnings_gnf: number
          target_zone_ids: string[]
          terms: string | null
          updated_at: string
        }
        Insert: {
          bonus_pool_gnf?: number | null
          commission_percent_override?: number | null
          created_at?: string
          created_by?: string | null
          group_id: string
          id?: string
          leader_user_id?: string | null
          name: string
          notes?: string | null
          period_end?: string | null
          period_start?: string | null
          status?: string
          target_active_driver_count?: number
          target_completed_rides?: number
          target_driver_count?: number
          target_gross_earnings_gnf?: number
          target_zone_ids?: string[]
          terms?: string | null
          updated_at?: string
        }
        Update: {
          bonus_pool_gnf?: number | null
          commission_percent_override?: number | null
          created_at?: string
          created_by?: string | null
          group_id?: string
          id?: string
          leader_user_id?: string | null
          name?: string
          notes?: string | null
          period_end?: string | null
          period_start?: string | null
          status?: string
          target_active_driver_count?: number
          target_completed_rides?: number
          target_driver_count?: number
          target_gross_earnings_gnf?: number
          target_zone_ids?: string[]
          terms?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "driver_group_contracts_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "driver_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      driver_group_field_checkins: {
        Row: {
          accuracy_m: number | null
          checkin_type: string
          created_at: string
          created_by: string
          driver_user_id: string | null
          group_id: string
          id: string
          lat: number | null
          leader_user_id: string | null
          lng: number | null
          metadata: Json
          notes: string | null
          photo_url: string | null
          zone_id: string | null
        }
        Insert: {
          accuracy_m?: number | null
          checkin_type?: string
          created_at?: string
          created_by: string
          driver_user_id?: string | null
          group_id: string
          id?: string
          lat?: number | null
          leader_user_id?: string | null
          lng?: number | null
          metadata?: Json
          notes?: string | null
          photo_url?: string | null
          zone_id?: string | null
        }
        Update: {
          accuracy_m?: number | null
          checkin_type?: string
          created_at?: string
          created_by?: string
          driver_user_id?: string | null
          group_id?: string
          id?: string
          lat?: number | null
          leader_user_id?: string | null
          lng?: number | null
          metadata?: Json
          notes?: string | null
          photo_url?: string | null
          zone_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "driver_group_field_checkins_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "driver_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "driver_group_field_checkins_zone_id_fkey"
            columns: ["zone_id"]
            isOneToOne: false
            referencedRelation: "zones"
            referencedColumns: ["id"]
          },
        ]
      }
      driver_group_memberships: {
        Row: {
          added_by: string | null
          assigned_zone: string | null
          assigned_zone_id: string | null
          created_at: string
          driver_profile_id: string | null
          driver_user_id: string
          group_id: string
          id: string
          joined_at: string
          notes: string | null
          removed_at: string | null
          removed_by: string | null
          status: string
          updated_at: string
        }
        Insert: {
          added_by?: string | null
          assigned_zone?: string | null
          assigned_zone_id?: string | null
          created_at?: string
          driver_profile_id?: string | null
          driver_user_id: string
          group_id: string
          id?: string
          joined_at?: string
          notes?: string | null
          removed_at?: string | null
          removed_by?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          added_by?: string | null
          assigned_zone?: string | null
          assigned_zone_id?: string | null
          created_at?: string
          driver_profile_id?: string | null
          driver_user_id?: string
          group_id?: string
          id?: string
          joined_at?: string
          notes?: string | null
          removed_at?: string | null
          removed_by?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "driver_group_memberships_assigned_zone_id_fkey"
            columns: ["assigned_zone_id"]
            isOneToOne: false
            referencedRelation: "zones"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "driver_group_memberships_driver_profile_id_fkey"
            columns: ["driver_profile_id"]
            isOneToOne: false
            referencedRelation: "driver_profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "driver_group_memberships_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "driver_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      driver_group_payout_statement_items: {
        Row: {
          amount_gnf: number
          created_at: string
          description: string | null
          driver_user_id: string | null
          id: string
          item_type: string
          source_id: string | null
          statement_id: string
        }
        Insert: {
          amount_gnf?: number
          created_at?: string
          description?: string | null
          driver_user_id?: string | null
          id?: string
          item_type: string
          source_id?: string | null
          statement_id: string
        }
        Update: {
          amount_gnf?: number
          created_at?: string
          description?: string | null
          driver_user_id?: string | null
          id?: string
          item_type?: string
          source_id?: string | null
          statement_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "driver_group_payout_statement_items_statement_id_fkey"
            columns: ["statement_id"]
            isOneToOne: false
            referencedRelation: "driver_group_payout_statements"
            referencedColumns: ["id"]
          },
        ]
      }
      driver_group_payout_statements: {
        Row: {
          adjustments_total_gnf: number
          commissions_total_gnf: number
          finalized_at: string | null
          finalized_by: string | null
          generated_at: string
          generated_by: string | null
          group_id: string
          id: string
          leader_user_id: string | null
          notes: string | null
          paid_at: string | null
          paid_by: string | null
          period_end: string
          period_start: string
          signup_bonuses_total_gnf: number
          status: string
          total_due_gnf: number
          void_reason: string | null
          voided_by: string | null
        }
        Insert: {
          adjustments_total_gnf?: number
          commissions_total_gnf?: number
          finalized_at?: string | null
          finalized_by?: string | null
          generated_at?: string
          generated_by?: string | null
          group_id: string
          id?: string
          leader_user_id?: string | null
          notes?: string | null
          paid_at?: string | null
          paid_by?: string | null
          period_end: string
          period_start: string
          signup_bonuses_total_gnf?: number
          status?: string
          total_due_gnf?: number
          void_reason?: string | null
          voided_by?: string | null
        }
        Update: {
          adjustments_total_gnf?: number
          commissions_total_gnf?: number
          finalized_at?: string | null
          finalized_by?: string | null
          generated_at?: string
          generated_by?: string | null
          group_id?: string
          id?: string
          leader_user_id?: string | null
          notes?: string | null
          paid_at?: string | null
          paid_by?: string | null
          period_end?: string
          period_start?: string
          signup_bonuses_total_gnf?: number
          status?: string
          total_due_gnf?: number
          void_reason?: string | null
          voided_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "driver_group_payout_statements_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "driver_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      driver_group_risk_reviews: {
        Row: {
          created_at: string
          entity_id: string
          entity_type: string
          id: string
          metadata: Json
          reason: string | null
          reviewed_at: string
          reviewed_by: string | null
          risk_level: string | null
          status: string
        }
        Insert: {
          created_at?: string
          entity_id: string
          entity_type: string
          id?: string
          metadata?: Json
          reason?: string | null
          reviewed_at?: string
          reviewed_by?: string | null
          risk_level?: string | null
          status: string
        }
        Update: {
          created_at?: string
          entity_id?: string
          entity_type?: string
          id?: string
          metadata?: Json
          reason?: string | null
          reviewed_at?: string
          reviewed_by?: string | null
          risk_level?: string | null
          status?: string
        }
        Relationships: []
      }
      driver_groups: {
        Row: {
          assigned_zone_ids: string[]
          assigned_zones: string[]
          commission_percent: number
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          leader_name: string | null
          leader_phone: string | null
          leader_user_id: string | null
          name: string
          notes: string | null
          referral_code: string | null
          signup_bonus_gnf: number
          status: string
          updated_at: string
        }
        Insert: {
          assigned_zone_ids?: string[]
          assigned_zones?: string[]
          commission_percent?: number
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          leader_name?: string | null
          leader_phone?: string | null
          leader_user_id?: string | null
          name: string
          notes?: string | null
          referral_code?: string | null
          signup_bonus_gnf?: number
          status?: string
          updated_at?: string
        }
        Update: {
          assigned_zone_ids?: string[]
          assigned_zones?: string[]
          commission_percent?: number
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          leader_name?: string | null
          leader_phone?: string | null
          leader_user_id?: string | null
          name?: string
          notes?: string | null
          referral_code?: string | null
          signup_bonus_gnf?: number
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      driver_locations: {
        Row: {
          heading: number | null
          lat: number
          lng: number
          speed: number | null
          status: string
          updated_at: string
          user_id: string
          zone: string | null
        }
        Insert: {
          heading?: number | null
          lat: number
          lng: number
          speed?: number | null
          status?: string
          updated_at?: string
          user_id: string
          zone?: string | null
        }
        Update: {
          heading?: number | null
          lat?: number
          lng?: number
          speed?: number | null
          status?: string
          updated_at?: string
          user_id?: string
          zone?: string | null
        }
        Relationships: []
      }
      driver_profiles: {
        Row: {
          accept_rate: number
          approved_at: string | null
          approved_by: string | null
          capabilities: string[]
          cash_debt_gnf: number
          created_at: string
          current_operating_district: string | null
          debt_limit_gnf: number
          driver_photo_url: string | null
          id_doc_url: string | null
          last_seen_at: string | null
          last_seen_district: string | null
          plate_number: string | null
          preferred_district: string | null
          presence: Database["public"]["Enums"]["driver_presence"]
          rating: number
          rejected_reason: string | null
          status: Database["public"]["Enums"]["driver_status"]
          suspended_reason: string | null
          updated_at: string
          user_id: string
          vehicle_photo_url: string | null
          vehicle_type: Database["public"]["Enums"]["driver_vehicle_type"]
          zones: string[]
        }
        Insert: {
          accept_rate?: number
          approved_at?: string | null
          approved_by?: string | null
          capabilities?: string[]
          cash_debt_gnf?: number
          created_at?: string
          current_operating_district?: string | null
          debt_limit_gnf?: number
          driver_photo_url?: string | null
          id_doc_url?: string | null
          last_seen_at?: string | null
          last_seen_district?: string | null
          plate_number?: string | null
          preferred_district?: string | null
          presence?: Database["public"]["Enums"]["driver_presence"]
          rating?: number
          rejected_reason?: string | null
          status?: Database["public"]["Enums"]["driver_status"]
          suspended_reason?: string | null
          updated_at?: string
          user_id: string
          vehicle_photo_url?: string | null
          vehicle_type?: Database["public"]["Enums"]["driver_vehicle_type"]
          zones?: string[]
        }
        Update: {
          accept_rate?: number
          approved_at?: string | null
          approved_by?: string | null
          capabilities?: string[]
          cash_debt_gnf?: number
          created_at?: string
          current_operating_district?: string | null
          debt_limit_gnf?: number
          driver_photo_url?: string | null
          id_doc_url?: string | null
          last_seen_at?: string | null
          last_seen_district?: string | null
          plate_number?: string | null
          preferred_district?: string | null
          presence?: Database["public"]["Enums"]["driver_presence"]
          rating?: number
          rejected_reason?: string | null
          status?: Database["public"]["Enums"]["driver_status"]
          suspended_reason?: string | null
          updated_at?: string
          user_id?: string
          vehicle_photo_url?: string | null
          vehicle_type?: Database["public"]["Enums"]["driver_vehicle_type"]
          zones?: string[]
        }
        Relationships: []
      }
      driver_recruitment_campaigns: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          end_date: string | null
          group_id: string
          id: string
          leader_user_id: string | null
          milestone_rule: string
          name: string
          notes: string | null
          signup_bonus_gnf: number
          start_date: string | null
          status: string
          target_active_driver_count: number
          target_completed_rides: number
          target_driver_count: number
          updated_at: string
          zone_ids: string[]
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          end_date?: string | null
          group_id: string
          id?: string
          leader_user_id?: string | null
          milestone_rule?: string
          name: string
          notes?: string | null
          signup_bonus_gnf?: number
          start_date?: string | null
          status?: string
          target_active_driver_count?: number
          target_completed_rides?: number
          target_driver_count?: number
          updated_at?: string
          zone_ids?: string[]
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          end_date?: string | null
          group_id?: string
          id?: string
          leader_user_id?: string | null
          milestone_rule?: string
          name?: string
          notes?: string | null
          signup_bonus_gnf?: number
          start_date?: string | null
          status?: string
          target_active_driver_count?: number
          target_completed_rides?: number
          target_driver_count?: number
          updated_at?: string
          zone_ids?: string[]
        }
        Relationships: [
          {
            foreignKeyName: "driver_recruitment_campaigns_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "driver_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      driver_referral_milestone_job_runs: {
        Row: {
          eligible: number
          error: string | null
          failed: number
          id: string
          processed: number
          ran_at: string
          source: string
        }
        Insert: {
          eligible?: number
          error?: string | null
          failed?: number
          id?: string
          processed?: number
          ran_at?: string
          source?: string
        }
        Update: {
          eligible?: number
          error?: string | null
          failed?: number
          id?: string
          processed?: number
          ran_at?: string
          source?: string
        }
        Relationships: []
      }
      driver_referral_milestone_jobs: {
        Row: {
          attempts: number
          created_at: string
          driver_user_id: string | null
          event_type: string
          id: string
          last_error: string | null
          processed_at: string | null
          referral_id: string | null
          ride_id: string | null
          status: string
        }
        Insert: {
          attempts?: number
          created_at?: string
          driver_user_id?: string | null
          event_type: string
          id?: string
          last_error?: string | null
          processed_at?: string | null
          referral_id?: string | null
          ride_id?: string | null
          status?: string
        }
        Update: {
          attempts?: number
          created_at?: string
          driver_user_id?: string | null
          event_type?: string
          id?: string
          last_error?: string | null
          processed_at?: string | null
          referral_id?: string | null
          ride_id?: string | null
          status?: string
        }
        Relationships: []
      }
      driver_referrals: {
        Row: {
          approved_at: string | null
          bonus_amount_gnf: number
          campaign_id: string | null
          created_at: string
          eligible_at: string | null
          first_ride_completed_at: string | null
          group_id: string | null
          id: string
          metadata: Json
          milestone_met_at: string | null
          milestone_rule: string
          milestone_status: string
          paid_at: string | null
          referral_code: string | null
          referred_driver_user_id: string
          referrer_user_id: string | null
          rides_completed_count: number
          risk_reason: string | null
          risk_score: number
          risk_status: string
          status: string
          updated_at: string
        }
        Insert: {
          approved_at?: string | null
          bonus_amount_gnf?: number
          campaign_id?: string | null
          created_at?: string
          eligible_at?: string | null
          first_ride_completed_at?: string | null
          group_id?: string | null
          id?: string
          metadata?: Json
          milestone_met_at?: string | null
          milestone_rule?: string
          milestone_status?: string
          paid_at?: string | null
          referral_code?: string | null
          referred_driver_user_id: string
          referrer_user_id?: string | null
          rides_completed_count?: number
          risk_reason?: string | null
          risk_score?: number
          risk_status?: string
          status?: string
          updated_at?: string
        }
        Update: {
          approved_at?: string | null
          bonus_amount_gnf?: number
          campaign_id?: string | null
          created_at?: string
          eligible_at?: string | null
          first_ride_completed_at?: string | null
          group_id?: string | null
          id?: string
          metadata?: Json
          milestone_met_at?: string | null
          milestone_rule?: string
          milestone_status?: string
          paid_at?: string | null
          referral_code?: string | null
          referred_driver_user_id?: string
          referrer_user_id?: string | null
          rides_completed_count?: number
          risk_reason?: string | null
          risk_score?: number
          risk_status?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "dr_campaign_fk"
            columns: ["campaign_id"]
            isOneToOne: false
            referencedRelation: "driver_recruitment_campaigns"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "driver_referrals_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "driver_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      driver_route_traces: {
        Row: {
          accuracy_m: number | null
          created_at: string
          driver_id: string
          heading: number | null
          id: number
          lat: number
          lng: number
          mission_id: string | null
          observed_at: string
          phase: string
          planned_route_hash: string | null
          provider: string | null
          ride_id: string | null
          speed_mps: number | null
        }
        Insert: {
          accuracy_m?: number | null
          created_at?: string
          driver_id: string
          heading?: number | null
          id?: number
          lat: number
          lng: number
          mission_id?: string | null
          observed_at?: string
          phase: string
          planned_route_hash?: string | null
          provider?: string | null
          ride_id?: string | null
          speed_mps?: number | null
        }
        Update: {
          accuracy_m?: number | null
          created_at?: string
          driver_id?: string
          heading?: number | null
          id?: number
          lat?: number
          lng?: number
          mission_id?: string | null
          observed_at?: string
          phase?: string
          planned_route_hash?: string | null
          provider?: string | null
          ride_id?: string | null
          speed_mps?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "driver_route_traces_ride_id_fkey"
            columns: ["ride_id"]
            isOneToOne: false
            referencedRelation: "rides"
            referencedColumns: ["id"]
          },
        ]
      }
      email_send_log: {
        Row: {
          created_at: string
          error_message: string | null
          id: string
          message_id: string | null
          metadata: Json | null
          recipient_email: string
          status: string
          template_name: string
        }
        Insert: {
          created_at?: string
          error_message?: string | null
          id?: string
          message_id?: string | null
          metadata?: Json | null
          recipient_email: string
          status: string
          template_name: string
        }
        Update: {
          created_at?: string
          error_message?: string | null
          id?: string
          message_id?: string | null
          metadata?: Json | null
          recipient_email?: string
          status?: string
          template_name?: string
        }
        Relationships: []
      }
      email_send_state: {
        Row: {
          auth_email_ttl_minutes: number
          batch_size: number
          id: number
          retry_after_until: string | null
          send_delay_ms: number
          transactional_email_ttl_minutes: number
          updated_at: string
        }
        Insert: {
          auth_email_ttl_minutes?: number
          batch_size?: number
          id?: number
          retry_after_until?: string | null
          send_delay_ms?: number
          transactional_email_ttl_minutes?: number
          updated_at?: string
        }
        Update: {
          auth_email_ttl_minutes?: number
          batch_size?: number
          id?: number
          retry_after_until?: string | null
          send_delay_ms?: number
          transactional_email_ttl_minutes?: number
          updated_at?: string
        }
        Relationships: []
      }
      email_unsubscribe_tokens: {
        Row: {
          created_at: string
          email: string
          id: string
          token: string
          used_at: string | null
        }
        Insert: {
          created_at?: string
          email: string
          id?: string
          token: string
          used_at?: string | null
        }
        Update: {
          created_at?: string
          email?: string
          id?: string
          token?: string
          used_at?: string | null
        }
        Relationships: []
      }
      fare_settings: {
        Row: {
          base_price: number
          currency: string
          id: string
          price_per_km: number
          ride_type: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          base_price?: number
          currency?: string
          id?: string
          price_per_km?: number
          ride_type: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          base_price?: number
          currency?: string
          id?: string
          price_per_km?: number
          ride_type?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      feature_flags: {
        Row: {
          description: string | null
          enabled: boolean
          key: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          description?: string | null
          enabled?: boolean
          key: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          description?: string | null
          enabled?: boolean
          key?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      food_menu_items: {
        Row: {
          category: string | null
          created_at: string
          description: string | null
          id: string
          is_available: boolean
          name: string
          photo_url: string | null
          position: number
          prep_time_min: number | null
          price_gnf: number
          restaurant_id: string
          updated_at: string
        }
        Insert: {
          category?: string | null
          created_at?: string
          description?: string | null
          id?: string
          is_available?: boolean
          name: string
          photo_url?: string | null
          position?: number
          prep_time_min?: number | null
          price_gnf?: number
          restaurant_id: string
          updated_at?: string
        }
        Update: {
          category?: string | null
          created_at?: string
          description?: string | null
          id?: string
          is_available?: boolean
          name?: string
          photo_url?: string | null
          position?: number
          prep_time_min?: number | null
          price_gnf?: number
          restaurant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "food_menu_items_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "food_restaurants"
            referencedColumns: ["id"]
          },
        ]
      }
      food_order_items: {
        Row: {
          created_at: string
          id: string
          menu_item_id: string | null
          name_snapshot: string
          order_id: string
          qty: number
          unit_price_gnf: number
        }
        Insert: {
          created_at?: string
          id?: string
          menu_item_id?: string | null
          name_snapshot: string
          order_id: string
          qty?: number
          unit_price_gnf?: number
        }
        Update: {
          created_at?: string
          id?: string
          menu_item_id?: string | null
          name_snapshot?: string
          order_id?: string
          qty?: number
          unit_price_gnf?: number
        }
        Relationships: [
          {
            foreignKeyName: "food_order_items_menu_item_id_fkey"
            columns: ["menu_item_id"]
            isOneToOne: false
            referencedRelation: "food_menu_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "food_order_items_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "food_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      food_orders: {
        Row: {
          created_at: string
          delivery_address: string | null
          delivery_lat: number | null
          delivery_lng: number | null
          fulfillment: Database["public"]["Enums"]["food_fulfillment"]
          id: string
          notes: string | null
          payment_method: Database["public"]["Enums"]["food_payment_method"]
          restaurant_id: string
          state: Database["public"]["Enums"]["food_order_state"]
          subtotal_gnf: number
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          delivery_address?: string | null
          delivery_lat?: number | null
          delivery_lng?: number | null
          fulfillment?: Database["public"]["Enums"]["food_fulfillment"]
          id?: string
          notes?: string | null
          payment_method?: Database["public"]["Enums"]["food_payment_method"]
          restaurant_id: string
          state?: Database["public"]["Enums"]["food_order_state"]
          subtotal_gnf?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          delivery_address?: string | null
          delivery_lat?: number | null
          delivery_lng?: number | null
          fulfillment?: Database["public"]["Enums"]["food_fulfillment"]
          id?: string
          notes?: string | null
          payment_method?: Database["public"]["Enums"]["food_payment_method"]
          restaurant_id?: string
          state?: Database["public"]["Enums"]["food_order_state"]
          subtotal_gnf?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "food_orders_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "food_restaurants"
            referencedColumns: ["id"]
          },
        ]
      }
      food_restaurants: {
        Row: {
          avatar_url: string | null
          choppay_enabled: boolean
          cover_url: string | null
          created_at: string
          cuisine: string | null
          delivery_available: boolean
          district: string | null
          id: string
          is_open: boolean
          latitude: number | null
          longitude: number | null
          name: string
          owner_user_id: string | null
          pickup_available: boolean
          prep_time_min: number
          slug: string
          status: string
          updated_at: string
          verification_state: string
        }
        Insert: {
          avatar_url?: string | null
          choppay_enabled?: boolean
          cover_url?: string | null
          created_at?: string
          cuisine?: string | null
          delivery_available?: boolean
          district?: string | null
          id?: string
          is_open?: boolean
          latitude?: number | null
          longitude?: number | null
          name: string
          owner_user_id?: string | null
          pickup_available?: boolean
          prep_time_min?: number
          slug: string
          status?: string
          updated_at?: string
          verification_state?: string
        }
        Update: {
          avatar_url?: string | null
          choppay_enabled?: boolean
          cover_url?: string | null
          created_at?: string
          cuisine?: string | null
          delivery_available?: boolean
          district?: string | null
          id?: string
          is_open?: boolean
          latitude?: number | null
          longitude?: number | null
          name?: string
          owner_user_id?: string | null
          pickup_available?: boolean
          prep_time_min?: number
          slug?: string
          status?: string
          updated_at?: string
          verification_state?: string
        }
        Relationships: []
      }
      landmarks: {
        Row: {
          active: boolean
          aliases: string[]
          category: string
          commune: string | null
          created_at: string
          id: string
          lat: number
          lng: number
          name: string
          neighborhood: string | null
          popularity: number
          updated_at: string
        }
        Insert: {
          active?: boolean
          aliases?: string[]
          category: string
          commune?: string | null
          created_at?: string
          id?: string
          lat: number
          lng: number
          name: string
          neighborhood?: string | null
          popularity?: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          aliases?: string[]
          category?: string
          commune?: string | null
          created_at?: string
          id?: string
          lat?: number
          lng?: number
          name?: string
          neighborhood?: string | null
          popularity?: number
          updated_at?: string
        }
        Relationships: []
      }
      learned_route_segments: {
        Row: {
          average_distance_delta_m: number | null
          average_time_saved_s: number | null
          confidence_score: number
          created_at: string
          day_type: string | null
          destination_district: string | null
          destination_geohash: string
          deviation_frequency: number | null
          first_observed_at: string | null
          id: number
          last_observed_at: string | null
          median_distance_m: number | null
          median_duration_s: number | null
          median_speed_kmh: number | null
          notes: string | null
          observed_count: number
          origin_district: string | null
          origin_geohash: string
          phase: string | null
          provider_median_distance_m: number | null
          provider_median_duration_s: number | null
          reviewed_at: string | null
          reviewed_by: string | null
          segment_hash: string | null
          source: string
          status: string
          time_window: string | null
          unique_driver_count: number
          updated_at: string
        }
        Insert: {
          average_distance_delta_m?: number | null
          average_time_saved_s?: number | null
          confidence_score?: number
          created_at?: string
          day_type?: string | null
          destination_district?: string | null
          destination_geohash: string
          deviation_frequency?: number | null
          first_observed_at?: string | null
          id?: number
          last_observed_at?: string | null
          median_distance_m?: number | null
          median_duration_s?: number | null
          median_speed_kmh?: number | null
          notes?: string | null
          observed_count?: number
          origin_district?: string | null
          origin_geohash: string
          phase?: string | null
          provider_median_distance_m?: number | null
          provider_median_duration_s?: number | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          segment_hash?: string | null
          source?: string
          status?: string
          time_window?: string | null
          unique_driver_count?: number
          updated_at?: string
        }
        Update: {
          average_distance_delta_m?: number | null
          average_time_saved_s?: number | null
          confidence_score?: number
          created_at?: string
          day_type?: string | null
          destination_district?: string | null
          destination_geohash?: string
          deviation_frequency?: number | null
          first_observed_at?: string | null
          id?: number
          last_observed_at?: string | null
          median_distance_m?: number | null
          median_duration_s?: number | null
          median_speed_kmh?: number | null
          notes?: string | null
          observed_count?: number
          origin_district?: string | null
          origin_geohash?: string
          phase?: string | null
          provider_median_distance_m?: number | null
          provider_median_duration_s?: number | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          segment_hash?: string | null
          source?: string
          status?: string
          time_window?: string | null
          unique_driver_count?: number
          updated_at?: string
        }
        Relationships: []
      }
      listing_images: {
        Row: {
          created_at: string
          id: string
          image_type: string
          is_primary: boolean
          listing_id: string
          position: number
          processing_error_code: string | null
          processing_status: string
          source_image_id: string | null
          updated_at: string
          url: string
        }
        Insert: {
          created_at?: string
          id?: string
          image_type?: string
          is_primary?: boolean
          listing_id: string
          position?: number
          processing_error_code?: string | null
          processing_status?: string
          source_image_id?: string | null
          updated_at?: string
          url: string
        }
        Update: {
          created_at?: string
          id?: string
          image_type?: string
          is_primary?: boolean
          listing_id?: string
          position?: number
          processing_error_code?: string | null
          processing_status?: string
          source_image_id?: string | null
          updated_at?: string
          url?: string
        }
        Relationships: [
          {
            foreignKeyName: "listing_images_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "marketplace_listings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "listing_images_source_image_id_fkey"
            columns: ["source_image_id"]
            isOneToOne: false
            referencedRelation: "listing_images"
            referencedColumns: ["id"]
          },
        ]
      }
      listing_interests: {
        Row: {
          buyer_id: string
          created_at: string
          id: string
          kind: Database["public"]["Enums"]["listing_interest_kind"]
          listing_id: string
          note: string | null
          response: string | null
          seller_id: string
          state: Database["public"]["Enums"]["listing_interest_state"]
          updated_at: string
        }
        Insert: {
          buyer_id: string
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["listing_interest_kind"]
          listing_id: string
          note?: string | null
          response?: string | null
          seller_id: string
          state?: Database["public"]["Enums"]["listing_interest_state"]
          updated_at?: string
        }
        Update: {
          buyer_id?: string
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["listing_interest_kind"]
          listing_id?: string
          note?: string | null
          response?: string | null
          seller_id?: string
          state?: Database["public"]["Enums"]["listing_interest_state"]
          updated_at?: string
        }
        Relationships: []
      }
      listing_metrics: {
        Row: {
          clicks: number
          listing_id: string
          messages: number
          saves: number
          updated_at: string
          views: number
        }
        Insert: {
          clicks?: number
          listing_id: string
          messages?: number
          saves?: number
          updated_at?: string
          views?: number
        }
        Update: {
          clicks?: number
          listing_id?: string
          messages?: number
          saves?: number
          updated_at?: string
          views?: number
        }
        Relationships: [
          {
            foreignKeyName: "listing_metrics_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: true
            referencedRelation: "marketplace_listings"
            referencedColumns: ["id"]
          },
        ]
      }
      listing_reports: {
        Row: {
          created_at: string
          details: string | null
          id: string
          listing_id: string
          reason: string
          reporter_id: string | null
          status: Database["public"]["Enums"]["report_status"]
        }
        Insert: {
          created_at?: string
          details?: string | null
          id?: string
          listing_id: string
          reason: string
          reporter_id?: string | null
          status?: Database["public"]["Enums"]["report_status"]
        }
        Update: {
          created_at?: string
          details?: string | null
          id?: string
          listing_id?: string
          reason?: string
          reporter_id?: string | null
          status?: Database["public"]["Enums"]["report_status"]
        }
        Relationships: [
          {
            foreignKeyName: "listing_reports_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "marketplace_listings"
            referencedColumns: ["id"]
          },
        ]
      }
      listing_saves: {
        Row: {
          created_at: string
          listing_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          listing_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          listing_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "listing_saves_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "marketplace_listings"
            referencedColumns: ["id"]
          },
        ]
      }
      location_search_events: {
        Row: {
          confidence: string | null
          context: string | null
          created_at: string
          district: string | null
          id: string
          latitude: number | null
          longitude: number | null
          query: string | null
          selected_label: string | null
          selected_place_id: string | null
          selected_source: string | null
          user_id: string | null
        }
        Insert: {
          confidence?: string | null
          context?: string | null
          created_at?: string
          district?: string | null
          id?: string
          latitude?: number | null
          longitude?: number | null
          query?: string | null
          selected_label?: string | null
          selected_place_id?: string | null
          selected_source?: string | null
          user_id?: string | null
        }
        Update: {
          confidence?: string | null
          context?: string | null
          created_at?: string
          district?: string | null
          id?: string
          latitude?: number | null
          longitude?: number | null
          query?: string | null
          selected_label?: string | null
          selected_place_id?: string | null
          selected_source?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      map_provider_settings: {
        Row: {
          default_lat: number
          default_lng: number
          default_zoom: number
          flags: Json
          id: number
          routing_provider: string
          style_url: string
          updated_at: string
        }
        Insert: {
          default_lat?: number
          default_lng?: number
          default_zoom?: number
          flags?: Json
          id?: number
          routing_provider?: string
          style_url?: string
          updated_at?: string
        }
        Update: {
          default_lat?: number
          default_lng?: number
          default_zoom?: number
          flags?: Json
          id?: number
          routing_provider?: string
          style_url?: string
          updated_at?: string
        }
        Relationships: []
      }
      maps_rate_limits: {
        Row: {
          count: number
          user_id: string
          window_kind: string
          window_start: string
        }
        Insert: {
          count?: number
          user_id: string
          window_kind: string
          window_start: string
        }
        Update: {
          count?: number
          user_id?: string
          window_kind?: string
          window_start?: string
        }
        Relationships: []
      }
      maps_request_log: {
        Row: {
          action: string
          created_at: string
          error_message: string | null
          id: string
          input: Json
          latency_ms: number | null
          output_summary: Json | null
          provider: string
          status: string
          user_id: string | null
        }
        Insert: {
          action: string
          created_at?: string
          error_message?: string | null
          id?: string
          input?: Json
          latency_ms?: number | null
          output_summary?: Json | null
          provider: string
          status?: string
          user_id?: string | null
        }
        Update: {
          action?: string
          created_at?: string
          error_message?: string | null
          id?: string
          input?: Json
          latency_ms?: number | null
          output_summary?: Json | null
          provider?: string
          status?: string
          user_id?: string | null
        }
        Relationships: []
      }
      market_onboarding_assignments: {
        Row: {
          assigned_zone: string | null
          campaign_id: string
          created_at: string
          id: string
          merchants_completed: number
          merchants_targeted: number
          specialist_user_id: string
          status: string
          updated_at: string
        }
        Insert: {
          assigned_zone?: string | null
          campaign_id: string
          created_at?: string
          id?: string
          merchants_completed?: number
          merchants_targeted?: number
          specialist_user_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          assigned_zone?: string | null
          campaign_id?: string
          created_at?: string
          id?: string
          merchants_completed?: number
          merchants_targeted?: number
          specialist_user_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "market_onboarding_assignments_campaign_id_fkey"
            columns: ["campaign_id"]
            isOneToOne: false
            referencedRelation: "market_onboarding_campaigns"
            referencedColumns: ["id"]
          },
        ]
      }
      market_onboarding_campaigns: {
        Row: {
          created_at: string
          end_date: string | null
          id: string
          market_id: string
          name: string
          notes: string | null
          start_date: string | null
          status: string
          target_merchants: number | null
          team_lead: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          end_date?: string | null
          id?: string
          market_id: string
          name: string
          notes?: string | null
          start_date?: string | null
          status?: string
          target_merchants?: number | null
          team_lead?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          end_date?: string | null
          id?: string
          market_id?: string
          name?: string
          notes?: string | null
          start_date?: string | null
          status?: string
          target_merchants?: number | null
          team_lead?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "market_onboarding_campaigns_market_id_fkey"
            columns: ["market_id"]
            isOneToOne: false
            referencedRelation: "physical_markets"
            referencedColumns: ["id"]
          },
        ]
      }
      marketplace_listings: {
        Row: {
          allow_offers: boolean
          asking_price_gnf: number | null
          availability: Database["public"]["Enums"]["listing_availability"]
          barcode: string | null
          category: string
          commune: string | null
          condition: string | null
          created_at: string
          delivery_available: boolean
          description: string | null
          fulfillment_options: string[]
          id: string
          is_negotiable: boolean
          is_urgent: boolean
          kind: Database["public"]["Enums"]["listing_kind"]
          landmark: string | null
          minimum_price_gnf: number | null
          neighborhood: string | null
          offer_increment_gnf: number | null
          photo_count: number
          price_gnf: number | null
          pricing_mode: string
          promoted: boolean
          quantity_in_stock: number | null
          seller_id: string
          sold_count: number
          status: Database["public"]["Enums"]["listing_status"]
          store_id: string | null
          title: string
          updated_at: string
          view_count: number
          visibility: string
        }
        Insert: {
          allow_offers?: boolean
          asking_price_gnf?: number | null
          availability?: Database["public"]["Enums"]["listing_availability"]
          barcode?: string | null
          category: string
          commune?: string | null
          condition?: string | null
          created_at?: string
          delivery_available?: boolean
          description?: string | null
          fulfillment_options?: string[]
          id?: string
          is_negotiable?: boolean
          is_urgent?: boolean
          kind?: Database["public"]["Enums"]["listing_kind"]
          landmark?: string | null
          minimum_price_gnf?: number | null
          neighborhood?: string | null
          offer_increment_gnf?: number | null
          photo_count?: number
          price_gnf?: number | null
          pricing_mode?: string
          promoted?: boolean
          quantity_in_stock?: number | null
          seller_id: string
          sold_count?: number
          status?: Database["public"]["Enums"]["listing_status"]
          store_id?: string | null
          title: string
          updated_at?: string
          view_count?: number
          visibility?: string
        }
        Update: {
          allow_offers?: boolean
          asking_price_gnf?: number | null
          availability?: Database["public"]["Enums"]["listing_availability"]
          barcode?: string | null
          category?: string
          commune?: string | null
          condition?: string | null
          created_at?: string
          delivery_available?: boolean
          description?: string | null
          fulfillment_options?: string[]
          id?: string
          is_negotiable?: boolean
          is_urgent?: boolean
          kind?: Database["public"]["Enums"]["listing_kind"]
          landmark?: string | null
          minimum_price_gnf?: number | null
          neighborhood?: string | null
          offer_increment_gnf?: number | null
          photo_count?: number
          price_gnf?: number | null
          pricing_mode?: string
          promoted?: boolean
          quantity_in_stock?: number | null
          seller_id?: string
          sold_count?: number
          status?: Database["public"]["Enums"]["listing_status"]
          store_id?: string | null
          title?: string
          updated_at?: string
          view_count?: number
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "marketplace_listings_store_id_fkey"
            columns: ["store_id"]
            isOneToOne: false
            referencedRelation: "merchant_stores"
            referencedColumns: ["id"]
          },
        ]
      }
      marketplace_offers: {
        Row: {
          buyer_message: string | null
          buyer_user_id: string
          counter_amount_gnf: number | null
          created_at: string
          expires_at: string | null
          id: string
          listing_id: string
          merchant_message: string | null
          merchant_store_id: string | null
          merchant_user_id: string
          metadata: Json
          offer_amount_gnf: number
          responded_at: string | null
          status: string
          updated_at: string
        }
        Insert: {
          buyer_message?: string | null
          buyer_user_id: string
          counter_amount_gnf?: number | null
          created_at?: string
          expires_at?: string | null
          id?: string
          listing_id: string
          merchant_message?: string | null
          merchant_store_id?: string | null
          merchant_user_id: string
          metadata?: Json
          offer_amount_gnf: number
          responded_at?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          buyer_message?: string | null
          buyer_user_id?: string
          counter_amount_gnf?: number | null
          created_at?: string
          expires_at?: string | null
          id?: string
          listing_id?: string
          merchant_message?: string | null
          merchant_store_id?: string | null
          merchant_user_id?: string
          metadata?: Json
          offer_amount_gnf?: number
          responded_at?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "marketplace_offers_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "marketplace_listings"
            referencedColumns: ["id"]
          },
        ]
      }
      merchant_stores: {
        Row: {
          address_label: string | null
          approved_at: string | null
          approved_by: string | null
          avatar_url: string | null
          bio: string | null
          business_name: string | null
          business_type: string | null
          category: string | null
          choppay_enabled: boolean
          cover_url: string | null
          created_at: string
          created_by: string | null
          delivery_available: boolean
          district: string | null
          id: string
          id_photo_path: string | null
          landmark: string | null
          latitude: number | null
          location_accuracy_m: number | null
          location_confirmed_at: string | null
          location_source: string | null
          longitude: number | null
          market_id: string | null
          member_since: string
          name: string
          onboarding_status: string
          operating_hours: string | null
          owner_name: string | null
          owner_user_id: string
          phone: string | null
          rejection_reason: string | null
          selfie_photo_path: string | null
          slug: string
          stall_number: string | null
          status: string
          storefront_photo_path: string | null
          submitted_at: string | null
          updated_at: string
          verification_state: string
          whatsapp: string | null
        }
        Insert: {
          address_label?: string | null
          approved_at?: string | null
          approved_by?: string | null
          avatar_url?: string | null
          bio?: string | null
          business_name?: string | null
          business_type?: string | null
          category?: string | null
          choppay_enabled?: boolean
          cover_url?: string | null
          created_at?: string
          created_by?: string | null
          delivery_available?: boolean
          district?: string | null
          id?: string
          id_photo_path?: string | null
          landmark?: string | null
          latitude?: number | null
          location_accuracy_m?: number | null
          location_confirmed_at?: string | null
          location_source?: string | null
          longitude?: number | null
          market_id?: string | null
          member_since?: string
          name: string
          onboarding_status?: string
          operating_hours?: string | null
          owner_name?: string | null
          owner_user_id: string
          phone?: string | null
          rejection_reason?: string | null
          selfie_photo_path?: string | null
          slug: string
          stall_number?: string | null
          status?: string
          storefront_photo_path?: string | null
          submitted_at?: string | null
          updated_at?: string
          verification_state?: string
          whatsapp?: string | null
        }
        Update: {
          address_label?: string | null
          approved_at?: string | null
          approved_by?: string | null
          avatar_url?: string | null
          bio?: string | null
          business_name?: string | null
          business_type?: string | null
          category?: string | null
          choppay_enabled?: boolean
          cover_url?: string | null
          created_at?: string
          created_by?: string | null
          delivery_available?: boolean
          district?: string | null
          id?: string
          id_photo_path?: string | null
          landmark?: string | null
          latitude?: number | null
          location_accuracy_m?: number | null
          location_confirmed_at?: string | null
          location_source?: string | null
          longitude?: number | null
          market_id?: string | null
          member_since?: string
          name?: string
          onboarding_status?: string
          operating_hours?: string | null
          owner_name?: string | null
          owner_user_id?: string
          phone?: string | null
          rejection_reason?: string | null
          selfie_photo_path?: string | null
          slug?: string
          stall_number?: string | null
          status?: string
          storefront_photo_path?: string | null
          submitted_at?: string | null
          updated_at?: string
          verification_state?: string
          whatsapp?: string | null
        }
        Relationships: []
      }
      merchants: {
        Row: {
          address: string | null
          category: string | null
          city: string
          created_at: string
          id: string
          lat: number | null
          lng: number | null
          name: string
          owner_user_id: string | null
          status: string
          updated_at: string
        }
        Insert: {
          address?: string | null
          category?: string | null
          city?: string
          created_at?: string
          id?: string
          lat?: number | null
          lng?: number | null
          name: string
          owner_user_id?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          address?: string | null
          category?: string | null
          city?: string
          created_at?: string
          id?: string
          lat?: number | null
          lng?: number | null
          name?: string
          owner_user_id?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      message_log: {
        Row: {
          body: string
          channel: Database["public"]["Enums"]["message_channel"]
          created_at: string
          delivered_at: string | null
          error: string | null
          id: string
          payload: Json
          provider: string
          provider_message_id: string | null
          retry_count: number
          sent_at: string | null
          status: Database["public"]["Enums"]["message_status"]
          template: Database["public"]["Enums"]["message_template"]
          to_address: string
          user_id: string | null
        }
        Insert: {
          body: string
          channel: Database["public"]["Enums"]["message_channel"]
          created_at?: string
          delivered_at?: string | null
          error?: string | null
          id?: string
          payload?: Json
          provider: string
          provider_message_id?: string | null
          retry_count?: number
          sent_at?: string | null
          status?: Database["public"]["Enums"]["message_status"]
          template: Database["public"]["Enums"]["message_template"]
          to_address: string
          user_id?: string | null
        }
        Update: {
          body?: string
          channel?: Database["public"]["Enums"]["message_channel"]
          created_at?: string
          delivered_at?: string | null
          error?: string | null
          id?: string
          payload?: Json
          provider?: string
          provider_message_id?: string | null
          retry_count?: number
          sent_at?: string | null
          status?: Database["public"]["Enums"]["message_status"]
          template?: Database["public"]["Enums"]["message_template"]
          to_address?: string
          user_id?: string | null
        }
        Relationships: []
      }
      messages: {
        Row: {
          attachment_url: string | null
          body: string | null
          conversation_id: string
          created_at: string
          id: string
          kind: Database["public"]["Enums"]["message_kind"]
          sender_id: string
        }
        Insert: {
          attachment_url?: string | null
          body?: string | null
          conversation_id: string
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["message_kind"]
          sender_id: string
        }
        Update: {
          attachment_url?: string | null
          body?: string | null
          conversation_id?: string
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["message_kind"]
          sender_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "messages_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
        ]
      }
      mission_events: {
        Row: {
          actor_id: string | null
          created_at: string
          event: string
          id: string
          mission_id: string
          note: string | null
        }
        Insert: {
          actor_id?: string | null
          created_at?: string
          event: string
          id?: string
          mission_id: string
          note?: string | null
        }
        Update: {
          actor_id?: string | null
          created_at?: string
          event?: string
          id?: string
          mission_id?: string
          note?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "mission_events_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
        ]
      }
      missions: {
        Row: {
          courier_id: string | null
          created_at: string
          customer_id: string
          dropoff_address: string | null
          dropoff_confirmed_at: string | null
          dropoff_confirmed_by: string | null
          dropoff_lat: number | null
          dropoff_lng: number | null
          estimated_distance_m: number | null
          estimated_duration_s: number | null
          estimated_earning_gnf: number
          id: string
          issue_district: string | null
          issue_hub_id: string | null
          issue_reason: string | null
          merchant_id: string | null
          payload_summary: string | null
          pickup_address: string | null
          pickup_confirmed_at: string | null
          pickup_confirmed_by: string | null
          pickup_lat: number | null
          pickup_lng: number | null
          ref_food_order_id: string | null
          ref_market_order_id: string | null
          ref_ride_id: string | null
          state: Database["public"]["Enums"]["mission_state"]
          type: Database["public"]["Enums"]["mission_type"]
          updated_at: string
        }
        Insert: {
          courier_id?: string | null
          created_at?: string
          customer_id: string
          dropoff_address?: string | null
          dropoff_confirmed_at?: string | null
          dropoff_confirmed_by?: string | null
          dropoff_lat?: number | null
          dropoff_lng?: number | null
          estimated_distance_m?: number | null
          estimated_duration_s?: number | null
          estimated_earning_gnf?: number
          id?: string
          issue_district?: string | null
          issue_hub_id?: string | null
          issue_reason?: string | null
          merchant_id?: string | null
          payload_summary?: string | null
          pickup_address?: string | null
          pickup_confirmed_at?: string | null
          pickup_confirmed_by?: string | null
          pickup_lat?: number | null
          pickup_lng?: number | null
          ref_food_order_id?: string | null
          ref_market_order_id?: string | null
          ref_ride_id?: string | null
          state?: Database["public"]["Enums"]["mission_state"]
          type: Database["public"]["Enums"]["mission_type"]
          updated_at?: string
        }
        Update: {
          courier_id?: string | null
          created_at?: string
          customer_id?: string
          dropoff_address?: string | null
          dropoff_confirmed_at?: string | null
          dropoff_confirmed_by?: string | null
          dropoff_lat?: number | null
          dropoff_lng?: number | null
          estimated_distance_m?: number | null
          estimated_duration_s?: number | null
          estimated_earning_gnf?: number
          id?: string
          issue_district?: string | null
          issue_hub_id?: string | null
          issue_reason?: string | null
          merchant_id?: string | null
          payload_summary?: string | null
          pickup_address?: string | null
          pickup_confirmed_at?: string | null
          pickup_confirmed_by?: string | null
          pickup_lat?: number | null
          pickup_lng?: number | null
          ref_food_order_id?: string | null
          ref_market_order_id?: string | null
          ref_ride_id?: string | null
          state?: Database["public"]["Enums"]["mission_state"]
          type?: Database["public"]["Enums"]["mission_type"]
          updated_at?: string
        }
        Relationships: []
      }
      navigation_events: {
        Row: {
          created_at: string
          event_name: string
          id: string
          metadata: Json
          mission_id: string | null
          provider: string | null
          ride_id: string | null
          surface: string | null
          user_id: string | null
        }
        Insert: {
          created_at?: string
          event_name: string
          id?: string
          metadata?: Json
          mission_id?: string | null
          provider?: string | null
          ride_id?: string | null
          surface?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string
          event_name?: string
          id?: string
          metadata?: Json
          mission_id?: string | null
          provider?: string | null
          ride_id?: string | null
          surface?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      notification_log: {
        Row: {
          channel: Database["public"]["Enums"]["notification_channel"]
          created_at: string
          error_message: string | null
          external_id: string | null
          id: string
          payload: Json
          priority: Database["public"]["Enums"]["notification_priority"]
          recipient: string | null
          status: Database["public"]["Enums"]["notification_status"]
          template: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          channel: Database["public"]["Enums"]["notification_channel"]
          created_at?: string
          error_message?: string | null
          external_id?: string | null
          id?: string
          payload?: Json
          priority?: Database["public"]["Enums"]["notification_priority"]
          recipient?: string | null
          status?: Database["public"]["Enums"]["notification_status"]
          template: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          channel?: Database["public"]["Enums"]["notification_channel"]
          created_at?: string
          error_message?: string | null
          external_id?: string | null
          id?: string
          payload?: Json
          priority?: Database["public"]["Enums"]["notification_priority"]
          recipient?: string | null
          status?: Database["public"]["Enums"]["notification_status"]
          template?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: []
      }
      notification_preferences: {
        Row: {
          created_at: string
          preferred_channel: Database["public"]["Enums"]["message_channel"]
          sms_enabled: boolean
          topic_marketing: boolean
          topic_otp: boolean
          topic_ride: boolean
          topic_wallet: boolean
          updated_at: string
          user_id: string
          whatsapp_enabled: boolean
        }
        Insert: {
          created_at?: string
          preferred_channel?: Database["public"]["Enums"]["message_channel"]
          sms_enabled?: boolean
          topic_marketing?: boolean
          topic_otp?: boolean
          topic_ride?: boolean
          topic_wallet?: boolean
          updated_at?: string
          user_id: string
          whatsapp_enabled?: boolean
        }
        Update: {
          created_at?: string
          preferred_channel?: Database["public"]["Enums"]["message_channel"]
          sms_enabled?: boolean
          topic_marketing?: boolean
          topic_otp?: boolean
          topic_ride?: boolean
          topic_wallet?: boolean
          updated_at?: string
          user_id?: string
          whatsapp_enabled?: boolean
        }
        Relationships: []
      }
      payment_intents: {
        Row: {
          amount_gnf: number
          created_at: string
          currency: string
          id: string
          internal_reference: string
          metadata: Json
          provider: Database["public"]["Enums"]["payment_provider"]
          provider_reference: string | null
          purpose: Database["public"]["Enums"]["payment_purpose"]
          related_listing_id: string | null
          related_mission_id: string | null
          related_order_id: string | null
          related_store_id: string | null
          state: Database["public"]["Enums"]["payment_state"]
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_gnf: number
          created_at?: string
          currency?: string
          id?: string
          internal_reference: string
          metadata?: Json
          provider?: Database["public"]["Enums"]["payment_provider"]
          provider_reference?: string | null
          purpose: Database["public"]["Enums"]["payment_purpose"]
          related_listing_id?: string | null
          related_mission_id?: string | null
          related_order_id?: string | null
          related_store_id?: string | null
          state?: Database["public"]["Enums"]["payment_state"]
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_gnf?: number
          created_at?: string
          currency?: string
          id?: string
          internal_reference?: string
          metadata?: Json
          provider?: Database["public"]["Enums"]["payment_provider"]
          provider_reference?: string | null
          purpose?: Database["public"]["Enums"]["payment_purpose"]
          related_listing_id?: string | null
          related_mission_id?: string | null
          related_order_id?: string | null
          related_store_id?: string | null
          state?: Database["public"]["Enums"]["payment_state"]
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      payment_provider_events: {
        Row: {
          amount_gnf: number
          created_at: string
          currency: string
          event_type: string
          id: string
          match_confidence: number | null
          matched_topup_request_id: string | null
          matched_user_id: string | null
          notes: string | null
          om_code_normalized: string | null
          payer_phone: string | null
          processed_at: string | null
          processing_status: string
          provider: string
          provider_transaction_id: string
          raw_payload: Json
          receiving_account_id: string | null
          status: string
        }
        Insert: {
          amount_gnf: number
          created_at?: string
          currency?: string
          event_type?: string
          id?: string
          match_confidence?: number | null
          matched_topup_request_id?: string | null
          matched_user_id?: string | null
          notes?: string | null
          om_code_normalized?: string | null
          payer_phone?: string | null
          processed_at?: string | null
          processing_status?: string
          provider: string
          provider_transaction_id: string
          raw_payload?: Json
          receiving_account_id?: string | null
          status?: string
        }
        Update: {
          amount_gnf?: number
          created_at?: string
          currency?: string
          event_type?: string
          id?: string
          match_confidence?: number | null
          matched_topup_request_id?: string | null
          matched_user_id?: string | null
          notes?: string | null
          om_code_normalized?: string | null
          payer_phone?: string | null
          processed_at?: string | null
          processing_status?: string
          provider?: string
          provider_transaction_id?: string
          raw_payload?: Json
          receiving_account_id?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_provider_events_receiving_account_id_fkey"
            columns: ["receiving_account_id"]
            isOneToOne: false
            referencedRelation: "payment_receiving_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_receiving_accounts: {
        Row: {
          admin_notes: string | null
          created_at: string
          created_by: string | null
          id: string
          is_active: boolean
          label: string
          phone_e164: string
          provider: string
          public_instructions: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          admin_notes?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          is_active?: boolean
          label: string
          phone_e164: string
          provider?: string
          public_instructions?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          admin_notes?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          is_active?: boolean
          label?: string
          phone_e164?: string
          provider?: string
          public_instructions?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      payment_reconciliation_events: {
        Row: {
          actor_user_id: string | null
          created_at: string
          event_type: Database["public"]["Enums"]["payment_recon_event"]
          id: string
          intent_id: string
          payload: Json
          provider: Database["public"]["Enums"]["payment_provider"] | null
          provider_reference: string | null
        }
        Insert: {
          actor_user_id?: string | null
          created_at?: string
          event_type: Database["public"]["Enums"]["payment_recon_event"]
          id?: string
          intent_id: string
          payload?: Json
          provider?: Database["public"]["Enums"]["payment_provider"] | null
          provider_reference?: string | null
        }
        Update: {
          actor_user_id?: string | null
          created_at?: string
          event_type?: Database["public"]["Enums"]["payment_recon_event"]
          id?: string
          intent_id?: string
          payload?: Json
          provider?: Database["public"]["Enums"]["payment_provider"] | null
          provider_reference?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payment_reconciliation_events_intent_id_fkey"
            columns: ["intent_id"]
            isOneToOne: false
            referencedRelation: "payment_intents"
            referencedColumns: ["id"]
          },
        ]
      }
      physical_markets: {
        Row: {
          address: string | null
          commune: string | null
          created_at: string
          district: string | null
          id: string
          landmark: string | null
          latitude: number | null
          longitude: number | null
          name: string
          notes: string | null
          status: string
          updated_at: string
        }
        Insert: {
          address?: string | null
          commune?: string | null
          created_at?: string
          district?: string | null
          id?: string
          landmark?: string | null
          latitude?: number | null
          longitude?: number | null
          name: string
          notes?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          address?: string | null
          commune?: string | null
          created_at?: string
          district?: string | null
          id?: string
          landmark?: string | null
          latitude?: number | null
          longitude?: number | null
          name?: string
          notes?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          account_status: string
          avatar_url: string | null
          created_at: string
          deleted_at: string | null
          display_name: string | null
          email: string | null
          first_name: string | null
          full_name: string | null
          has_pin: boolean
          id: string
          kyc_level: number
          language: string
          last_name: string | null
          last_profile_confirmed_at: string | null
          phone: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          account_status?: string
          avatar_url?: string | null
          created_at?: string
          deleted_at?: string | null
          display_name?: string | null
          email?: string | null
          first_name?: string | null
          full_name?: string | null
          has_pin?: boolean
          id?: string
          kyc_level?: number
          language?: string
          last_name?: string | null
          last_profile_confirmed_at?: string | null
          phone?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          account_status?: string
          avatar_url?: string | null
          created_at?: string
          deleted_at?: string | null
          display_name?: string | null
          email?: string | null
          first_name?: string | null
          full_name?: string | null
          has_pin?: boolean
          id?: string
          kyc_level?: number
          language?: string
          last_name?: string | null
          last_profile_confirmed_at?: string | null
          phone?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      ride_offers: {
        Row: {
          decline_reason: string | null
          destination_zone: string | null
          distance_to_pickup_m: number | null
          driver_id: string
          estimated_earning_gnf: number | null
          estimated_fare_gnf: number | null
          expires_at: string
          id: string
          pickup_zone: string | null
          responded_at: string | null
          ride_id: string
          sent_at: string
          status: Database["public"]["Enums"]["ride_offer_status"]
        }
        Insert: {
          decline_reason?: string | null
          destination_zone?: string | null
          distance_to_pickup_m?: number | null
          driver_id: string
          estimated_earning_gnf?: number | null
          estimated_fare_gnf?: number | null
          expires_at?: string
          id?: string
          pickup_zone?: string | null
          responded_at?: string | null
          ride_id: string
          sent_at?: string
          status?: Database["public"]["Enums"]["ride_offer_status"]
        }
        Update: {
          decline_reason?: string | null
          destination_zone?: string | null
          distance_to_pickup_m?: number | null
          driver_id?: string
          estimated_earning_gnf?: number | null
          estimated_fare_gnf?: number | null
          expires_at?: string
          id?: string
          pickup_zone?: string | null
          responded_at?: string | null
          ride_id?: string
          sent_at?: string
          status?: Database["public"]["Enums"]["ride_offer_status"]
        }
        Relationships: []
      }
      ride_ratings: {
        Row: {
          comment: string | null
          created_at: string
          direction: Database["public"]["Enums"]["rating_direction"]
          id: string
          ratee_id: string
          rater_id: string
          ride_id: string
          score: number
        }
        Insert: {
          comment?: string | null
          created_at?: string
          direction: Database["public"]["Enums"]["rating_direction"]
          id?: string
          ratee_id: string
          rater_id: string
          ride_id: string
          score: number
        }
        Update: {
          comment?: string | null
          created_at?: string
          direction?: Database["public"]["Enums"]["rating_direction"]
          id?: string
          ratee_id?: string
          rater_id?: string
          ride_id?: string
          score?: number
        }
        Relationships: []
      }
      ride_route_summaries: {
        Row: {
          actual_route_distance_m: number | null
          actual_route_duration_s: number | null
          average_speed_kmh: number | null
          created_at: string
          day_type: string | null
          deviation_count: number
          driver_id: string | null
          end_district: string | null
          hour_bucket: number | null
          metadata: Json
          phase: string | null
          planned_route_distance_m: number | null
          planned_route_duration_s: number | null
          point_count: number
          provider: string | null
          ride_id: string
          route_confidence: number | null
          start_district: string | null
          time_window: string | null
          updated_at: string
        }
        Insert: {
          actual_route_distance_m?: number | null
          actual_route_duration_s?: number | null
          average_speed_kmh?: number | null
          created_at?: string
          day_type?: string | null
          deviation_count?: number
          driver_id?: string | null
          end_district?: string | null
          hour_bucket?: number | null
          metadata?: Json
          phase?: string | null
          planned_route_distance_m?: number | null
          planned_route_duration_s?: number | null
          point_count?: number
          provider?: string | null
          ride_id: string
          route_confidence?: number | null
          start_district?: string | null
          time_window?: string | null
          updated_at?: string
        }
        Update: {
          actual_route_distance_m?: number | null
          actual_route_duration_s?: number | null
          average_speed_kmh?: number | null
          created_at?: string
          day_type?: string | null
          deviation_count?: number
          driver_id?: string | null
          end_district?: string | null
          hour_bucket?: number | null
          metadata?: Json
          phase?: string | null
          planned_route_distance_m?: number | null
          planned_route_duration_s?: number | null
          point_count?: number
          provider?: string | null
          ride_id?: string
          route_confidence?: number | null
          start_district?: string | null
          time_window?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ride_route_summaries_ride_id_fkey"
            columns: ["ride_id"]
            isOneToOne: true
            referencedRelation: "rides"
            referencedColumns: ["id"]
          },
        ]
      }
      rides: {
        Row: {
          client_id: string
          completed_at: string | null
          created_at: string
          dest_lat: number | null
          dest_lng: number | null
          driver_earning_gnf: number
          driver_id: string | null
          fare_gnf: number
          hold_tx_id: string | null
          id: string
          metadata: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf: number
          status: Database["public"]["Enums"]["ride_status"]
          updated_at: string
        }
        Insert: {
          client_id: string
          completed_at?: string | null
          created_at?: string
          dest_lat?: number | null
          dest_lng?: number | null
          driver_earning_gnf?: number
          driver_id?: string | null
          fare_gnf: number
          hold_tx_id?: string | null
          id?: string
          metadata?: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id?: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf?: number
          status?: Database["public"]["Enums"]["ride_status"]
          updated_at?: string
        }
        Update: {
          client_id?: string
          completed_at?: string | null
          created_at?: string
          dest_lat?: number | null
          dest_lng?: number | null
          driver_earning_gnf?: number
          driver_id?: string | null
          fare_gnf?: number
          hold_tx_id?: string | null
          id?: string
          metadata?: Json | null
          mode?: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id?: string | null
          pickup_lat?: number
          pickup_lng?: number
          platform_fee_gnf?: number
          status?: Database["public"]["Enums"]["ride_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "rides_hold_tx_id_fkey"
            columns: ["hold_tx_id"]
            isOneToOne: false
            referencedRelation: "wallet_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rides_payment_tx_id_fkey"
            columns: ["payment_tx_id"]
            isOneToOne: false
            referencedRelation: "wallet_transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      saved_listings: {
        Row: {
          created_at: string
          listing_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          listing_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          listing_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "saved_listings_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "marketplace_listings"
            referencedColumns: ["id"]
          },
        ]
      }
      saved_places: {
        Row: {
          created_at: string
          id: string
          kind: Database["public"]["Enums"]["saved_place_kind"]
          label: string
          landmark_note: string | null
          lat: number
          lng: number
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["saved_place_kind"]
          label: string
          landmark_note?: string | null
          lat: number
          lng: number
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["saved_place_kind"]
          label?: string
          landmark_note?: string | null
          lat?: number
          lng?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      service_profiles: {
        Row: {
          availability: string | null
          bio: string | null
          created_at: string
          id: string
          portfolio_urls: string[]
          pricing_range: string | null
          profession: string
          rating: number
          response_rate: number
          service_areas: string[]
          status: string
          updated_at: string
          user_id: string
          visibility: string
        }
        Insert: {
          availability?: string | null
          bio?: string | null
          created_at?: string
          id?: string
          portfolio_urls?: string[]
          pricing_range?: string | null
          profession: string
          rating?: number
          response_rate?: number
          service_areas?: string[]
          status?: string
          updated_at?: string
          user_id: string
          visibility?: string
        }
        Update: {
          availability?: string | null
          bio?: string | null
          created_at?: string
          id?: string
          portfolio_urls?: string[]
          pricing_range?: string | null
          profession?: string
          rating?: number
          response_rate?: number
          service_areas?: string[]
          status?: string
          updated_at?: string
          user_id?: string
          visibility?: string
        }
        Relationships: []
      }
      support_issues: {
        Row: {
          assigned_role: Database["public"]["Enums"]["support_issue_role"]
          created_at: string
          description: string | null
          district: string | null
          id: string
          issue_type: Database["public"]["Enums"]["support_issue_type"]
          metadata: Json
          related_customer_id: string | null
          related_driver_id: string | null
          related_food_order_id: string | null
          related_market_listing_id: string | null
          related_mission_id: string | null
          related_payment_intent_id: string | null
          related_restaurant_id: string | null
          related_store_id: string | null
          reporter_user_id: string | null
          resolved_at: string | null
          severity: Database["public"]["Enums"]["support_issue_severity"]
          status: Database["public"]["Enums"]["support_issue_status"]
          title: string
          updated_at: string
        }
        Insert: {
          assigned_role?: Database["public"]["Enums"]["support_issue_role"]
          created_at?: string
          description?: string | null
          district?: string | null
          id?: string
          issue_type: Database["public"]["Enums"]["support_issue_type"]
          metadata?: Json
          related_customer_id?: string | null
          related_driver_id?: string | null
          related_food_order_id?: string | null
          related_market_listing_id?: string | null
          related_mission_id?: string | null
          related_payment_intent_id?: string | null
          related_restaurant_id?: string | null
          related_store_id?: string | null
          reporter_user_id?: string | null
          resolved_at?: string | null
          severity?: Database["public"]["Enums"]["support_issue_severity"]
          status?: Database["public"]["Enums"]["support_issue_status"]
          title: string
          updated_at?: string
        }
        Update: {
          assigned_role?: Database["public"]["Enums"]["support_issue_role"]
          created_at?: string
          description?: string | null
          district?: string | null
          id?: string
          issue_type?: Database["public"]["Enums"]["support_issue_type"]
          metadata?: Json
          related_customer_id?: string | null
          related_driver_id?: string | null
          related_food_order_id?: string | null
          related_market_listing_id?: string | null
          related_mission_id?: string | null
          related_payment_intent_id?: string | null
          related_restaurant_id?: string | null
          related_store_id?: string | null
          reporter_user_id?: string | null
          resolved_at?: string | null
          severity?: Database["public"]["Enums"]["support_issue_severity"]
          status?: Database["public"]["Enums"]["support_issue_status"]
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      support_messages: {
        Row: {
          created_at: string
          id: string
          message: string
          status: string
          user_id: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          message: string
          status?: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          message?: string
          status?: string
          user_id?: string | null
        }
        Relationships: []
      }
      suppressed_emails: {
        Row: {
          created_at: string
          email: string
          id: string
          metadata: Json | null
          reason: string
        }
        Insert: {
          created_at?: string
          email: string
          id?: string
          metadata?: Json | null
          reason: string
        }
        Update: {
          created_at?: string
          email?: string
          id?: string
          metadata?: Json | null
          reason?: string
        }
        Relationships: []
      }
      topup_requests: {
        Row: {
          agent_user_id: string | null
          amount_gnf: number
          cancelled_reason: string | null
          client_user_id: string
          confirmation_code: string
          confirmed_at: string | null
          created_at: string
          customer_om_code_normalized: string | null
          customer_om_code_raw: string | null
          customer_om_code_submitted_at: string | null
          expires_at: string
          id: string
          matched_provider_transaction_id: string | null
          notes: string | null
          provider: string
          receiving_account_id: string | null
          reference: string
          status: Database["public"]["Enums"]["topup_status"]
          transaction_id: string | null
          updated_at: string
          user_phone: string | null
        }
        Insert: {
          agent_user_id?: string | null
          amount_gnf: number
          cancelled_reason?: string | null
          client_user_id: string
          confirmation_code: string
          confirmed_at?: string | null
          created_at?: string
          customer_om_code_normalized?: string | null
          customer_om_code_raw?: string | null
          customer_om_code_submitted_at?: string | null
          expires_at?: string
          id?: string
          matched_provider_transaction_id?: string | null
          notes?: string | null
          provider?: string
          receiving_account_id?: string | null
          reference: string
          status?: Database["public"]["Enums"]["topup_status"]
          transaction_id?: string | null
          updated_at?: string
          user_phone?: string | null
        }
        Update: {
          agent_user_id?: string | null
          amount_gnf?: number
          cancelled_reason?: string | null
          client_user_id?: string
          confirmation_code?: string
          confirmed_at?: string | null
          created_at?: string
          customer_om_code_normalized?: string | null
          customer_om_code_raw?: string | null
          customer_om_code_submitted_at?: string | null
          expires_at?: string
          id?: string
          matched_provider_transaction_id?: string | null
          notes?: string | null
          provider?: string
          receiving_account_id?: string | null
          reference?: string
          status?: Database["public"]["Enums"]["topup_status"]
          transaction_id?: string | null
          updated_at?: string
          user_phone?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "topup_requests_receiving_account_id_fkey"
            columns: ["receiving_account_id"]
            isOneToOne: false
            referencedRelation: "payment_receiving_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "topup_requests_transaction_id_fkey"
            columns: ["transaction_id"]
            isOneToOne: false
            referencedRelation: "wallet_transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      user_consent: {
        Row: {
          basic_analytics: boolean
          consent_version: number
          created_at: string
          location_improvements: boolean
          marketing_analytics: boolean
          personalization: boolean
          security_fraud: boolean
          updated_at: string
          user_id: string
        }
        Insert: {
          basic_analytics?: boolean
          consent_version?: number
          created_at?: string
          location_improvements?: boolean
          marketing_analytics?: boolean
          personalization?: boolean
          security_fraud?: boolean
          updated_at?: string
          user_id: string
        }
        Update: {
          basic_analytics?: boolean
          consent_version?: number
          created_at?: string
          location_improvements?: boolean
          marketing_analytics?: boolean
          personalization?: boolean
          security_fraud?: boolean
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_legal_consents: {
        Row: {
          accepted_at: string
          accepted_privacy: boolean
          accepted_terms: boolean
          created_at: string
          id: string
          ip_address: string | null
          privacy_version: string
          source: string
          terms_version: string
          user_agent: string | null
          user_id: string
        }
        Insert: {
          accepted_at?: string
          accepted_privacy?: boolean
          accepted_terms?: boolean
          created_at?: string
          id?: string
          ip_address?: string | null
          privacy_version: string
          source?: string
          terms_version: string
          user_agent?: string | null
          user_id: string
        }
        Update: {
          accepted_at?: string
          accepted_privacy?: boolean
          accepted_terms?: boolean
          created_at?: string
          id?: string
          ip_address?: string | null
          privacy_version?: string
          source?: string
          terms_version?: string
          user_agent?: string | null
          user_id?: string
        }
        Relationships: []
      }
      user_pins: {
        Row: {
          pin_hash: string
          updated_at: string
          user_id: string
        }
        Insert: {
          pin_hash: string
          updated_at?: string
          user_id: string
        }
        Update: {
          pin_hash?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_preferences: {
        Row: {
          allow_marketing_notifications: boolean
          allow_personalized_offers: boolean
          allow_urban_insights: boolean
          app_mode: string
          created_at: string
          id: string
          merchant_slides_completed_at: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          allow_marketing_notifications?: boolean
          allow_personalized_offers?: boolean
          allow_urban_insights?: boolean
          app_mode?: string
          created_at?: string
          id?: string
          merchant_slides_completed_at?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          allow_marketing_notifications?: boolean
          allow_personalized_offers?: boolean
          allow_urban_insights?: boolean
          app_mode?: string
          created_at?: string
          id?: string
          merchant_slides_completed_at?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          created_at: string
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
      wallet_transactions: {
        Row: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        Insert: {
          amount_gnf: number
          completed_at?: string | null
          created_at?: string
          description?: string | null
          from_wallet_id?: string | null
          id?: string
          metadata?: Json
          reference: string
          related_entity?: string | null
          related_user_id?: string | null
          status?: Database["public"]["Enums"]["txn_status"]
          to_wallet_id?: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        Update: {
          amount_gnf?: number
          completed_at?: string | null
          created_at?: string
          description?: string | null
          from_wallet_id?: string | null
          id?: string
          metadata?: Json
          reference?: string
          related_entity?: string | null
          related_user_id?: string | null
          status?: Database["public"]["Enums"]["txn_status"]
          to_wallet_id?: string | null
          type?: Database["public"]["Enums"]["txn_type"]
        }
        Relationships: [
          {
            foreignKeyName: "wallet_transactions_from_wallet_id_fkey"
            columns: ["from_wallet_id"]
            isOneToOne: false
            referencedRelation: "wallets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wallet_transactions_to_wallet_id_fkey"
            columns: ["to_wallet_id"]
            isOneToOne: false
            referencedRelation: "wallets"
            referencedColumns: ["id"]
          },
        ]
      }
      wallets: {
        Row: {
          balance_gnf: number
          created_at: string
          currency: string
          held_gnf: number
          id: string
          owner_user_id: string | null
          party_type: Database["public"]["Enums"]["party_type"]
          status: Database["public"]["Enums"]["wallet_status"]
          updated_at: string
        }
        Insert: {
          balance_gnf?: number
          created_at?: string
          currency?: string
          held_gnf?: number
          id?: string
          owner_user_id?: string | null
          party_type: Database["public"]["Enums"]["party_type"]
          status?: Database["public"]["Enums"]["wallet_status"]
          updated_at?: string
        }
        Update: {
          balance_gnf?: number
          created_at?: string
          currency?: string
          held_gnf?: number
          id?: string
          owner_user_id?: string | null
          party_type?: Database["public"]["Enums"]["party_type"]
          status?: Database["public"]["Enums"]["wallet_status"]
          updated_at?: string
        }
        Relationships: []
      }
      zones: {
        Row: {
          city: string | null
          commune: string | null
          country: string
          created_at: string
          id: string
          kind: string
          metadata: Json
          neighborhood: string | null
          updated_at: string
        }
        Insert: {
          city?: string | null
          commune?: string | null
          country?: string
          created_at?: string
          id?: string
          kind?: string
          metadata?: Json
          neighborhood?: string | null
          updated_at?: string
        }
        Update: {
          city?: string | null
          commune?: string | null
          country?: string
          created_at?: string
          id?: string
          kind?: string
          metadata?: Json
          neighborhood?: string | null
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      agent_topup_requests: {
        Row: {
          agent_user_id: string | null
          amount_gnf: number | null
          cancelled_reason: string | null
          client_user_id: string | null
          confirmed_at: string | null
          created_at: string | null
          expires_at: string | null
          id: string | null
          reference: string | null
          status: Database["public"]["Enums"]["topup_status"] | null
          transaction_id: string | null
          updated_at: string | null
        }
        Insert: {
          agent_user_id?: string | null
          amount_gnf?: number | null
          cancelled_reason?: string | null
          client_user_id?: string | null
          confirmed_at?: string | null
          created_at?: string | null
          expires_at?: string | null
          id?: string | null
          reference?: string | null
          status?: Database["public"]["Enums"]["topup_status"] | null
          transaction_id?: string | null
          updated_at?: string | null
        }
        Update: {
          agent_user_id?: string | null
          amount_gnf?: number | null
          cancelled_reason?: string | null
          client_user_id?: string | null
          confirmed_at?: string | null
          created_at?: string | null
          expires_at?: string | null
          id?: string | null
          reference?: string | null
          status?: Database["public"]["Enums"]["topup_status"] | null
          transaction_id?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "topup_requests_transaction_id_fkey"
            columns: ["transaction_id"]
            isOneToOne: false
            referencedRelation: "wallet_transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      public_agents: {
        Row: {
          business_name: string | null
          id: string | null
          latitude: number | null
          location: string | null
          longitude: number | null
          status: Database["public"]["Enums"]["wallet_status"] | null
          user_id: string | null
        }
        Insert: {
          business_name?: string | null
          id?: string | null
          latitude?: number | null
          location?: string | null
          longitude?: number | null
          status?: Database["public"]["Enums"]["wallet_status"] | null
          user_id?: string | null
        }
        Update: {
          business_name?: string | null
          id?: string | null
          latitude?: number | null
          location?: string | null
          longitude?: number | null
          status?: Database["public"]["Enums"]["wallet_status"] | null
          user_id?: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      _anonymize_user_core: {
        Args: { _suspended_reason: string; _target: string }
        Returns: Json
      }
      _driver_group_stats: {
        Args: { p_from: string; p_group: string; p_to: string }
        Returns: {
          active_drivers: number
          commissions_paid_gnf: number
          commissions_pending_gnf: number
          gross_driver_earnings_gnf: number
          group_id: string
          rides_completed: number
          signup_bonus_eligible_count: number
          signup_bonus_paid_gnf: number
        }[]
      }
      _is_god_admin: { Args: { _user: string }; Returns: boolean }
      _is_ops_or_god_admin: { Args: { _user: string }; Returns: boolean }
      _leader_group_id: { Args: { _uid: string }; Returns: string }
      _notify_account_event: {
        Args: {
          _body: string
          _template: string
          _title: string
          _user: string
        }
        Returns: undefined
      }
      admin_adjust_agent_float: {
        Args: {
          p_agent_user_id: string
          p_delta_gnf: number
          p_reason?: string
        }
        Returns: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        SetofOptions: {
          from: "*"
          to: "wallet_transactions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_anonymize_user: {
        Args: { _reason?: string; _target: string }
        Returns: Json
      }
      admin_assign_driver_to_group: {
        Args: {
          p_driver: string
          p_group: string
          p_notes?: string
          p_zone?: string
        }
        Returns: string
      }
      admin_attach_referral_campaign: {
        Args: { p_campaign: string; p_reason?: string; p_referral: string }
        Returns: undefined
      }
      admin_auth_user_exists: { Args: { _target: string }; Returns: boolean }
      admin_ban_user: {
        Args: { _expires_at?: string; _reason: string; _target: string }
        Returns: Json
      }
      admin_check_email_reuse_blocker: {
        Args: { p_email: string }
        Returns: Json
      }
      admin_create_agent: {
        Args: {
          p_business_name: string
          p_commission_rate?: number
          p_daily_limit_gnf?: number
          p_location?: string
          p_phone: string
        }
        Returns: {
          business_name: string
          commission_rate: number
          created_at: string
          daily_limit_gnf: number
          id: string
          latitude: number | null
          location: string | null
          longitude: number | null
          prepaid_float_gnf: number
          status: Database["public"]["Enums"]["wallet_status"]
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "agent_profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_create_campaign: { Args: { payload: Json }; Returns: string }
      admin_create_contract: { Args: { payload: Json }; Returns: string }
      admin_create_driver_group: { Args: { payload: Json }; Returns: string }
      admin_driver_group_stats: {
        Args: { p_from?: string; p_group?: string; p_to?: string }
        Returns: {
          active_drivers: number
          commissions_paid_gnf: number
          commissions_pending_gnf: number
          gross_driver_earnings_gnf: number
          group_id: string
          rides_completed: number
          signup_bonus_eligible_count: number
          signup_bonus_paid_gnf: number
        }[]
      }
      admin_email_delivery_diagnostics: {
        Args: { p_email: string }
        Returns: Json
      }
      admin_enqueue_milestone_refresh: {
        Args: { p_driver: string; p_event?: string }
        Returns: string
      }
      admin_freeze_user: {
        Args: {
          _expires_at?: string
          _freeze_type?: string
          _reason: string
          _target: string
        }
        Returns: Json
      }
      admin_generate_payout_statement: {
        Args: {
          p_from: string
          p_group: string
          p_notes?: string
          p_to: string
        }
        Returns: string
      }
      admin_get_driver_application_detail: {
        Args: { p_user_id: string }
        Returns: Json
      }
      admin_group_risk_scorecard: {
        Args: never
        Returns: {
          commissions_held: number
          group_id: string
          group_name: string
          last_review_at: string
          referrals_count: number
          risk_held: number
          risk_review: number
        }[]
      }
      admin_group_scorecard: {
        Args: { p_days?: number; p_group: string }
        Returns: Json
      }
      admin_incentive_suggestions: {
        Args: never
        Returns: {
          kind: string
          message: string
          severity: string
          signal: Json
          target_group: string
          target_zone: string
        }[]
      }
      admin_list_driver_applications: {
        Args: { p_status?: string }
        Returns: {
          application_decision: string
          application_id: string
          decision_reason: string
          display_name: string
          driver_created_at: string
          email: string
          has_id_doc: boolean
          has_selfie: boolean
          has_vehicle_photo: boolean
          is_complete: boolean
          missing_required: string[]
          phone: string
          plate_number: string
          rejected_reason: string
          status: string
          submitted_at: string
          suspended_reason: string
          user_id: string
          vehicle_type: string
          zones: string[]
        }[]
      }
      admin_list_field_checkins: {
        Args: { p_group?: string; p_limit?: number }
        Returns: {
          accuracy_m: number | null
          checkin_type: string
          created_at: string
          created_by: string
          driver_user_id: string | null
          group_id: string
          id: string
          lat: number | null
          leader_user_id: string | null
          lng: number | null
          metadata: Json
          notes: string | null
          photo_url: string | null
          zone_id: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "driver_group_field_checkins"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      admin_log_test_delete: {
        Args: { _caller: string; _reason: string; _target: string }
        Returns: undefined
      }
      admin_mark_om_conflict: {
        Args: { p_event_id: string; p_reason: string }
        Returns: undefined
      }
      admin_mark_referral: {
        Args: { p_action: string; p_referral: string }
        Returns: undefined
      }
      admin_merchant_decision: {
        Args: { _decision: string; _reason?: string; _store_id: string }
        Returns: {
          address_label: string | null
          approved_at: string | null
          approved_by: string | null
          avatar_url: string | null
          bio: string | null
          business_name: string | null
          business_type: string | null
          category: string | null
          choppay_enabled: boolean
          cover_url: string | null
          created_at: string
          created_by: string | null
          delivery_available: boolean
          district: string | null
          id: string
          id_photo_path: string | null
          landmark: string | null
          latitude: number | null
          location_accuracy_m: number | null
          location_confirmed_at: string | null
          location_source: string | null
          longitude: number | null
          market_id: string | null
          member_since: string
          name: string
          onboarding_status: string
          operating_hours: string | null
          owner_name: string | null
          owner_user_id: string
          phone: string | null
          rejection_reason: string | null
          selfie_photo_path: string | null
          slug: string
          stall_number: string | null
          status: string
          storefront_photo_path: string | null
          submitted_at: string | null
          updated_at: string
          verification_state: string
          whatsapp: string | null
        }
        SetofOptions: {
          from: "*"
          to: "merchant_stores"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_pre_purge_test_user: { Args: { _target: string }; Returns: Json }
      admin_record_om_receipt: {
        Args: {
          p_amount_gnf: number
          p_note?: string
          p_payer_phone?: string
          p_provider_transaction_id: string
          p_receiving_account_id?: string
        }
        Returns: Json
      }
      admin_regenerate_group_referral_code: {
        Args: { p_code?: string; p_group: string }
        Returns: string
      }
      admin_remove_driver_from_group: {
        Args: { p_membership: string; p_reason?: string }
        Returns: undefined
      }
      admin_request_driver_info: {
        Args: { p_missing: string[]; p_note: string; p_user_id: string }
        Returns: undefined
      }
      admin_retry_om_credit: { Args: { p_event_id: string }; Returns: Json }
      admin_review_commission: {
        Args: { p_action: string; p_commission: string; p_notes?: string }
        Returns: undefined
      }
      admin_review_commission_risk: {
        Args: { p_action: string; p_commission: string; p_reason?: string }
        Returns: undefined
      }
      admin_review_referral_risk: {
        Args: { p_action: string; p_reason?: string; p_referral: string }
        Returns: undefined
      }
      admin_set_statement_status: {
        Args: { p_notes?: string; p_statement: string; p_status: string }
        Returns: undefined
      }
      admin_unban_user:
        | {
            Args: { _ban_id?: string; _lift_reason?: string; _target?: string }
            Returns: Json
          }
        | { Args: { _lift_reason: string; _target: string }; Returns: Json }
      admin_unfreeze_user: {
        Args: { _freeze_id?: string; _lift_reason?: string; _target?: string }
        Returns: Json
      }
      admin_update_campaign: {
        Args: { p_campaign: string; payload: Json }
        Returns: undefined
      }
      admin_update_contract: {
        Args: { p_contract: string; payload: Json }
        Returns: undefined
      }
      admin_update_driver_group: {
        Args: { p_group: string; payload: Json }
        Returns: undefined
      }
      admin_zone_coverage_stats: {
        Args: never
        Returns: {
          active_drivers_count: number
          drivers_count: number
          groups_count: number
          zone_id: string
          zone_label: string
        }[]
      }
      analytics_summary: { Args: { p_days?: number }; Returns: Json }
      analyze_route_learning_v1: {
        Args: { p_window_days?: number }
        Returns: {
          processed_summaries: number
          upserted_segments: number
        }[]
      }
      can_access_admin: { Args: { _user_id: string }; Returns: boolean }
      can_manage_operations: { Args: { _user_id: string }; Returns: boolean }
      can_manage_wallet: { Args: { _user_id: string }; Returns: boolean }
      cancel_payment_intent: {
        Args: { p_intent_id: string; p_reason?: string }
        Returns: {
          amount_gnf: number
          created_at: string
          currency: string
          id: string
          internal_reference: string
          metadata: Json
          provider: Database["public"]["Enums"]["payment_provider"]
          provider_reference: string | null
          purpose: Database["public"]["Enums"]["payment_purpose"]
          related_listing_id: string | null
          related_mission_id: string | null
          related_order_id: string | null
          related_store_id: string | null
          state: Database["public"]["Enums"]["payment_state"]
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "payment_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      check_signup_allowed: {
        Args: { _email: string; _phone: string }
        Returns: Json
      }
      claim_first_admin: { Args: never; Returns: boolean }
      confirm_payment_intent: {
        Args: {
          p_intent_id: string
          p_note?: string
          p_provider_reference?: string
        }
        Returns: {
          amount_gnf: number
          created_at: string
          currency: string
          id: string
          internal_reference: string
          metadata: Json
          provider: Database["public"]["Enums"]["payment_provider"]
          provider_reference: string | null
          purpose: Database["public"]["Enums"]["payment_purpose"]
          related_listing_id: string | null
          related_mission_id: string | null
          related_order_id: string | null
          related_store_id: string | null
          state: Database["public"]["Enums"]["payment_state"]
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "payment_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_marketplace_offer: {
        Args: { p_amount_gnf: number; p_listing_id: string; p_message?: string }
        Returns: string
      }
      current_admin_role: {
        Args: { _user_id: string }
        Returns: Database["public"]["Enums"]["admin_role"]
      }
      current_freeze: {
        Args: { _user?: string }
        Returns: {
          expires_at: string
          freeze_type: string
          frozen_at: string
          id: string
          reason: string
          user_id: string
        }[]
      }
      debug_create_offer_for_current_driver: { Args: never; Returns: Json }
      delete_email: {
        Args: { message_id: number; queue_name: string }
        Returns: boolean
      }
      demo_link_ride: { Args: { p_ride_id: string }; Returns: string }
      demo_reset_driver: { Args: never; Returns: Json }
      demo_seed_ride_offer: { Args: never; Returns: Json }
      driver_admin_decide: {
        Args: { p_decision: string; p_reason?: string; p_user_id: string }
        Returns: {
          accept_rate: number
          approved_at: string | null
          approved_by: string | null
          capabilities: string[]
          cash_debt_gnf: number
          created_at: string
          current_operating_district: string | null
          debt_limit_gnf: number
          driver_photo_url: string | null
          id_doc_url: string | null
          last_seen_at: string | null
          last_seen_district: string | null
          plate_number: string | null
          preferred_district: string | null
          presence: Database["public"]["Enums"]["driver_presence"]
          rating: number
          rejected_reason: string | null
          status: Database["public"]["Enums"]["driver_status"]
          suspended_reason: string | null
          updated_at: string
          user_id: string
          vehicle_photo_url: string | null
          vehicle_type: Database["public"]["Enums"]["driver_vehicle_type"]
          zones: string[]
        }
        SetofOptions: {
          from: "*"
          to: "driver_profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      driver_apply: {
        Args: { p_payload: Json }
        Returns: {
          created_at: string
          decided_at: string | null
          decided_by: string | null
          decision: Database["public"]["Enums"]["driver_application_decision"]
          decision_reason: string | null
          id: string
          payload: Json
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "driver_applications"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      driver_cash_settle: {
        Args: {
          p_amount_gnf: number
          p_driver_user_id: string
          p_note?: string
        }
        Returns: {
          cash_collected_gnf: number
          commission_owed_gnf: number
          created_at: string
          driver_id: string
          id: string
          note: string | null
          ride_id: string | null
          settled_amount_gnf: number
          settled_at: string | null
        }
        SetofOptions: {
          from: "*"
          to: "driver_cash_ledger"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      driver_has_capability: {
        Args: { _capability: string; _user_id: string }
        Returns: boolean
      }
      driver_offer_accept: {
        Args: { p_offer_id: string }
        Returns: {
          decline_reason: string | null
          destination_zone: string | null
          distance_to_pickup_m: number | null
          driver_id: string
          estimated_earning_gnf: number | null
          estimated_fare_gnf: number | null
          expires_at: string
          id: string
          pickup_zone: string | null
          responded_at: string | null
          ride_id: string
          sent_at: string
          status: Database["public"]["Enums"]["ride_offer_status"]
        }
        SetofOptions: {
          from: "*"
          to: "ride_offers"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      driver_offer_decline: {
        Args: { p_offer_id: string; p_reason?: string }
        Returns: {
          decline_reason: string | null
          destination_zone: string | null
          distance_to_pickup_m: number | null
          driver_id: string
          estimated_earning_gnf: number | null
          estimated_fare_gnf: number | null
          expires_at: string
          id: string
          pickup_zone: string | null
          responded_at: string | null
          ride_id: string
          sent_at: string
          status: Database["public"]["Enums"]["ride_offer_status"]
        }
        SetofOptions: {
          from: "*"
          to: "ride_offers"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      driver_set_capabilities: {
        Args: { _caps: string[] }
        Returns: {
          accept_rate: number
          approved_at: string | null
          approved_by: string | null
          capabilities: string[]
          cash_debt_gnf: number
          created_at: string
          current_operating_district: string | null
          debt_limit_gnf: number
          driver_photo_url: string | null
          id_doc_url: string | null
          last_seen_at: string | null
          last_seen_district: string | null
          plate_number: string | null
          preferred_district: string | null
          presence: Database["public"]["Enums"]["driver_presence"]
          rating: number
          rejected_reason: string | null
          status: Database["public"]["Enums"]["driver_status"]
          suspended_reason: string | null
          updated_at: string
          user_id: string
          vehicle_photo_url: string | null
          vehicle_type: Database["public"]["Enums"]["driver_vehicle_type"]
          zones: string[]
        }
        SetofOptions: {
          from: "*"
          to: "driver_profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      driver_set_status: {
        Args: { p_status: Database["public"]["Enums"]["driver_presence"] }
        Returns: {
          accept_rate: number
          approved_at: string | null
          approved_by: string | null
          capabilities: string[]
          cash_debt_gnf: number
          created_at: string
          current_operating_district: string | null
          debt_limit_gnf: number
          driver_photo_url: string | null
          id_doc_url: string | null
          last_seen_at: string | null
          last_seen_district: string | null
          plate_number: string | null
          preferred_district: string | null
          presence: Database["public"]["Enums"]["driver_presence"]
          rating: number
          rejected_reason: string | null
          status: Database["public"]["Enums"]["driver_status"]
          suspended_reason: string | null
          updated_at: string
          user_id: string
          vehicle_photo_url: string | null
          vehicle_type: Database["public"]["Enums"]["driver_vehicle_type"]
          zones: string[]
        }
        SetofOptions: {
          from: "*"
          to: "driver_profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      enqueue_email: {
        Args: { payload: Json; queue_name: string }
        Returns: number
      }
      fail_payment_intent: {
        Args: { p_intent_id: string; p_reason?: string }
        Returns: {
          amount_gnf: number
          created_at: string
          currency: string
          id: string
          internal_reference: string
          metadata: Json
          provider: Database["public"]["Enums"]["payment_provider"]
          provider_reference: string | null
          purpose: Database["public"]["Enums"]["payment_purpose"]
          related_listing_id: string | null
          related_mission_id: string | null
          related_order_id: string | null
          related_store_id: string | null
          state: Database["public"]["Enums"]["payment_state"]
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "payment_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      find_user_by_phone: {
        Args: { p_phone: string }
        Returns: {
          full_name: string
          user_id: string
        }[]
      }
      gen_topup_reference: { Args: never; Returns: string }
      get_active_payment_receiving_accounts: {
        Args: never
        Returns: {
          id: string
          label: string
          phone_e164: string
          provider: string
          public_instructions: string
        }[]
      }
      get_demo_driver: { Args: never; Returns: string }
      get_listing_minimum_price: {
        Args: { p_listing_id: string }
        Returns: number
      }
      get_merchant_listing_full: {
        Args: { p_listing_id: string }
        Returns: {
          allow_offers: boolean
          asking_price_gnf: number | null
          availability: Database["public"]["Enums"]["listing_availability"]
          barcode: string | null
          category: string
          commune: string | null
          condition: string | null
          created_at: string
          delivery_available: boolean
          description: string | null
          fulfillment_options: string[]
          id: string
          is_negotiable: boolean
          is_urgent: boolean
          kind: Database["public"]["Enums"]["listing_kind"]
          landmark: string | null
          minimum_price_gnf: number | null
          neighborhood: string | null
          offer_increment_gnf: number | null
          photo_count: number
          price_gnf: number | null
          pricing_mode: string
          promoted: boolean
          quantity_in_stock: number | null
          seller_id: string
          sold_count: number
          status: Database["public"]["Enums"]["listing_status"]
          store_id: string | null
          title: string
          updated_at: string
          view_count: number
          visibility: string
        }
        SetofOptions: {
          from: "*"
          to: "marketplace_listings"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      get_my_driver_application_status: {
        Args: never
        Returns: {
          created_at: string
          decided_at: string
          decision: Database["public"]["Enums"]["driver_application_decision"]
          decision_reason: string
          id: string
        }[]
      }
      get_my_pending_topup: {
        Args: never
        Returns: {
          amount_gnf: number
          confirmation_code: string
          expires_at: string
          id: string
          reference: string
        }[]
      }
      get_my_topup_om_status: {
        Args: { p_topup_id: string }
        Returns: {
          amount_gnf: number
          customer_om_code_submitted_at: string
          expires_at: string
          id: string
          provider: string
          receiving_instructions: string
          receiving_label: string
          receiving_phone: string
          reference: string
          status: string
        }[]
      }
      get_nearby_available_drivers: {
        Args: {
          p_lat: number
          p_limit?: number
          p_lng: number
          p_radius_m?: number
          p_vehicle_type?: string
        }
        Returns: {
          approx_lat: number
          approx_lng: number
          distance_m: number
          driver_ref: string
          heading: number
          last_seen_at: string
          vehicle_type: string
        }[]
      }
      has_admin_role: {
        Args: {
          _role: Database["public"]["Enums"]["admin_role"]
          _user_id: string
        }
        Returns: boolean
      }
      has_app_role: {
        Args: { _role: string; _user_id: string }
        Returns: boolean
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      is_admin: { Args: { _user_id: string }; Returns: boolean }
      is_any_admin: { Args: { _user_id: string }; Returns: boolean }
      is_god_admin: { Args: { _user_id: string }; Returns: boolean }
      is_user_banned: { Args: { _user: string }; Returns: boolean }
      is_user_frozen: { Args: { _user: string }; Returns: boolean }
      leader_create_field_checkin: { Args: { payload: Json }; Returns: string }
      leader_get_my_group: {
        Args: never
        Returns: {
          assigned_zone_ids: string[]
          assigned_zones: string[]
          commission_percent: number
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          leader_name: string | null
          leader_phone: string | null
          leader_user_id: string | null
          name: string
          notes: string | null
          referral_code: string | null
          signup_bonus_gnf: number
          status: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "driver_groups"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      leader_get_my_scorecard: { Args: { p_days?: number }; Returns: Json }
      leader_get_my_stats: {
        Args: { p_from?: string; p_to?: string }
        Returns: {
          active_drivers: number
          commissions_paid_gnf: number
          commissions_pending_gnf: number
          gross_driver_earnings_gnf: number
          group_id: string
          rides_completed: number
          signup_bonus_eligible_count: number
          signup_bonus_paid_gnf: number
        }[]
      }
      leader_list_my_campaigns: {
        Args: never
        Returns: {
          created_at: string
          created_by: string | null
          description: string | null
          end_date: string | null
          group_id: string
          id: string
          leader_user_id: string | null
          milestone_rule: string
          name: string
          notes: string | null
          signup_bonus_gnf: number
          start_date: string | null
          status: string
          target_active_driver_count: number
          target_completed_rides: number
          target_driver_count: number
          updated_at: string
          zone_ids: string[]
        }[]
        SetofOptions: {
          from: "*"
          to: "driver_recruitment_campaigns"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      leader_list_my_checkins: {
        Args: { p_limit?: number }
        Returns: {
          accuracy_m: number | null
          checkin_type: string
          created_at: string
          created_by: string
          driver_user_id: string | null
          group_id: string
          id: string
          lat: number | null
          leader_user_id: string | null
          lng: number | null
          metadata: Json
          notes: string | null
          photo_url: string | null
          zone_id: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "driver_group_field_checkins"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      leader_list_my_commissions: {
        Args: { p_status?: string }
        Returns: {
          approved_at: string | null
          commission_amount_gnf: number
          commission_percent: number
          created_at: string
          driver_user_id: string
          gross_driver_earning_gnf: number
          group_id: string
          id: string
          leader_user_id: string | null
          notes: string | null
          paid_at: string | null
          risk_reason: string | null
          risk_status: string
          source_id: string | null
          source_type: string
          status: string
          updated_at: string
          wallet_transaction_id: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "driver_group_commissions"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      leader_list_my_contracts: {
        Args: never
        Returns: {
          bonus_pool_gnf: number | null
          commission_percent_override: number | null
          created_at: string
          created_by: string | null
          group_id: string
          id: string
          leader_user_id: string | null
          name: string
          notes: string | null
          period_end: string | null
          period_start: string | null
          status: string
          target_active_driver_count: number
          target_completed_rides: number
          target_driver_count: number
          target_gross_earnings_gnf: number
          target_zone_ids: string[]
          terms: string | null
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "driver_group_contracts"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      leader_list_my_members: {
        Args: never
        Returns: {
          assigned_zone: string
          driver_display: string
          driver_phone_last4: string
          driver_user_id: string
          id: string
          joined_at: string
          status: string
        }[]
      }
      leader_list_my_referrals: {
        Args: { p_status?: string }
        Returns: {
          approved_at: string | null
          bonus_amount_gnf: number
          campaign_id: string | null
          created_at: string
          eligible_at: string | null
          first_ride_completed_at: string | null
          group_id: string | null
          id: string
          metadata: Json
          milestone_met_at: string | null
          milestone_rule: string
          milestone_status: string
          paid_at: string | null
          referral_code: string | null
          referred_driver_user_id: string
          referrer_user_id: string | null
          rides_completed_count: number
          risk_reason: string | null
          risk_score: number
          risk_status: string
          status: string
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "driver_referrals"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      leader_list_my_statements: {
        Args: never
        Returns: {
          adjustments_total_gnf: number
          commissions_total_gnf: number
          finalized_at: string | null
          finalized_by: string | null
          generated_at: string
          generated_by: string | null
          group_id: string
          id: string
          leader_user_id: string | null
          notes: string | null
          paid_at: string | null
          paid_by: string | null
          period_end: string
          period_start: string
          signup_bonuses_total_gnf: number
          status: string
          total_due_gnf: number
          void_reason: string | null
          voided_by: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "driver_group_payout_statements"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      list_my_topup_requests: {
        Args: { p_limit?: number }
        Returns: {
          amount_gnf: number
          cancelled_reason: string
          confirmed_at: string
          created_at: string
          customer_code_submitted_at: string
          expires_at: string
          id: string
          provider: string
          receiving_label: string
          receiving_phone: string
          reference: string
          status: string
          updated_at: string
        }[]
      }
      log_admin_action: {
        Args: {
          _action: string
          _after?: Json
          _before?: Json
          _module: string
          _note?: string
          _target_id?: string
          _target_type?: string
        }
        Returns: string
      }
      marche_increment_listing_metric: {
        Args: { _kind: string; _listing_id: string }
        Returns: undefined
      }
      marche_toggle_listing_save: {
        Args: { _listing_id: string }
        Returns: boolean
      }
      merchant_ensure_wallet: {
        Args: { p_merchant_id: string }
        Returns: string
      }
      merchant_respond_marketplace_offer: {
        Args: {
          p_action: string
          p_counter_amount_gnf?: number
          p_message?: string
          p_offer_id: string
        }
        Returns: undefined
      }
      mission_claim: {
        Args: { _mission_id: string }
        Returns: {
          courier_id: string | null
          created_at: string
          customer_id: string
          dropoff_address: string | null
          dropoff_confirmed_at: string | null
          dropoff_confirmed_by: string | null
          dropoff_lat: number | null
          dropoff_lng: number | null
          estimated_distance_m: number | null
          estimated_duration_s: number | null
          estimated_earning_gnf: number
          id: string
          issue_district: string | null
          issue_hub_id: string | null
          issue_reason: string | null
          merchant_id: string | null
          payload_summary: string | null
          pickup_address: string | null
          pickup_confirmed_at: string | null
          pickup_confirmed_by: string | null
          pickup_lat: number | null
          pickup_lng: number | null
          ref_food_order_id: string | null
          ref_market_order_id: string | null
          ref_ride_id: string | null
          state: Database["public"]["Enums"]["mission_state"]
          type: Database["public"]["Enums"]["mission_type"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "missions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      mission_confirm_dropoff: {
        Args: { _mission_id: string }
        Returns: {
          courier_id: string | null
          created_at: string
          customer_id: string
          dropoff_address: string | null
          dropoff_confirmed_at: string | null
          dropoff_confirmed_by: string | null
          dropoff_lat: number | null
          dropoff_lng: number | null
          estimated_distance_m: number | null
          estimated_duration_s: number | null
          estimated_earning_gnf: number
          id: string
          issue_district: string | null
          issue_hub_id: string | null
          issue_reason: string | null
          merchant_id: string | null
          payload_summary: string | null
          pickup_address: string | null
          pickup_confirmed_at: string | null
          pickup_confirmed_by: string | null
          pickup_lat: number | null
          pickup_lng: number | null
          ref_food_order_id: string | null
          ref_market_order_id: string | null
          ref_ride_id: string | null
          state: Database["public"]["Enums"]["mission_state"]
          type: Database["public"]["Enums"]["mission_type"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "missions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      mission_confirm_pickup: {
        Args: { _mission_id: string }
        Returns: {
          courier_id: string | null
          created_at: string
          customer_id: string
          dropoff_address: string | null
          dropoff_confirmed_at: string | null
          dropoff_confirmed_by: string | null
          dropoff_lat: number | null
          dropoff_lng: number | null
          estimated_distance_m: number | null
          estimated_duration_s: number | null
          estimated_earning_gnf: number
          id: string
          issue_district: string | null
          issue_hub_id: string | null
          issue_reason: string | null
          merchant_id: string | null
          payload_summary: string | null
          pickup_address: string | null
          pickup_confirmed_at: string | null
          pickup_confirmed_by: string | null
          pickup_lat: number | null
          pickup_lng: number | null
          ref_food_order_id: string | null
          ref_market_order_id: string | null
          ref_ride_id: string | null
          state: Database["public"]["Enums"]["mission_state"]
          type: Database["public"]["Enums"]["mission_type"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "missions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      mission_report_issue: {
        Args: {
          _district?: string
          _hub_id?: string
          _mission_id: string
          _reason: string
        }
        Returns: {
          courier_id: string | null
          created_at: string
          customer_id: string
          dropoff_address: string | null
          dropoff_confirmed_at: string | null
          dropoff_confirmed_by: string | null
          dropoff_lat: number | null
          dropoff_lng: number | null
          estimated_distance_m: number | null
          estimated_duration_s: number | null
          estimated_earning_gnf: number
          id: string
          issue_district: string | null
          issue_hub_id: string | null
          issue_reason: string | null
          merchant_id: string | null
          payload_summary: string | null
          pickup_address: string | null
          pickup_confirmed_at: string | null
          pickup_confirmed_by: string | null
          pickup_lat: number | null
          pickup_lng: number | null
          ref_food_order_id: string | null
          ref_market_order_id: string | null
          ref_ride_id: string | null
          state: Database["public"]["Enums"]["mission_state"]
          type: Database["public"]["Enums"]["mission_type"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "missions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      mission_required_capability: {
        Args: { _type: Database["public"]["Enums"]["mission_type"] }
        Returns: string
      }
      mission_set_state: {
        Args: {
          _mission_id: string
          _state: Database["public"]["Enums"]["mission_state"]
        }
        Returns: {
          courier_id: string | null
          created_at: string
          customer_id: string
          dropoff_address: string | null
          dropoff_confirmed_at: string | null
          dropoff_confirmed_by: string | null
          dropoff_lat: number | null
          dropoff_lng: number | null
          estimated_distance_m: number | null
          estimated_duration_s: number | null
          estimated_earning_gnf: number
          id: string
          issue_district: string | null
          issue_hub_id: string | null
          issue_reason: string | null
          merchant_id: string | null
          payload_summary: string | null
          pickup_address: string | null
          pickup_confirmed_at: string | null
          pickup_confirmed_by: string | null
          pickup_lat: number | null
          pickup_lng: number | null
          ref_food_order_id: string | null
          ref_market_order_id: string | null
          ref_ride_id: string | null
          state: Database["public"]["Enums"]["mission_state"]
          type: Database["public"]["Enums"]["mission_type"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "missions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      move_to_dlq: {
        Args: {
          dlq_name: string
          message_id: number
          payload: Json
          source_queue: string
        }
        Returns: number
      }
      next_wongo_reference: { Args: never; Returns: string }
      normalize_om_code: { Args: { p_code: string }; Returns: string }
      om_auto_match: { Args: { p_event_id: string }; Returns: Json }
      om_pending_topups_for_event: {
        Args: { p_event_id: string }
        Returns: {
          amount_gnf: number
          amount_match: boolean
          client_name: string
          client_phone: string
          client_user_id: string
          created_at: string
          expires_at: string
          phone_match: boolean
          reference: string
          status: string
          topup_id: string
        }[]
      }
      process_driver_referral_milestone_jobs: {
        Args: { p_limit?: number }
        Returns: {
          eligible: number
          failed: number
          processed: number
        }[]
      }
      process_driver_referral_milestone_jobs_cron: {
        Args: { p_limit?: number }
        Returns: {
          eligible: number
          error: string | null
          failed: number
          id: string
          processed: number
          ran_at: string
          source: string
        }
        SetofOptions: {
          from: "*"
          to: "driver_referral_milestone_job_runs"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      read_email_batch: {
        Args: { batch_size: number; queue_name: string; vt: number }
        Returns: {
          message: Json
          msg_id: number
          read_ct: number
        }[]
      }
      refresh_driver_referral_milestones: {
        Args: { p_driver?: string }
        Returns: number
      }
      request_account_deletion: { Args: { _reason?: string }; Returns: Json }
      review_learned_route_segment: {
        Args: { p_id: number; p_notes?: string; p_status: string }
        Returns: boolean
      }
      ride_accept: {
        Args: { p_ride_id: string }
        Returns: {
          client_id: string
          completed_at: string | null
          created_at: string
          dest_lat: number | null
          dest_lng: number | null
          driver_earning_gnf: number
          driver_id: string | null
          fare_gnf: number
          hold_tx_id: string | null
          id: string
          metadata: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf: number
          status: Database["public"]["Enums"]["ride_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "rides"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ride_cancel: {
        Args: { p_reason?: string; p_ride_id: string }
        Returns: {
          client_id: string
          completed_at: string | null
          created_at: string
          dest_lat: number | null
          dest_lng: number | null
          driver_earning_gnf: number
          driver_id: string | null
          fare_gnf: number
          hold_tx_id: string | null
          id: string
          metadata: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf: number
          status: Database["public"]["Enums"]["ride_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "rides"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ride_complete: {
        Args: {
          p_actual_fare_gnf?: number
          p_commission_bps?: number
          p_ride_id: string
        }
        Returns: {
          client_id: string
          completed_at: string | null
          created_at: string
          dest_lat: number | null
          dest_lng: number | null
          driver_earning_gnf: number
          driver_id: string | null
          fare_gnf: number
          hold_tx_id: string | null
          id: string
          metadata: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf: number
          status: Database["public"]["Enums"]["ride_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "rides"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ride_confirm_pickup: {
        Args: { p_code: string; p_ride_id: string }
        Returns: {
          client_id: string
          completed_at: string | null
          created_at: string
          dest_lat: number | null
          dest_lng: number | null
          driver_earning_gnf: number
          driver_id: string | null
          fare_gnf: number
          hold_tx_id: string | null
          id: string
          metadata: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf: number
          status: Database["public"]["Enums"]["ride_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "rides"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ride_create: {
        Args: {
          p_dest_lat: number
          p_dest_lng: number
          p_driver_id?: string
          p_fare_gnf: number
          p_hold_tx_id: string
          p_mode: Database["public"]["Enums"]["ride_mode"]
          p_pickup_lat: number
          p_pickup_lng: number
        }
        Returns: {
          client_id: string
          completed_at: string | null
          created_at: string
          dest_lat: number | null
          dest_lng: number | null
          driver_earning_gnf: number
          driver_id: string | null
          fare_gnf: number
          hold_tx_id: string | null
          id: string
          metadata: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf: number
          status: Database["public"]["Enums"]["ride_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "rides"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ride_dispatch: { Args: { p_ride_id: string }; Returns: string }
      ride_integrity_check: { Args: { p_ride_id: string }; Returns: Json }
      ride_rate: {
        Args: {
          p_comment?: string
          p_direction?: Database["public"]["Enums"]["rating_direction"]
          p_ride_id: string
          p_score: number
        }
        Returns: string
      }
      ride_set_phase: {
        Args: { p_phase: string; p_ride_id: string }
        Returns: {
          client_id: string
          completed_at: string | null
          created_at: string
          dest_lat: number | null
          dest_lng: number | null
          driver_earning_gnf: number
          driver_id: string | null
          fare_gnf: number
          hold_tx_id: string | null
          id: string
          metadata: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf: number
          status: Database["public"]["Enums"]["ride_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "rides"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ride_start: {
        Args: { p_ride_id: string }
        Returns: {
          client_id: string
          completed_at: string | null
          created_at: string
          dest_lat: number | null
          dest_lng: number | null
          driver_earning_gnf: number
          driver_id: string | null
          fare_gnf: number
          hold_tx_id: string | null
          id: string
          metadata: Json | null
          mode: Database["public"]["Enums"]["ride_mode"]
          payment_tx_id: string | null
          pickup_lat: number
          pickup_lng: number
          platform_fee_gnf: number
          status: Database["public"]["Enums"]["ride_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "rides"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      score_driver_referral_risk: {
        Args: { p_referral: string }
        Returns: {
          reason: string
          score: number
          status: string
        }[]
      }
      score_driver_referral_risk_v2: {
        Args: { p_referral: string }
        Returns: {
          level: string
          reason_codes: string[]
          score: number
        }[]
      }
      set_primary_listing_image: {
        Args: { p_image_id: string }
        Returns: undefined
      }
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
      submit_customer_om_code: {
        Args: { p_om_code: string; p_topup_request_id: string }
        Returns: Json
      }
      user_has_financial_history: {
        Args: { _user_id: string }
        Returns: boolean
      }
      user_has_pin: {
        Args: never
        Returns: {
          has_pin: boolean
          updated_at: string
        }[]
      }
      validate_referral_code: {
        Args: { p_code: string }
        Returns: {
          group_id: string
          group_name: string
          leader_name: string
          status: string
          valid: boolean
        }[]
      }
      wallet_admin_credit: {
        Args: {
          p_amount_gnf: number
          p_provider_tx_id?: string
          p_reason: string
          p_user_id: string
        }
        Returns: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        SetofOptions: {
          from: "*"
          to: "wallet_transactions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_capture: {
        Args: {
          p_actual_amount_gnf?: number
          p_description?: string
          p_hold_id: string
          p_to_party_type?: Database["public"]["Enums"]["party_type"]
          p_to_user_id?: string
        }
        Returns: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        SetofOptions: {
          from: "*"
          to: "wallet_transactions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_ensure: { Args: { _party_type?: string }; Returns: string }
      wallet_hold: {
        Args: {
          p_amount_gnf: number
          p_description?: string
          p_reference?: string
        }
        Returns: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        SetofOptions: {
          from: "*"
          to: "wallet_transactions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_internal_transfer: {
        Args: {
          p_amount_gnf: number
          p_description: string
          p_from_party_type: string
          p_from_user_id: string
          p_to_party_type: string
          p_to_user_id: string
        }
        Returns: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        SetofOptions: {
          from: "*"
          to: "wallet_transactions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_pay_driver_commission: {
        Args: { p_commission_id: string }
        Returns: string
      }
      wallet_pay_driver_commission_batch: {
        Args: { p_commission_ids: string[] }
        Returns: Json
      }
      wallet_pay_merchant: {
        Args: {
          p_amount_gnf: number
          p_description?: string
          p_merchant_id: string
        }
        Returns: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        SetofOptions: {
          from: "*"
          to: "wallet_transactions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_release: {
        Args: { p_hold_id: string; p_reason?: string }
        Returns: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        SetofOptions: {
          from: "*"
          to: "wallet_transactions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_reverse_driver_commission: {
        Args: { p_commission_id: string; p_reason: string }
        Returns: string
      }
      wallet_topup_admin_cancel: {
        Args: { p_reason?: string; p_topup_id: string }
        Returns: {
          agent_user_id: string | null
          amount_gnf: number
          cancelled_reason: string | null
          client_user_id: string
          confirmation_code: string
          confirmed_at: string | null
          created_at: string
          customer_om_code_normalized: string | null
          customer_om_code_raw: string | null
          customer_om_code_submitted_at: string | null
          expires_at: string
          id: string
          matched_provider_transaction_id: string | null
          notes: string | null
          provider: string
          receiving_account_id: string | null
          reference: string
          status: Database["public"]["Enums"]["topup_status"]
          transaction_id: string | null
          updated_at: string
          user_phone: string | null
        }
        SetofOptions: {
          from: "*"
          to: "topup_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_topup_admin_mark_expired: {
        Args: { p_reason?: string; p_topup_id: string }
        Returns: {
          agent_user_id: string | null
          amount_gnf: number
          cancelled_reason: string | null
          client_user_id: string
          confirmation_code: string
          confirmed_at: string | null
          created_at: string
          customer_om_code_normalized: string | null
          customer_om_code_raw: string | null
          customer_om_code_submitted_at: string | null
          expires_at: string
          id: string
          matched_provider_transaction_id: string | null
          notes: string | null
          provider: string
          receiving_account_id: string | null
          reference: string
          status: Database["public"]["Enums"]["topup_status"]
          transaction_id: string | null
          updated_at: string
          user_phone: string | null
        }
        SetofOptions: {
          from: "*"
          to: "topup_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_topup_cancel: {
        Args: { p_reason?: string; p_topup_id: string }
        Returns: {
          agent_user_id: string | null
          amount_gnf: number
          cancelled_reason: string | null
          client_user_id: string
          confirmation_code: string
          confirmed_at: string | null
          created_at: string
          customer_om_code_normalized: string | null
          customer_om_code_raw: string | null
          customer_om_code_submitted_at: string | null
          expires_at: string
          id: string
          matched_provider_transaction_id: string | null
          notes: string | null
          provider: string
          receiving_account_id: string | null
          reference: string
          status: Database["public"]["Enums"]["topup_status"]
          transaction_id: string | null
          updated_at: string
          user_phone: string | null
        }
        SetofOptions: {
          from: "*"
          to: "topup_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_topup_confirm: {
        Args: { p_code: string; p_topup_id: string }
        Returns: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        SetofOptions: {
          from: "*"
          to: "wallet_transactions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_topup_create: {
        Args: { p_amount_gnf: number; p_client_user_id: string }
        Returns: {
          agent_user_id: string | null
          amount_gnf: number
          cancelled_reason: string | null
          client_user_id: string
          confirmation_code: string
          confirmed_at: string | null
          created_at: string
          customer_om_code_normalized: string | null
          customer_om_code_raw: string | null
          customer_om_code_submitted_at: string | null
          expires_at: string
          id: string
          matched_provider_transaction_id: string | null
          notes: string | null
          provider: string
          receiving_account_id: string | null
          reference: string
          status: Database["public"]["Enums"]["topup_status"]
          transaction_id: string | null
          updated_at: string
          user_phone: string | null
        }
        SetofOptions: {
          from: "*"
          to: "topup_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_topup_om_create: {
        Args: { p_amount_gnf: number; p_receiving_account_id?: string }
        Returns: {
          agent_user_id: string | null
          amount_gnf: number
          cancelled_reason: string | null
          client_user_id: string
          confirmation_code: string
          confirmed_at: string | null
          created_at: string
          customer_om_code_normalized: string | null
          customer_om_code_raw: string | null
          customer_om_code_submitted_at: string | null
          expires_at: string
          id: string
          matched_provider_transaction_id: string | null
          notes: string | null
          provider: string
          receiving_account_id: string | null
          reference: string
          status: Database["public"]["Enums"]["topup_status"]
          transaction_id: string | null
          updated_at: string
          user_phone: string | null
        }
        SetofOptions: {
          from: "*"
          to: "topup_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      wallet_topup_om_credit: {
        Args: { p_event_id: string; p_topup_request_id: string }
        Returns: {
          amount_gnf: number
          completed_at: string | null
          created_at: string
          description: string | null
          from_wallet_id: string | null
          id: string
          metadata: Json
          reference: string
          related_entity: string | null
          related_user_id: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        SetofOptions: {
          from: "*"
          to: "wallet_transactions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      withdraw_marketplace_offer: {
        Args: { p_offer_id: string }
        Returns: undefined
      }
    }
    Enums: {
      admin_role:
        | "super_admin"
        | "ops_admin"
        | "finance_admin"
        | "god_admin"
        | "operations_admin"
        | "support_admin"
      admin_user_status: "active" | "suspended"
      ai_assistant_kind: "admin" | "support" | "marche" | "fraud"
      ai_request_status: "ok" | "error" | "rate_limited" | "blocked"
      app_role:
        | "admin"
        | "user"
        | "client"
        | "driver"
        | "merchant"
        | "agent"
        | "recharge_agent"
        | "operations_admin"
        | "finance_admin"
        | "god_admin"
        | "onboarding_specialist"
      approval_status: "pending" | "approved" | "rejected" | "cancelled"
      driver_application_decision:
        | "pending"
        | "approved"
        | "rejected"
        | "more_info"
      driver_presence: "offline" | "online" | "on_trip"
      driver_status: "pending" | "approved" | "rejected" | "suspended"
      driver_vehicle_type: "moto" | "toktok" | "livraison" | "auto"
      food_fulfillment: "pickup" | "delivery"
      food_order_state:
        | "placed"
        | "confirmed"
        | "preparing"
        | "ready"
        | "out_for_delivery"
        | "completed"
        | "cancelled"
      food_payment_method: "wallet" | "choppay" | "cash"
      insight_confidence: "low" | "medium" | "high"
      insight_section:
        | "executive"
        | "behavior"
        | "mobility"
        | "wallet"
        | "marketplace"
        | "driver"
        | "merchant"
        | "fraud"
        | "growth"
        | "recommendation"
      listing_availability:
        | "available"
        | "limited"
        | "to_confirm"
        | "reserved"
        | "sold"
      listing_interest_kind:
        | "availability"
        | "delivery"
        | "reservation"
        | "offer"
      listing_interest_state:
        | "pending"
        | "available"
        | "reserved"
        | "sold"
        | "responded"
        | "declined"
      listing_kind: "merchant" | "community" | "service"
      listing_status: "active" | "sold" | "paused" | "removed"
      message_channel: "whatsapp" | "sms" | "inapp" | "in_app"
      message_kind: "text" | "image" | "location" | "quick_reply"
      message_status:
        | "queued"
        | "sending"
        | "sent"
        | "delivered"
        | "read"
        | "failed"
      message_template:
        | "otp_code"
        | "welcome"
        | "topup_pending"
        | "topup_success"
        | "payment_success"
        | "refund"
        | "ride_confirmed"
        | "driver_assigned"
        | "delivery_completed"
        | "suspicious_activity"
      mission_state:
        | "assigned"
        | "heading_to_pickup"
        | "arrived_pickup"
        | "picked_up"
        | "heading_to_dropoff"
        | "arrived_dropoff"
        | "delivered"
        | "failed"
      mission_type:
        | "ride"
        | "food_delivery"
        | "marketplace_delivery"
        | "package_delivery"
      notification_channel: "email" | "sms" | "whatsapp" | "push" | "inapp"
      notification_priority: "critical" | "high" | "normal" | "low"
      notification_status:
        | "pending"
        | "sent"
        | "failed"
        | "suppressed"
        | "skipped"
      party_type: "client" | "driver" | "merchant" | "agent" | "master"
      payment_provider:
        | "orange_money"
        | "mtn_money"
        | "cash"
        | "manual"
        | "internal"
        | "agent"
      payment_purpose:
        | "wallet_topup"
        | "repas_payment"
        | "marche_payment"
        | "courier_payout"
        | "merchant_settlement"
        | "refund"
      payment_recon_event:
        | "intent_created"
        | "provider_pending"
        | "provider_confirmed"
        | "provider_failed"
        | "wallet_credited"
        | "payout_queued"
        | "payout_paid"
        | "refund_created"
        | "refund_completed"
      payment_state:
        | "pending"
        | "processing"
        | "confirmed"
        | "failed"
        | "cancelled"
        | "refunded"
        | "reversed"
        | "expired"
      rating_direction: "client_to_driver" | "driver_to_client"
      report_status: "open" | "reviewed" | "actioned" | "dismissed"
      ride_mode: "moto" | "toktok" | "food"
      ride_offer_status:
        | "pending"
        | "accepted"
        | "declined"
        | "missed"
        | "expired"
        | "cancelled"
      ride_status: "pending" | "in_progress" | "completed" | "cancelled"
      saved_place_kind: "home" | "work" | "favorite"
      support_issue_role:
        | "support"
        | "operations"
        | "payment"
        | "merchant"
        | "courier"
        | "admin"
      support_issue_severity: "low" | "medium" | "high" | "critical"
      support_issue_status:
        | "open"
        | "in_review"
        | "waiting_on_user"
        | "waiting_on_courier"
        | "waiting_on_merchant"
        | "resolved"
        | "escalated"
        | "cancelled"
      support_issue_type:
        | "payment_pending"
        | "payment_failed"
        | "courier_no_show"
        | "merchant_not_ready"
        | "customer_unreachable"
        | "wrong_address"
        | "package_dispute"
        | "item_not_available"
        | "delivery_failed"
        | "app_bug"
        | "account_issue"
        | "safety_concern"
        | "other"
      topup_status:
        | "pending"
        | "confirmed"
        | "expired"
        | "cancelled"
        | "matched"
        | "needs_review"
        | "credited"
        | "failed"
      txn_status: "pending" | "completed" | "failed" | "reversed" | "cancelled"
      txn_type:
        | "topup"
        | "payment"
        | "refund"
        | "commission"
        | "payout"
        | "hold"
        | "capture"
        | "release"
        | "transfer"
        | "adjustment"
      wallet_status: "active" | "frozen" | "closed"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      admin_role: [
        "super_admin",
        "ops_admin",
        "finance_admin",
        "god_admin",
        "operations_admin",
        "support_admin",
      ],
      admin_user_status: ["active", "suspended"],
      ai_assistant_kind: ["admin", "support", "marche", "fraud"],
      ai_request_status: ["ok", "error", "rate_limited", "blocked"],
      app_role: [
        "admin",
        "user",
        "client",
        "driver",
        "merchant",
        "agent",
        "recharge_agent",
        "operations_admin",
        "finance_admin",
        "god_admin",
        "onboarding_specialist",
      ],
      approval_status: ["pending", "approved", "rejected", "cancelled"],
      driver_application_decision: [
        "pending",
        "approved",
        "rejected",
        "more_info",
      ],
      driver_presence: ["offline", "online", "on_trip"],
      driver_status: ["pending", "approved", "rejected", "suspended"],
      driver_vehicle_type: ["moto", "toktok", "livraison", "auto"],
      food_fulfillment: ["pickup", "delivery"],
      food_order_state: [
        "placed",
        "confirmed",
        "preparing",
        "ready",
        "out_for_delivery",
        "completed",
        "cancelled",
      ],
      food_payment_method: ["wallet", "choppay", "cash"],
      insight_confidence: ["low", "medium", "high"],
      insight_section: [
        "executive",
        "behavior",
        "mobility",
        "wallet",
        "marketplace",
        "driver",
        "merchant",
        "fraud",
        "growth",
        "recommendation",
      ],
      listing_availability: [
        "available",
        "limited",
        "to_confirm",
        "reserved",
        "sold",
      ],
      listing_interest_kind: [
        "availability",
        "delivery",
        "reservation",
        "offer",
      ],
      listing_interest_state: [
        "pending",
        "available",
        "reserved",
        "sold",
        "responded",
        "declined",
      ],
      listing_kind: ["merchant", "community", "service"],
      listing_status: ["active", "sold", "paused", "removed"],
      message_channel: ["whatsapp", "sms", "inapp", "in_app"],
      message_kind: ["text", "image", "location", "quick_reply"],
      message_status: [
        "queued",
        "sending",
        "sent",
        "delivered",
        "read",
        "failed",
      ],
      message_template: [
        "otp_code",
        "welcome",
        "topup_pending",
        "topup_success",
        "payment_success",
        "refund",
        "ride_confirmed",
        "driver_assigned",
        "delivery_completed",
        "suspicious_activity",
      ],
      mission_state: [
        "assigned",
        "heading_to_pickup",
        "arrived_pickup",
        "picked_up",
        "heading_to_dropoff",
        "arrived_dropoff",
        "delivered",
        "failed",
      ],
      mission_type: [
        "ride",
        "food_delivery",
        "marketplace_delivery",
        "package_delivery",
      ],
      notification_channel: ["email", "sms", "whatsapp", "push", "inapp"],
      notification_priority: ["critical", "high", "normal", "low"],
      notification_status: [
        "pending",
        "sent",
        "failed",
        "suppressed",
        "skipped",
      ],
      party_type: ["client", "driver", "merchant", "agent", "master"],
      payment_provider: [
        "orange_money",
        "mtn_money",
        "cash",
        "manual",
        "internal",
        "agent",
      ],
      payment_purpose: [
        "wallet_topup",
        "repas_payment",
        "marche_payment",
        "courier_payout",
        "merchant_settlement",
        "refund",
      ],
      payment_recon_event: [
        "intent_created",
        "provider_pending",
        "provider_confirmed",
        "provider_failed",
        "wallet_credited",
        "payout_queued",
        "payout_paid",
        "refund_created",
        "refund_completed",
      ],
      payment_state: [
        "pending",
        "processing",
        "confirmed",
        "failed",
        "cancelled",
        "refunded",
        "reversed",
        "expired",
      ],
      rating_direction: ["client_to_driver", "driver_to_client"],
      report_status: ["open", "reviewed", "actioned", "dismissed"],
      ride_mode: ["moto", "toktok", "food"],
      ride_offer_status: [
        "pending",
        "accepted",
        "declined",
        "missed",
        "expired",
        "cancelled",
      ],
      ride_status: ["pending", "in_progress", "completed", "cancelled"],
      saved_place_kind: ["home", "work", "favorite"],
      support_issue_role: [
        "support",
        "operations",
        "payment",
        "merchant",
        "courier",
        "admin",
      ],
      support_issue_severity: ["low", "medium", "high", "critical"],
      support_issue_status: [
        "open",
        "in_review",
        "waiting_on_user",
        "waiting_on_courier",
        "waiting_on_merchant",
        "resolved",
        "escalated",
        "cancelled",
      ],
      support_issue_type: [
        "payment_pending",
        "payment_failed",
        "courier_no_show",
        "merchant_not_ready",
        "customer_unreachable",
        "wrong_address",
        "package_dispute",
        "item_not_available",
        "delivery_failed",
        "app_bug",
        "account_issue",
        "safety_concern",
        "other",
      ],
      topup_status: [
        "pending",
        "confirmed",
        "expired",
        "cancelled",
        "matched",
        "needs_review",
        "credited",
        "failed",
      ],
      txn_status: ["pending", "completed", "failed", "reversed", "cancelled"],
      txn_type: [
        "topup",
        "payment",
        "refund",
        "commission",
        "payout",
        "hold",
        "capture",
        "release",
        "transfer",
        "adjustment",
      ],
      wallet_status: ["active", "frozen", "closed"],
    },
  },
} as const
