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
      _qa_s13_results: {
        Row: {
          created_at: string
          id: number
          part: number
          result: Json
        }
        Insert: {
          created_at?: string
          id?: number
          part: number
          result: Json
        }
        Update: {
          created_at?: string
          id?: number
          part?: number
          result?: Json
        }
        Relationships: []
      }
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
      account_recovery_challenges: {
        Row: {
          asked_question_ids: string[]
          attempts: number
          consumed_at: string | null
          created_at: string
          expires_at: string
          id: string
          identifier_hash: string
          ip_hash: string | null
          is_decoy: boolean
          max_attempts: number
          reset_token_expires_at: string | null
          reset_token_hash: string | null
          reset_used_at: string | null
          user_id: string | null
          verified_at: string | null
        }
        Insert: {
          asked_question_ids?: string[]
          attempts?: number
          consumed_at?: string | null
          created_at?: string
          expires_at: string
          id?: string
          identifier_hash: string
          ip_hash?: string | null
          is_decoy?: boolean
          max_attempts?: number
          reset_token_expires_at?: string | null
          reset_token_hash?: string | null
          reset_used_at?: string | null
          user_id?: string | null
          verified_at?: string | null
        }
        Update: {
          asked_question_ids?: string[]
          attempts?: number
          consumed_at?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          identifier_hash?: string
          ip_hash?: string | null
          is_decoy?: boolean
          max_attempts?: number
          reset_token_expires_at?: string | null
          reset_token_hash?: string | null
          reset_used_at?: string | null
          user_id?: string | null
          verified_at?: string | null
        }
        Relationships: []
      }
      account_recovery_lockouts: {
        Row: {
          cooldown_until: string | null
          exhausted_count: number
          key_hash: string
          updated_at: string
          window_started_at: string
        }
        Insert: {
          cooldown_until?: string | null
          exhausted_count?: number
          key_hash: string
          updated_at?: string
          window_started_at?: string
        }
        Update: {
          cooldown_until?: string | null
          exhausted_count?: number
          key_hash?: string
          updated_at?: string
          window_started_at?: string
        }
        Relationships: []
      }
      account_recovery_profiles: {
        Row: {
          answer_1_hash: string
          answer_2_hash: string
          answer_3_hash: string
          birthdate_hash: string
          created_at: string
          question_1_id: string
          question_2_id: string
          question_3_id: string
          recovery_key_hash: string
          recovery_key_version: number
          rotated_at: string | null
          setup_completed_at: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          answer_1_hash: string
          answer_2_hash: string
          answer_3_hash: string
          birthdate_hash: string
          created_at?: string
          question_1_id: string
          question_2_id: string
          question_3_id: string
          recovery_key_hash: string
          recovery_key_version?: number
          rotated_at?: string | null
          setup_completed_at?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          answer_1_hash?: string
          answer_2_hash?: string
          answer_3_hash?: string
          birthdate_hash?: string
          created_at?: string
          question_1_id?: string
          question_2_id?: string
          question_3_id?: string
          recovery_key_hash?: string
          recovery_key_version?: number
          rotated_at?: string | null
          setup_completed_at?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      admin_users: {
        Row: {
          admin_role: Database["public"]["Enums"]["admin_role"]
          changed_password_at: string | null
          created_at: string
          created_by: string | null
          created_via: string | null
          id: string
          must_change_password: boolean
          notes: string | null
          status: Database["public"]["Enums"]["admin_user_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          admin_role: Database["public"]["Enums"]["admin_role"]
          changed_password_at?: string | null
          created_at?: string
          created_by?: string | null
          created_via?: string | null
          id?: string
          must_change_password?: boolean
          notes?: string | null
          status?: Database["public"]["Enums"]["admin_user_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          admin_role?: Database["public"]["Enums"]["admin_role"]
          changed_password_at?: string | null
          created_at?: string
          created_by?: string | null
          created_via?: string | null
          id?: string
          must_change_password?: boolean
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
      cash_order_runtime: {
        Row: {
          cancelled_at: string | null
          cash_collected_gnf: number | null
          cash_delivery_earning_gnf: number | null
          cash_due_gnf: number
          cash_fee_recovery_gnf: number | null
          cash_principal_recovery_gnf: number | null
          completed_at: string | null
          created_at: string
          customer_user_id: string
          delivery_fee_gnf: number
          dispute_opened_by: string | null
          dispute_reason: string | null
          dispute_resolution: Json | null
          disputed_at: string | null
          driver_user_id: string
          funded_at: string | null
          id: string
          is_sandbox: boolean
          merchandise_subtotal_gnf: number
          merchant_store_id: string | null
          merchant_user_id: string | null
          mission_id: string | null
          mission_type: string
          order_key: string
          platform_fee_gnf: number
          policy_snapshot: Json
          prep_locked_at: string | null
          resolved_at: string | null
          resolved_by: string | null
          source_id: string
          source_module: string
          state: string
          updated_at: string
        }
        Insert: {
          cancelled_at?: string | null
          cash_collected_gnf?: number | null
          cash_delivery_earning_gnf?: number | null
          cash_due_gnf: number
          cash_fee_recovery_gnf?: number | null
          cash_principal_recovery_gnf?: number | null
          completed_at?: string | null
          created_at?: string
          customer_user_id: string
          delivery_fee_gnf?: number
          dispute_opened_by?: string | null
          dispute_reason?: string | null
          dispute_resolution?: Json | null
          disputed_at?: string | null
          driver_user_id: string
          funded_at?: string | null
          id?: string
          is_sandbox?: boolean
          merchandise_subtotal_gnf: number
          merchant_store_id?: string | null
          merchant_user_id?: string | null
          mission_id?: string | null
          mission_type: string
          order_key: string
          platform_fee_gnf?: number
          policy_snapshot?: Json
          prep_locked_at?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          source_id: string
          source_module: string
          state?: string
          updated_at?: string
        }
        Update: {
          cancelled_at?: string | null
          cash_collected_gnf?: number | null
          cash_delivery_earning_gnf?: number | null
          cash_due_gnf?: number
          cash_fee_recovery_gnf?: number | null
          cash_principal_recovery_gnf?: number | null
          completed_at?: string | null
          created_at?: string
          customer_user_id?: string
          delivery_fee_gnf?: number
          dispute_opened_by?: string | null
          dispute_reason?: string | null
          dispute_resolution?: Json | null
          disputed_at?: string | null
          driver_user_id?: string
          funded_at?: string | null
          id?: string
          is_sandbox?: boolean
          merchandise_subtotal_gnf?: number
          merchant_store_id?: string | null
          merchant_user_id?: string | null
          mission_id?: string | null
          mission_type?: string
          order_key?: string
          platform_fee_gnf?: number
          policy_snapshot?: Json
          prep_locked_at?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          source_id?: string
          source_module?: string
          state?: string
          updated_at?: string
        }
        Relationships: []
      }
      chop_pay_order_runtime: {
        Row: {
          accepted_at: string | null
          authorized_at: string
          cancellation_charge_gnf: number
          cancelled_at: string | null
          collateral_gnf: number
          completed_at: string | null
          created_at: string
          customer_refunded_gnf: number
          customer_user_id: string
          delivery_fee_gnf: number
          dispute_opened_by: string | null
          dispute_reason: string | null
          dispute_resolution: Json | null
          disputed_at: string | null
          driver_earning_gnf: number
          driver_user_id: string | null
          funded_at: string | null
          id: string
          is_sandbox: boolean
          merchandise_subtotal_gnf: number
          merchant_credited_gnf: number
          merchant_store_id: string | null
          merchant_user_id: string | null
          mission_id: string | null
          mission_type: string
          order_key: string
          order_total_gnf: number
          platform_fee_gnf: number
          platform_revenue_gnf: number
          policy_snapshot: Json
          prep_locked_at: string | null
          resolved_at: string | null
          resolved_by: string | null
          source_id: string
          source_module: string
          state: string
          updated_at: string
        }
        Insert: {
          accepted_at?: string | null
          authorized_at?: string
          cancellation_charge_gnf?: number
          cancelled_at?: string | null
          collateral_gnf?: number
          completed_at?: string | null
          created_at?: string
          customer_refunded_gnf?: number
          customer_user_id: string
          delivery_fee_gnf?: number
          dispute_opened_by?: string | null
          dispute_reason?: string | null
          dispute_resolution?: Json | null
          disputed_at?: string | null
          driver_earning_gnf?: number
          driver_user_id?: string | null
          funded_at?: string | null
          id?: string
          is_sandbox?: boolean
          merchandise_subtotal_gnf: number
          merchant_credited_gnf?: number
          merchant_store_id?: string | null
          merchant_user_id?: string | null
          mission_id?: string | null
          mission_type: string
          order_key: string
          order_total_gnf: number
          platform_fee_gnf?: number
          platform_revenue_gnf?: number
          policy_snapshot?: Json
          prep_locked_at?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          source_id: string
          source_module: string
          state?: string
          updated_at?: string
        }
        Update: {
          accepted_at?: string | null
          authorized_at?: string
          cancellation_charge_gnf?: number
          cancelled_at?: string | null
          collateral_gnf?: number
          completed_at?: string | null
          created_at?: string
          customer_refunded_gnf?: number
          customer_user_id?: string
          delivery_fee_gnf?: number
          dispute_opened_by?: string | null
          dispute_reason?: string | null
          dispute_resolution?: Json | null
          disputed_at?: string | null
          driver_earning_gnf?: number
          driver_user_id?: string | null
          funded_at?: string | null
          id?: string
          is_sandbox?: boolean
          merchandise_subtotal_gnf?: number
          merchant_credited_gnf?: number
          merchant_store_id?: string | null
          merchant_user_id?: string | null
          mission_id?: string | null
          mission_type?: string
          order_key?: string
          order_total_gnf?: number
          platform_fee_gnf?: number
          platform_revenue_gnf?: number
          policy_snapshot?: Json
          prep_locked_at?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          source_id?: string
          source_module?: string
          state?: string
          updated_at?: string
        }
        Relationships: []
      }
      claims_reserves: {
        Row: {
          authorized_by: string
          authorized_gnf: number
          claim_key: string
          created_at: string
          customer_user_id: string | null
          declared_value_gnf: number
          documented_actual_value_gnf: number | null
          driver_user_id: string | null
          evidence_ref: string
          id: string
          is_sandbox: boolean
          mission_type: string | null
          paid_gnf: number
          reason: string
          released_gnf: number
          resolved_at: string | null
          resolved_by: string | null
          source_id: string
          source_module: string
          state: string
          updated_at: string
        }
        Insert: {
          authorized_by: string
          authorized_gnf: number
          claim_key: string
          created_at?: string
          customer_user_id?: string | null
          declared_value_gnf?: number
          documented_actual_value_gnf?: number | null
          driver_user_id?: string | null
          evidence_ref: string
          id?: string
          is_sandbox?: boolean
          mission_type?: string | null
          paid_gnf?: number
          reason: string
          released_gnf?: number
          resolved_at?: string | null
          resolved_by?: string | null
          source_id: string
          source_module: string
          state?: string
          updated_at?: string
        }
        Update: {
          authorized_by?: string
          authorized_gnf?: number
          claim_key?: string
          created_at?: string
          customer_user_id?: string | null
          declared_value_gnf?: number
          documented_actual_value_gnf?: number | null
          driver_user_id?: string | null
          evidence_ref?: string
          id?: string
          is_sandbox?: boolean
          mission_type?: string | null
          paid_gnf?: number
          reason?: string
          released_gnf?: number
          resolved_at?: string | null
          resolved_by?: string | null
          source_id?: string
          source_module?: string
          state?: string
          updated_at?: string
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
      customer_cancellation_debts: {
        Row: {
          amount_gnf: number
          applied_bps: number
          basis_gnf: number
          created_at: string
          customer_user_id: string
          debt_key: string
          exempt_reason: string | null
          id: string
          is_sandbox: boolean
          mission_type: string
          paid_gnf: number
          policy_snapshot: Json
          resolved_at: string | null
          resolved_by: string | null
          source_id: string
          source_module: string
          stage: string
          state: string
          updated_at: string
          waived_gnf: number
        }
        Insert: {
          amount_gnf: number
          applied_bps: number
          basis_gnf: number
          created_at?: string
          customer_user_id: string
          debt_key: string
          exempt_reason?: string | null
          id?: string
          is_sandbox?: boolean
          mission_type: string
          paid_gnf?: number
          policy_snapshot?: Json
          resolved_at?: string | null
          resolved_by?: string | null
          source_id: string
          source_module: string
          stage: string
          state?: string
          updated_at?: string
          waived_gnf?: number
        }
        Update: {
          amount_gnf?: number
          applied_bps?: number
          basis_gnf?: number
          created_at?: string
          customer_user_id?: string
          debt_key?: string
          exempt_reason?: string | null
          id?: string
          is_sandbox?: boolean
          mission_type?: string
          paid_gnf?: number
          policy_snapshot?: Json
          resolved_at?: string | null
          resolved_by?: string | null
          source_id?: string
          source_module?: string
          stage?: string
          state?: string
          updated_at?: string
          waived_gnf?: number
        }
        Relationships: []
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
      driver_cashout_requests: {
        Row: {
          admin_note: string | null
          amount_gnf: number
          created_at: string
          driver_note: string | null
          driver_user_id: string
          id: string
          paid_at: string | null
          paid_by: string | null
          payout_method: string
          payout_phone: string
          provider_reference: string | null
          rejected_reason: string | null
          requested_at: string
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          updated_at: string
          wallet_id: string
        }
        Insert: {
          admin_note?: string | null
          amount_gnf: number
          created_at?: string
          driver_note?: string | null
          driver_user_id: string
          id?: string
          paid_at?: string | null
          paid_by?: string | null
          payout_method?: string
          payout_phone: string
          provider_reference?: string | null
          rejected_reason?: string | null
          requested_at?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          updated_at?: string
          wallet_id: string
        }
        Update: {
          admin_note?: string | null
          amount_gnf?: number
          created_at?: string
          driver_note?: string | null
          driver_user_id?: string
          id?: string
          paid_at?: string | null
          paid_by?: string | null
          payout_method?: string
          payout_phone?: string
          provider_reference?: string | null
          rejected_reason?: string | null
          requested_at?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          updated_at?: string
          wallet_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "driver_cashout_requests_wallet_id_fkey"
            columns: ["wallet_id"]
            isOneToOne: false
            referencedRelation: "wallets"
            referencedColumns: ["id"]
          },
        ]
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
      driver_location_signals: {
        Row: {
          accuracy_meters: number | null
          active_mission_id: string | null
          active_ride_id: string | null
          capabilities: Json | null
          created_at: string
          driver_user_id: string
          heading: number | null
          last_ping_at: string
          lat: number
          lng: number
          service_zone_id: string | null
          source: string
          speed_mps: number | null
          status: string
          updated_at: string
        }
        Insert: {
          accuracy_meters?: number | null
          active_mission_id?: string | null
          active_ride_id?: string | null
          capabilities?: Json | null
          created_at?: string
          driver_user_id: string
          heading?: number | null
          last_ping_at?: string
          lat: number
          lng: number
          service_zone_id?: string | null
          source?: string
          speed_mps?: number | null
          status?: string
          updated_at?: string
        }
        Update: {
          accuracy_meters?: number | null
          active_mission_id?: string | null
          active_ride_id?: string | null
          capabilities?: Json | null
          created_at?: string
          driver_user_id?: string
          heading?: number | null
          last_ping_at?: string
          lat?: number
          lng?: number
          service_zone_id?: string | null
          source?: string
          speed_mps?: number | null
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
      driver_payout_policies: {
        Row: {
          block_on_dispute_or_freeze: boolean
          cancel_window_seconds: number
          created_at: string
          created_by: string | null
          daily_limit_gnf: number
          effective_from: string
          enabled: boolean
          id: string
          max_request_gnf: number
          min_request_gnf: number
          note: string | null
          one_pending_request_only: boolean
          processing_estimate_max_minutes: number
          processing_estimate_min_minutes: number
          provider_fee_passthrough: boolean
          registered_om_phone_only: boolean
          restricted_funds_withdrawable: boolean
        }
        Insert: {
          block_on_dispute_or_freeze?: boolean
          cancel_window_seconds?: number
          created_at?: string
          created_by?: string | null
          daily_limit_gnf?: number
          effective_from?: string
          enabled?: boolean
          id?: string
          max_request_gnf?: number
          min_request_gnf?: number
          note?: string | null
          one_pending_request_only?: boolean
          processing_estimate_max_minutes?: number
          processing_estimate_min_minutes?: number
          provider_fee_passthrough?: boolean
          registered_om_phone_only?: boolean
          restricted_funds_withdrawable?: boolean
        }
        Update: {
          block_on_dispute_or_freeze?: boolean
          cancel_window_seconds?: number
          created_at?: string
          created_by?: string | null
          daily_limit_gnf?: number
          effective_from?: string
          enabled?: boolean
          id?: string
          max_request_gnf?: number
          min_request_gnf?: number
          note?: string | null
          one_pending_request_only?: boolean
          processing_estimate_max_minutes?: number
          processing_estimate_min_minutes?: number
          provider_fee_passthrough?: boolean
          registered_om_phone_only?: boolean
          restricted_funds_withdrawable?: boolean
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
      driver_promo_credits: {
        Row: {
          consumed_gnf: number
          created_at: string
          driver_user_id: string
          grant_key: string
          grant_tx_id: string | null
          granted_by: string | null
          granted_gnf: number
          id: string
          identity_key: string | null
          policy_id: string | null
          reason: string | null
          reversed_gnf: number
          state: string
          updated_at: string
        }
        Insert: {
          consumed_gnf?: number
          created_at?: string
          driver_user_id: string
          grant_key: string
          grant_tx_id?: string | null
          granted_by?: string | null
          granted_gnf: number
          id?: string
          identity_key?: string | null
          policy_id?: string | null
          reason?: string | null
          reversed_gnf?: number
          state?: string
          updated_at?: string
        }
        Update: {
          consumed_gnf?: number
          created_at?: string
          driver_user_id?: string
          grant_key?: string
          grant_tx_id?: string | null
          granted_by?: string | null
          granted_gnf?: number
          id?: string
          identity_key?: string | null
          policy_id?: string | null
          reason?: string | null
          reversed_gnf?: number
          state?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "driver_promo_credits_policy_id_fkey"
            columns: ["policy_id"]
            isOneToOne: false
            referencedRelation: "driver_starter_credit_policies"
            referencedColumns: ["id"]
          },
        ]
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
      driver_starter_credit_policies: {
        Row: {
          amount_gnf: number
          created_at: string
          created_by: string | null
          effective_from: string
          enabled: boolean
          id: string
          note: string | null
          updated_at: string
        }
        Insert: {
          amount_gnf?: number
          created_at?: string
          created_by?: string | null
          effective_from?: string
          enabled?: boolean
          id?: string
          note?: string | null
          updated_at?: string
        }
        Update: {
          amount_gnf?: number
          created_at?: string
          created_by?: string | null
          effective_from?: string
          enabled?: boolean
          id?: string
          note?: string | null
          updated_at?: string
        }
        Relationships: []
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
      field_assignments: {
        Row: {
          assigned_zone_id: string | null
          created_at: string
          created_by: string | null
          id: string
          pilot_id: string
          role: Database["public"]["Enums"]["field_assignment_role"]
          status: Database["public"]["Enums"]["field_assignment_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          assigned_zone_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          pilot_id: string
          role?: Database["public"]["Enums"]["field_assignment_role"]
          status?: Database["public"]["Enums"]["field_assignment_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          assigned_zone_id?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          pilot_id?: string
          role?: Database["public"]["Enums"]["field_assignment_role"]
          status?: Database["public"]["Enums"]["field_assignment_status"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "field_assignments_assigned_zone_id_fkey"
            columns: ["assigned_zone_id"]
            isOneToOne: false
            referencedRelation: "map_service_zones"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "field_assignments_pilot_id_fkey"
            columns: ["pilot_id"]
            isOneToOne: false
            referencedRelation: "field_pilots"
            referencedColumns: ["id"]
          },
        ]
      }
      field_daily_reports: {
        Row: {
          created_at: string
          id: string
          merchants_converted_count: number
          merchants_interested_count: number
          merchants_submitted_count: number
          merchants_visited_count: number
          notes: string | null
          pilot_id: string
          report_date: string
          reviewed_at: string | null
          reviewed_by: string | null
          status: Database["public"]["Enums"]["field_report_status"]
          submitted_at: string
          transport_morning_paid: boolean
          transport_return_paid: boolean
          updated_at: string
          user_id: string
          zone_id: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          merchants_converted_count?: number
          merchants_interested_count?: number
          merchants_submitted_count?: number
          merchants_visited_count?: number
          notes?: string | null
          pilot_id: string
          report_date?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["field_report_status"]
          submitted_at?: string
          transport_morning_paid?: boolean
          transport_return_paid?: boolean
          updated_at?: string
          user_id: string
          zone_id?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          merchants_converted_count?: number
          merchants_interested_count?: number
          merchants_submitted_count?: number
          merchants_visited_count?: number
          notes?: string | null
          pilot_id?: string
          report_date?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["field_report_status"]
          submitted_at?: string
          transport_morning_paid?: boolean
          transport_return_paid?: boolean
          updated_at?: string
          user_id?: string
          zone_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "field_daily_reports_pilot_id_fkey"
            columns: ["pilot_id"]
            isOneToOne: false
            referencedRelation: "field_pilots"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "field_daily_reports_zone_id_fkey"
            columns: ["zone_id"]
            isOneToOne: false
            referencedRelation: "map_service_zones"
            referencedColumns: ["id"]
          },
        ]
      }
      field_merchant_visits: {
        Row: {
          address_text: string | null
          assigned_user_id: string
          created_at: string
          entrance_note: string | null
          field_captain_id: string | null
          id: string
          interest_level: Database["public"]["Enums"]["field_visit_interest"]
          landmark_note: string | null
          lat: number | null
          linked_map_place_id: string | null
          linked_merchant_store_id: string | null
          lng: number | null
          map_service_zone_id: string | null
          merchant_category: string | null
          merchant_name: string
          merchant_phone: string | null
          notes: string | null
          photo_url: string | null
          pickup_note: string | null
          pilot_id: string
          updated_at: string
          visit_status: Database["public"]["Enums"]["field_visit_status"]
        }
        Insert: {
          address_text?: string | null
          assigned_user_id: string
          created_at?: string
          entrance_note?: string | null
          field_captain_id?: string | null
          id?: string
          interest_level?: Database["public"]["Enums"]["field_visit_interest"]
          landmark_note?: string | null
          lat?: number | null
          linked_map_place_id?: string | null
          linked_merchant_store_id?: string | null
          lng?: number | null
          map_service_zone_id?: string | null
          merchant_category?: string | null
          merchant_name: string
          merchant_phone?: string | null
          notes?: string | null
          photo_url?: string | null
          pickup_note?: string | null
          pilot_id: string
          updated_at?: string
          visit_status?: Database["public"]["Enums"]["field_visit_status"]
        }
        Update: {
          address_text?: string | null
          assigned_user_id?: string
          created_at?: string
          entrance_note?: string | null
          field_captain_id?: string | null
          id?: string
          interest_level?: Database["public"]["Enums"]["field_visit_interest"]
          landmark_note?: string | null
          lat?: number | null
          linked_map_place_id?: string | null
          linked_merchant_store_id?: string | null
          lng?: number | null
          map_service_zone_id?: string | null
          merchant_category?: string | null
          merchant_name?: string
          merchant_phone?: string | null
          notes?: string | null
          photo_url?: string | null
          pickup_note?: string | null
          pilot_id?: string
          updated_at?: string
          visit_status?: Database["public"]["Enums"]["field_visit_status"]
        }
        Relationships: [
          {
            foreignKeyName: "field_merchant_visits_linked_map_place_id_fkey"
            columns: ["linked_map_place_id"]
            isOneToOne: false
            referencedRelation: "map_places"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "field_merchant_visits_map_service_zone_id_fkey"
            columns: ["map_service_zone_id"]
            isOneToOne: false
            referencedRelation: "map_service_zones"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "field_merchant_visits_pilot_id_fkey"
            columns: ["pilot_id"]
            isOneToOne: false
            referencedRelation: "field_pilots"
            referencedColumns: ["id"]
          },
        ]
      }
      field_pilots: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          end_date: string | null
          id: string
          name: string
          start_date: string | null
          status: Database["public"]["Enums"]["field_pilot_status"]
          target_merchant_count: number | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          end_date?: string | null
          id?: string
          name: string
          start_date?: string | null
          status?: Database["public"]["Enums"]["field_pilot_status"]
          target_merchant_count?: number | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          end_date?: string | null
          id?: string
          name?: string
          start_date?: string | null
          status?: Database["public"]["Enums"]["field_pilot_status"]
          target_merchant_count?: number | null
          updated_at?: string
        }
        Relationships: []
      }
      finance_evidence_refs: {
        Row: {
          actor_user_id: string | null
          amount_gnf: number
          created_at: string
          evidence_ref: string
          id: string
          normalized_ref: string | null
          target_id: string
          usage_kind: string
        }
        Insert: {
          actor_user_id?: string | null
          amount_gnf?: number
          created_at?: string
          evidence_ref: string
          id?: string
          normalized_ref?: string | null
          target_id: string
          usage_kind: string
        }
        Update: {
          actor_user_id?: string | null
          amount_gnf?: number
          created_at?: string
          evidence_ref?: string
          id?: string
          normalized_ref?: string | null
          target_id?: string
          usage_kind?: string
        }
        Relationships: []
      }
      finance_policies: {
        Row: {
          cancel_after_dispatch_bps: number
          cancel_basis: string
          cancel_before_dispatch_bps: number
          cash_funding_max_gnf: number | null
          cash_funding_mode: string
          cash_funding_pct_bps: number
          claims_exposure_max_gnf: number | null
          collateral_basis: string
          collateral_fixed_gnf: number
          collateral_max_gnf: number | null
          collateral_min_gnf: number
          collateral_mode: string
          collateral_pct_bps: number
          commission_bps: number
          created_at: string
          created_by: string | null
          effective_from: string
          enabled: boolean
          fee_basis: string
          fixed_commission_gnf: number
          id: string
          max_declared_value_gnf: number | null
          min_driver_balance_gnf: number
          mission_type: string
          note: string | null
          require_collateral_before_offer: boolean
          transaction_fee_bps: number
          updated_at: string
        }
        Insert: {
          cancel_after_dispatch_bps?: number
          cancel_basis?: string
          cancel_before_dispatch_bps?: number
          cash_funding_max_gnf?: number | null
          cash_funding_mode?: string
          cash_funding_pct_bps?: number
          claims_exposure_max_gnf?: number | null
          collateral_basis?: string
          collateral_fixed_gnf?: number
          collateral_max_gnf?: number | null
          collateral_min_gnf?: number
          collateral_mode?: string
          collateral_pct_bps?: number
          commission_bps?: number
          created_at?: string
          created_by?: string | null
          effective_from?: string
          enabled?: boolean
          fee_basis?: string
          fixed_commission_gnf?: number
          id?: string
          max_declared_value_gnf?: number | null
          min_driver_balance_gnf?: number
          mission_type: string
          note?: string | null
          require_collateral_before_offer?: boolean
          transaction_fee_bps?: number
          updated_at?: string
        }
        Update: {
          cancel_after_dispatch_bps?: number
          cancel_basis?: string
          cancel_before_dispatch_bps?: number
          cash_funding_max_gnf?: number | null
          cash_funding_mode?: string
          cash_funding_pct_bps?: number
          claims_exposure_max_gnf?: number | null
          collateral_basis?: string
          collateral_fixed_gnf?: number
          collateral_max_gnf?: number | null
          collateral_min_gnf?: number
          collateral_mode?: string
          collateral_pct_bps?: number
          commission_bps?: number
          created_at?: string
          created_by?: string | null
          effective_from?: string
          enabled?: boolean
          fee_basis?: string
          fixed_commission_gnf?: number
          id?: string
          max_declared_value_gnf?: number | null
          min_driver_balance_gnf?: number
          mission_type?: string
          note?: string | null
          require_collateral_before_offer?: boolean
          transaction_fee_bps?: number
          updated_at?: string
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
      food_order_messages: {
        Row: {
          body: string
          created_at: string
          id: string
          read_at: string | null
          sender_role: Database["public"]["Enums"]["food_order_sender_role"]
          sender_user_id: string
          thread_id: string
        }
        Insert: {
          body: string
          created_at?: string
          id?: string
          read_at?: string | null
          sender_role: Database["public"]["Enums"]["food_order_sender_role"]
          sender_user_id: string
          thread_id: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          read_at?: string | null
          sender_role?: Database["public"]["Enums"]["food_order_sender_role"]
          sender_user_id?: string
          thread_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "food_order_messages_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "food_order_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      food_order_threads: {
        Row: {
          client_user_id: string
          courier_user_id: string | null
          created_at: string
          food_order_id: string
          id: string
          last_message_at: string
          restaurant_id: string
          restaurant_owner_user_id: string
          thread_type: Database["public"]["Enums"]["food_order_thread_type"]
          updated_at: string
        }
        Insert: {
          client_user_id: string
          courier_user_id?: string | null
          created_at?: string
          food_order_id: string
          id?: string
          last_message_at?: string
          restaurant_id: string
          restaurant_owner_user_id: string
          thread_type: Database["public"]["Enums"]["food_order_thread_type"]
          updated_at?: string
        }
        Update: {
          client_user_id?: string
          courier_user_id?: string | null
          created_at?: string
          food_order_id?: string
          id?: string
          last_message_at?: string
          restaurant_id?: string
          restaurant_owner_user_id?: string
          thread_type?: Database["public"]["Enums"]["food_order_thread_type"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "food_order_threads_food_order_id_fkey"
            columns: ["food_order_id"]
            isOneToOne: false
            referencedRelation: "food_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "food_order_threads_restaurant_id_fkey"
            columns: ["restaurant_id"]
            isOneToOne: false
            referencedRelation: "food_restaurants"
            referencedColumns: ["id"]
          },
        ]
      }
      food_orders: {
        Row: {
          captured_intent_id: string | null
          client_request_id: string | null
          completed_at: string | null
          created_at: string
          delivery_address: string | null
          delivery_lat: number | null
          delivery_lng: number | null
          fulfillment: Database["public"]["Enums"]["food_fulfillment"]
          id: string
          notes: string | null
          paid_at: string | null
          payment_method: Database["public"]["Enums"]["food_payment_method"]
          payment_status: string
          request_fingerprint: string | null
          restaurant_id: string
          settlement_state: string
          settlement_tx_id: string | null
          state: Database["public"]["Enums"]["food_order_state"]
          subtotal_gnf: number
          updated_at: string
          user_id: string
        }
        Insert: {
          captured_intent_id?: string | null
          client_request_id?: string | null
          completed_at?: string | null
          created_at?: string
          delivery_address?: string | null
          delivery_lat?: number | null
          delivery_lng?: number | null
          fulfillment?: Database["public"]["Enums"]["food_fulfillment"]
          id?: string
          notes?: string | null
          paid_at?: string | null
          payment_method?: Database["public"]["Enums"]["food_payment_method"]
          payment_status?: string
          request_fingerprint?: string | null
          restaurant_id: string
          settlement_state?: string
          settlement_tx_id?: string | null
          state?: Database["public"]["Enums"]["food_order_state"]
          subtotal_gnf?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          captured_intent_id?: string | null
          client_request_id?: string | null
          completed_at?: string | null
          created_at?: string
          delivery_address?: string | null
          delivery_lat?: number | null
          delivery_lng?: number | null
          fulfillment?: Database["public"]["Enums"]["food_fulfillment"]
          id?: string
          notes?: string | null
          paid_at?: string | null
          payment_method?: Database["public"]["Enums"]["food_payment_method"]
          payment_status?: string
          request_fingerprint?: string | null
          restaurant_id?: string
          settlement_state?: string
          settlement_tx_id?: string | null
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
          merchant_store_id: string | null
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
          merchant_store_id?: string | null
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
          merchant_store_id?: string | null
          name?: string
          owner_user_id?: string | null
          pickup_available?: boolean
          prep_time_min?: number
          slug?: string
          status?: string
          updated_at?: string
          verification_state?: string
        }
        Relationships: [
          {
            foreignKeyName: "food_restaurants_merchant_store_id_fkey"
            columns: ["merchant_store_id"]
            isOneToOne: false
            referencedRelation: "merchant_stores"
            referencedColumns: ["id"]
          },
        ]
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
      ledger_accounts: {
        Row: {
          code: string
          created_at: string
          description: string | null
          kind: string
          name: string
          restricted: boolean
        }
        Insert: {
          code: string
          created_at?: string
          description?: string | null
          kind: string
          name: string
          restricted?: boolean
        }
        Update: {
          code?: string
          created_at?: string
          description?: string | null
          kind?: string
          name?: string
          restricted?: boolean
        }
        Relationships: []
      }
      ledger_journals: {
        Row: {
          action: string
          actor_user_id: string | null
          created_at: string
          evidence_ref: string | null
          id: string
          is_sandbox: boolean
          journal_key: string
          mission_type: string | null
          policy_snapshot: Json
          reason: string | null
          reverses_journal_id: string | null
          source_id: string | null
          source_module: string
        }
        Insert: {
          action: string
          actor_user_id?: string | null
          created_at?: string
          evidence_ref?: string | null
          id?: string
          is_sandbox?: boolean
          journal_key: string
          mission_type?: string | null
          policy_snapshot?: Json
          reason?: string | null
          reverses_journal_id?: string | null
          source_id?: string | null
          source_module: string
        }
        Update: {
          action?: string
          actor_user_id?: string | null
          created_at?: string
          evidence_ref?: string | null
          id?: string
          is_sandbox?: boolean
          journal_key?: string
          mission_type?: string | null
          policy_snapshot?: Json
          reason?: string | null
          reverses_journal_id?: string | null
          source_id?: string | null
          source_module?: string
        }
        Relationships: [
          {
            foreignKeyName: "ledger_journals_reverses_journal_id_fkey"
            columns: ["reverses_journal_id"]
            isOneToOne: false
            referencedRelation: "ledger_journals"
            referencedColumns: ["id"]
          },
        ]
      }
      ledger_postings: {
        Row: {
          account_code: string
          amount_gnf: number
          created_at: string
          id: string
          journal_id: string
          memo: string | null
          merchant_store_id: string | null
          party_type: Database["public"]["Enums"]["party_type"] | null
          party_user_id: string | null
        }
        Insert: {
          account_code: string
          amount_gnf: number
          created_at?: string
          id?: string
          journal_id: string
          memo?: string | null
          merchant_store_id?: string | null
          party_type?: Database["public"]["Enums"]["party_type"] | null
          party_user_id?: string | null
        }
        Update: {
          account_code?: string
          amount_gnf?: number
          created_at?: string
          id?: string
          journal_id?: string
          memo?: string | null
          merchant_store_id?: string | null
          party_type?: Database["public"]["Enums"]["party_type"] | null
          party_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ledger_postings_account_code_fkey"
            columns: ["account_code"]
            isOneToOne: false
            referencedRelation: "ledger_accounts"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "ledger_postings_journal_id_fkey"
            columns: ["journal_id"]
            isOneToOne: false
            referencedRelation: "ledger_journals"
            referencedColumns: ["id"]
          },
        ]
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
        Relationships: [
          {
            foreignKeyName: "listing_interests_listing_id_fkey"
            columns: ["listing_id"]
            isOneToOne: false
            referencedRelation: "marketplace_listings"
            referencedColumns: ["id"]
          },
        ]
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
      map_driver_reports: {
        Row: {
          created_at: string
          id: string
          notes: string | null
          place_id: string | null
          report_type: string
          reporter_id: string | null
          resolved_at: string | null
          resolved_by: string | null
          status: string
          zone_id: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          notes?: string | null
          place_id?: string | null
          report_type: string
          reporter_id?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: string
          zone_id?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          notes?: string | null
          place_id?: string | null
          report_type?: string
          reporter_id?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: string
          zone_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "map_driver_reports_place_id_fkey"
            columns: ["place_id"]
            isOneToOne: false
            referencedRelation: "map_places"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "map_driver_reports_zone_id_fkey"
            columns: ["zone_id"]
            isOneToOne: false
            referencedRelation: "map_service_zones"
            referencedColumns: ["id"]
          },
        ]
      }
      map_fare_troncons: {
        Row: {
          collected_at: string
          collected_by: string | null
          confidence_score: number
          created_at: string
          day_price_gnf: number | null
          departure_name: string
          departure_place_id: string | null
          destination_name: string
          destination_place_id: string | null
          id: string
          is_active: boolean
          is_bidirectional: boolean
          night_price_gnf: number | null
          notes: string | null
          raw_departure_name: string
          raw_destination_name: string
          source: string | null
          source_type: string
          updated_at: string
          verification_status: Database["public"]["Enums"]["map_verification_status"]
        }
        Insert: {
          collected_at?: string
          collected_by?: string | null
          confidence_score?: number
          created_at?: string
          day_price_gnf?: number | null
          departure_name: string
          departure_place_id?: string | null
          destination_name: string
          destination_place_id?: string | null
          id?: string
          is_active?: boolean
          is_bidirectional?: boolean
          night_price_gnf?: number | null
          notes?: string | null
          raw_departure_name: string
          raw_destination_name: string
          source?: string | null
          source_type?: string
          updated_at?: string
          verification_status?: Database["public"]["Enums"]["map_verification_status"]
        }
        Update: {
          collected_at?: string
          collected_by?: string | null
          confidence_score?: number
          created_at?: string
          day_price_gnf?: number | null
          departure_name?: string
          departure_place_id?: string | null
          destination_name?: string
          destination_place_id?: string | null
          id?: string
          is_active?: boolean
          is_bidirectional?: boolean
          night_price_gnf?: number | null
          notes?: string | null
          raw_departure_name?: string
          raw_destination_name?: string
          source?: string | null
          source_type?: string
          updated_at?: string
          verification_status?: Database["public"]["Enums"]["map_verification_status"]
        }
        Relationships: [
          {
            foreignKeyName: "map_fare_troncons_departure_place_id_fkey"
            columns: ["departure_place_id"]
            isOneToOne: false
            referencedRelation: "map_places"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "map_fare_troncons_destination_place_id_fkey"
            columns: ["destination_place_id"]
            isOneToOne: false
            referencedRelation: "map_places"
            referencedColumns: ["id"]
          },
        ]
      }
      map_place_duplicate_candidates: {
        Row: {
          category_match: boolean
          commune_match: boolean
          created_at: string
          distance_meters: number | null
          id: string
          merge_target_place_id: string | null
          name_similarity: number | null
          notes: string | null
          phone_match: boolean
          place_a_id: string
          place_b_id: string
          reason_codes: string[]
          reviewed_at: string | null
          reviewed_by: string | null
          score: number
          status: string
          updated_at: string
        }
        Insert: {
          category_match?: boolean
          commune_match?: boolean
          created_at?: string
          distance_meters?: number | null
          id?: string
          merge_target_place_id?: string | null
          name_similarity?: number | null
          notes?: string | null
          phone_match?: boolean
          place_a_id: string
          place_b_id: string
          reason_codes?: string[]
          reviewed_at?: string | null
          reviewed_by?: string | null
          score?: number
          status?: string
          updated_at?: string
        }
        Update: {
          category_match?: boolean
          commune_match?: boolean
          created_at?: string
          distance_meters?: number | null
          id?: string
          merge_target_place_id?: string | null
          name_similarity?: number | null
          notes?: string | null
          phone_match?: boolean
          place_a_id?: string
          place_b_id?: string
          reason_codes?: string[]
          reviewed_at?: string | null
          reviewed_by?: string | null
          score?: number
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "map_place_duplicate_candidates_merge_target_place_id_fkey"
            columns: ["merge_target_place_id"]
            isOneToOne: false
            referencedRelation: "map_places"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "map_place_duplicate_candidates_place_a_id_fkey"
            columns: ["place_a_id"]
            isOneToOne: false
            referencedRelation: "map_places"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "map_place_duplicate_candidates_place_b_id_fkey"
            columns: ["place_b_id"]
            isOneToOne: false
            referencedRelation: "map_places"
            referencedColumns: ["id"]
          },
        ]
      }
      map_places: {
        Row: {
          active: boolean
          aliases: string[]
          category: string | null
          commune: string | null
          confidence_score: number
          created_at: string
          created_by: string | null
          duplicate_of: string | null
          entrance_note: string | null
          id: string
          landmark_note: string | null
          last_reported_at: string | null
          lat: number | null
          lng: number | null
          name: string
          neighborhood: string | null
          operational_note: string | null
          pickup_note: string | null
          source: string | null
          updated_at: string
          verification_status: Database["public"]["Enums"]["map_verification_status"]
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          active?: boolean
          aliases?: string[]
          category?: string | null
          commune?: string | null
          confidence_score?: number
          created_at?: string
          created_by?: string | null
          duplicate_of?: string | null
          entrance_note?: string | null
          id?: string
          landmark_note?: string | null
          last_reported_at?: string | null
          lat?: number | null
          lng?: number | null
          name: string
          neighborhood?: string | null
          operational_note?: string | null
          pickup_note?: string | null
          source?: string | null
          updated_at?: string
          verification_status?: Database["public"]["Enums"]["map_verification_status"]
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          active?: boolean
          aliases?: string[]
          category?: string | null
          commune?: string | null
          confidence_score?: number
          created_at?: string
          created_by?: string | null
          duplicate_of?: string | null
          entrance_note?: string | null
          id?: string
          landmark_note?: string | null
          last_reported_at?: string | null
          lat?: number | null
          lng?: number | null
          name?: string
          neighborhood?: string | null
          operational_note?: string | null
          pickup_note?: string | null
          source?: string | null
          updated_at?: string
          verification_status?: Database["public"]["Enums"]["map_verification_status"]
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "map_places_duplicate_of_fkey"
            columns: ["duplicate_of"]
            isOneToOne: false
            referencedRelation: "map_places"
            referencedColumns: ["id"]
          },
        ]
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
      map_route_observations: {
        Row: {
          confidence_score: number
          created_at: string
          destination_lat: number
          destination_lng: number
          driver_user_id: string | null
          fallback_used: boolean
          id: string
          notes: string | null
          observed_distance_meters: number | null
          observed_duration_seconds: number | null
          observed_polyline_geojson: Json | null
          origin_lat: number
          origin_lng: number
          provider_used: string | null
          simplified_polyline_geojson: Json | null
          source_id: string | null
          source_module: string
          status: string
          updated_at: string
          verification_status: string
        }
        Insert: {
          confidence_score?: number
          created_at?: string
          destination_lat: number
          destination_lng: number
          driver_user_id?: string | null
          fallback_used?: boolean
          id?: string
          notes?: string | null
          observed_distance_meters?: number | null
          observed_duration_seconds?: number | null
          observed_polyline_geojson?: Json | null
          origin_lat: number
          origin_lng: number
          provider_used?: string | null
          simplified_polyline_geojson?: Json | null
          source_id?: string | null
          source_module: string
          status?: string
          updated_at?: string
          verification_status?: string
        }
        Update: {
          confidence_score?: number
          created_at?: string
          destination_lat?: number
          destination_lng?: number
          driver_user_id?: string | null
          fallback_used?: boolean
          id?: string
          notes?: string | null
          observed_distance_meters?: number | null
          observed_duration_seconds?: number | null
          observed_polyline_geojson?: Json | null
          origin_lat?: number
          origin_lng?: number
          provider_used?: string | null
          simplified_polyline_geojson?: Json | null
          source_id?: string | null
          source_module?: string
          status?: string
          updated_at?: string
          verification_status?: string
        }
        Relationships: []
      }
      map_service_zones: {
        Row: {
          boundary_geojson: Json | null
          center_lat: number | null
          center_lng: number | null
          commune: string | null
          confidence_score: number
          coverage_notes: string | null
          created_at: string
          created_by: string | null
          district: string | null
          driver_notes: string | null
          id: string
          merchant_notes: string | null
          name: string
          ops_notes: string | null
          priority: string
          radius_meters: number | null
          services_enabled: Json
          status: string
          updated_at: string
          verification_status: Database["public"]["Enums"]["map_verification_status"]
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          boundary_geojson?: Json | null
          center_lat?: number | null
          center_lng?: number | null
          commune?: string | null
          confidence_score?: number
          coverage_notes?: string | null
          created_at?: string
          created_by?: string | null
          district?: string | null
          driver_notes?: string | null
          id?: string
          merchant_notes?: string | null
          name: string
          ops_notes?: string | null
          priority?: string
          radius_meters?: number | null
          services_enabled?: Json
          status?: string
          updated_at?: string
          verification_status?: Database["public"]["Enums"]["map_verification_status"]
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          boundary_geojson?: Json | null
          center_lat?: number | null
          center_lng?: number | null
          commune?: string | null
          confidence_score?: number
          coverage_notes?: string | null
          created_at?: string
          created_by?: string | null
          district?: string | null
          driver_notes?: string | null
          id?: string
          merchant_notes?: string | null
          name?: string
          ops_notes?: string | null
          priority?: string
          radius_meters?: number | null
          services_enabled?: Json
          status?: string
          updated_at?: string
          verification_status?: Database["public"]["Enums"]["map_verification_status"]
          verified_at?: string | null
          verified_by?: string | null
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
          authorized_at: string | null
          buyer_message: string | null
          buyer_user_id: string
          captured_tx_id: string | null
          completed_at: string | null
          counter_amount_gnf: number | null
          created_at: string
          expires_at: string | null
          fulfilled_at: string | null
          fulfillment_status: string
          id: string
          listing_id: string
          merchant_message: string | null
          merchant_store_id: string | null
          merchant_user_id: string
          metadata: Json
          offer_amount_gnf: number
          paid_at: string | null
          payment_intent_id: string | null
          payment_status: string
          responded_at: string | null
          settlement_state: string
          settlement_tx_id: string | null
          status: string
          updated_at: string
        }
        Insert: {
          authorized_at?: string | null
          buyer_message?: string | null
          buyer_user_id: string
          captured_tx_id?: string | null
          completed_at?: string | null
          counter_amount_gnf?: number | null
          created_at?: string
          expires_at?: string | null
          fulfilled_at?: string | null
          fulfillment_status?: string
          id?: string
          listing_id: string
          merchant_message?: string | null
          merchant_store_id?: string | null
          merchant_user_id: string
          metadata?: Json
          offer_amount_gnf: number
          paid_at?: string | null
          payment_intent_id?: string | null
          payment_status?: string
          responded_at?: string | null
          settlement_state?: string
          settlement_tx_id?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          authorized_at?: string | null
          buyer_message?: string | null
          buyer_user_id?: string
          captured_tx_id?: string | null
          completed_at?: string | null
          counter_amount_gnf?: number | null
          created_at?: string
          expires_at?: string | null
          fulfilled_at?: string | null
          fulfillment_status?: string
          id?: string
          listing_id?: string
          merchant_message?: string | null
          merchant_store_id?: string | null
          merchant_user_id?: string
          metadata?: Json
          offer_amount_gnf?: number
          paid_at?: string | null
          payment_intent_id?: string | null
          payment_status?: string
          responded_at?: string | null
          settlement_state?: string
          settlement_tx_id?: string | null
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
      merchant_payables: {
        Row: {
          amount_gnf: number
          created_at: string
          deduction_gnf: number
          evidence_ref: string | null
          funded_gnf: number
          funding_source: string
          id: string
          is_sandbox: boolean
          merchant_store_id: string
          merchant_user_id: string | null
          mission_type: string | null
          payable_key: string
          policy_snapshot: Json
          reason: string | null
          resolved_at: string | null
          resolved_by: string | null
          settled_gnf: number
          source_id: string
          source_module: string
          state: string
          subtotal_gnf: number
          updated_at: string
        }
        Insert: {
          amount_gnf: number
          created_at?: string
          deduction_gnf?: number
          evidence_ref?: string | null
          funded_gnf?: number
          funding_source?: string
          id?: string
          is_sandbox?: boolean
          merchant_store_id: string
          merchant_user_id?: string | null
          mission_type?: string | null
          payable_key: string
          policy_snapshot?: Json
          reason?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          settled_gnf?: number
          source_id: string
          source_module: string
          state?: string
          subtotal_gnf: number
          updated_at?: string
        }
        Update: {
          amount_gnf?: number
          created_at?: string
          deduction_gnf?: number
          evidence_ref?: string | null
          funded_gnf?: number
          funding_source?: string
          id?: string
          is_sandbox?: boolean
          merchant_store_id?: string
          merchant_user_id?: string | null
          mission_type?: string | null
          payable_key?: string
          policy_snapshot?: Json
          reason?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          settled_gnf?: number
          source_id?: string
          source_module?: string
          state?: string
          subtotal_gnf?: number
          updated_at?: string
        }
        Relationships: []
      }
      merchant_settlement_policies: {
        Row: {
          cadence: string | null
          configured: boolean
          created_at: string
          created_by: string | null
          effective_from: string
          enabled: boolean
          fee_bps: number | null
          fee_fixed_gnf: number | null
          fee_passthrough: boolean | null
          id: string
          max_settlement_gnf: number | null
          min_settlement_gnf: number | null
          note: string | null
          requires_evidence_reconciliation: boolean
        }
        Insert: {
          cadence?: string | null
          configured?: boolean
          created_at?: string
          created_by?: string | null
          effective_from?: string
          enabled?: boolean
          fee_bps?: number | null
          fee_fixed_gnf?: number | null
          fee_passthrough?: boolean | null
          id?: string
          max_settlement_gnf?: number | null
          min_settlement_gnf?: number | null
          note?: string | null
          requires_evidence_reconciliation?: boolean
        }
        Update: {
          cadence?: string | null
          configured?: boolean
          created_at?: string
          created_by?: string | null
          effective_from?: string
          enabled?: boolean
          fee_bps?: number | null
          fee_fixed_gnf?: number | null
          fee_passthrough?: boolean | null
          id?: string
          max_settlement_gnf?: number | null
          min_settlement_gnf?: number | null
          note?: string | null
          requires_evidence_reconciliation?: boolean
        }
        Relationships: []
      }
      merchant_settlement_requests: {
        Row: {
          amount_gnf: number
          channel: string
          created_at: string
          currency: string
          eligible_snapshot_gnf: number
          evidence_ref: string | null
          id: string
          merchant_store_id: string
          merchant_user_id: string
          note: string | null
          reject_reason: string | null
          request_key: string
          reviewed_at: string | null
          reviewed_by: string | null
          settled_at: string | null
          status: string
          updated_at: string
        }
        Insert: {
          amount_gnf: number
          channel?: string
          created_at?: string
          currency?: string
          eligible_snapshot_gnf: number
          evidence_ref?: string | null
          id?: string
          merchant_store_id: string
          merchant_user_id: string
          note?: string | null
          reject_reason?: string | null
          request_key: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          settled_at?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          amount_gnf?: number
          channel?: string
          created_at?: string
          currency?: string
          eligible_snapshot_gnf?: number
          evidence_ref?: string | null
          id?: string
          merchant_store_id?: string
          merchant_user_id?: string
          note?: string | null
          reject_reason?: string | null
          request_key?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          settled_at?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      merchant_settlement_schedule_runs: {
        Row: {
          as_of: string
          candidate_amount_gnf: number
          created_at: string
          id: string
          merchant_store_id: string
          period_key: string
          policy_snapshot: Json
          request_id: string | null
        }
        Insert: {
          as_of?: string
          candidate_amount_gnf?: number
          created_at?: string
          id?: string
          merchant_store_id: string
          period_key: string
          policy_snapshot?: Json
          request_id?: string | null
        }
        Update: {
          as_of?: string
          candidate_amount_gnf?: number
          created_at?: string
          id?: string
          merchant_store_id?: string
          period_key?: string
          policy_snapshot?: Json
          request_id?: string | null
        }
        Relationships: []
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
          commune: string | null
          cover_url: string | null
          created_at: string
          created_by: string | null
          delivery_available: boolean
          district: string | null
          id: string
          id_photo_path: string | null
          landmark: string | null
          landmark_note: string | null
          latitude: number | null
          location_accuracy_m: number | null
          location_capture_method: string | null
          location_confirmed_at: string | null
          location_notes: string | null
          location_source: string | null
          location_submission_status: string
          location_submitted_at: string | null
          location_verified_at: string | null
          location_verified_by: string | null
          longitude: number | null
          map_place_id: string | null
          market_id: string | null
          market_name: string | null
          member_since: string
          merchant_account_number: string | null
          merchant_qr_payload: string | null
          merchant_status: string
          name: string
          onboarding_branch: string
          onboarding_status: string
          operating_hours: string | null
          owner_name: string | null
          owner_user_id: string
          phone: string | null
          product_categories: string[]
          rejection_reason: string | null
          selfie_photo_path: string | null
          service_agent_decided_at: string | null
          service_agent_decided_by: string | null
          service_agent_notes: string | null
          service_agent_requested: boolean
          service_agent_status: string
          slug: string
          stall_number: string | null
          status: string
          storefront_photo_path: string | null
          submitted_at: string | null
          updated_at: string
          verification_state: string
          wants_food: boolean
          wants_marketplace: boolean
          wants_wallet_agent: boolean
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
          commune?: string | null
          cover_url?: string | null
          created_at?: string
          created_by?: string | null
          delivery_available?: boolean
          district?: string | null
          id?: string
          id_photo_path?: string | null
          landmark?: string | null
          landmark_note?: string | null
          latitude?: number | null
          location_accuracy_m?: number | null
          location_capture_method?: string | null
          location_confirmed_at?: string | null
          location_notes?: string | null
          location_source?: string | null
          location_submission_status?: string
          location_submitted_at?: string | null
          location_verified_at?: string | null
          location_verified_by?: string | null
          longitude?: number | null
          map_place_id?: string | null
          market_id?: string | null
          market_name?: string | null
          member_since?: string
          merchant_account_number?: string | null
          merchant_qr_payload?: string | null
          merchant_status?: string
          name: string
          onboarding_branch?: string
          onboarding_status?: string
          operating_hours?: string | null
          owner_name?: string | null
          owner_user_id: string
          phone?: string | null
          product_categories?: string[]
          rejection_reason?: string | null
          selfie_photo_path?: string | null
          service_agent_decided_at?: string | null
          service_agent_decided_by?: string | null
          service_agent_notes?: string | null
          service_agent_requested?: boolean
          service_agent_status?: string
          slug: string
          stall_number?: string | null
          status?: string
          storefront_photo_path?: string | null
          submitted_at?: string | null
          updated_at?: string
          verification_state?: string
          wants_food?: boolean
          wants_marketplace?: boolean
          wants_wallet_agent?: boolean
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
          commune?: string | null
          cover_url?: string | null
          created_at?: string
          created_by?: string | null
          delivery_available?: boolean
          district?: string | null
          id?: string
          id_photo_path?: string | null
          landmark?: string | null
          landmark_note?: string | null
          latitude?: number | null
          location_accuracy_m?: number | null
          location_capture_method?: string | null
          location_confirmed_at?: string | null
          location_notes?: string | null
          location_source?: string | null
          location_submission_status?: string
          location_submitted_at?: string | null
          location_verified_at?: string | null
          location_verified_by?: string | null
          longitude?: number | null
          map_place_id?: string | null
          market_id?: string | null
          market_name?: string | null
          member_since?: string
          merchant_account_number?: string | null
          merchant_qr_payload?: string | null
          merchant_status?: string
          name?: string
          onboarding_branch?: string
          onboarding_status?: string
          operating_hours?: string | null
          owner_name?: string | null
          owner_user_id?: string
          phone?: string | null
          product_categories?: string[]
          rejection_reason?: string | null
          selfie_photo_path?: string | null
          service_agent_decided_at?: string | null
          service_agent_decided_by?: string | null
          service_agent_notes?: string | null
          service_agent_requested?: boolean
          service_agent_status?: string
          slug?: string
          stall_number?: string | null
          status?: string
          storefront_photo_path?: string | null
          submitted_at?: string | null
          updated_at?: string
          verification_state?: string
          wants_food?: boolean
          wants_marketplace?: boolean
          wants_wallet_agent?: boolean
          whatsapp?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "merchant_stores_map_place_id_fkey"
            columns: ["map_place_id"]
            isOneToOne: false
            referencedRelation: "map_places"
            referencedColumns: ["id"]
          },
        ]
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
      mission_financial_holds: {
        Row: {
          amount_gnf: number
          basis_value_gnf: number
          captured_gnf: number
          captured_promo_gnf: number
          captured_unrestricted_gnf: number
          created_at: string
          customer_gnf: number
          driver_user_id: string | null
          evidence_ref: string | null
          hold_tx_id: string | null
          id: string
          is_sandbox: boolean
          journal_key: string | null
          kind: string
          merchant_store_id: string | null
          mission_type: string
          party_type: Database["public"]["Enums"]["party_type"]
          party_user_id: string | null
          platform_gnf: number
          policy_id: string | null
          policy_snapshot: Json
          promo_gnf: number
          reason: string | null
          released_gnf: number
          resolution_tx_id: string | null
          resolved_at: string | null
          resolved_by: string | null
          source_id: string
          source_module: string
          state: string
          unrestricted_gnf: number
          updated_at: string
        }
        Insert: {
          amount_gnf: number
          basis_value_gnf?: number
          captured_gnf?: number
          captured_promo_gnf?: number
          captured_unrestricted_gnf?: number
          created_at?: string
          customer_gnf?: number
          driver_user_id?: string | null
          evidence_ref?: string | null
          hold_tx_id?: string | null
          id?: string
          is_sandbox?: boolean
          journal_key?: string | null
          kind: string
          merchant_store_id?: string | null
          mission_type: string
          party_type?: Database["public"]["Enums"]["party_type"]
          party_user_id?: string | null
          platform_gnf?: number
          policy_id?: string | null
          policy_snapshot?: Json
          promo_gnf?: number
          reason?: string | null
          released_gnf?: number
          resolution_tx_id?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          source_id: string
          source_module: string
          state?: string
          unrestricted_gnf?: number
          updated_at?: string
        }
        Update: {
          amount_gnf?: number
          basis_value_gnf?: number
          captured_gnf?: number
          captured_promo_gnf?: number
          captured_unrestricted_gnf?: number
          created_at?: string
          customer_gnf?: number
          driver_user_id?: string | null
          evidence_ref?: string | null
          hold_tx_id?: string | null
          id?: string
          is_sandbox?: boolean
          journal_key?: string | null
          kind?: string
          merchant_store_id?: string | null
          mission_type?: string
          party_type?: Database["public"]["Enums"]["party_type"]
          party_user_id?: string | null
          platform_gnf?: number
          policy_id?: string | null
          policy_snapshot?: Json
          promo_gnf?: number
          reason?: string | null
          released_gnf?: number
          resolution_tx_id?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          source_id?: string
          source_module?: string
          state?: string
          unrestricted_gnf?: number
          updated_at?: string
        }
        Relationships: []
      }
      missions: {
        Row: {
          courier_id: string | null
          created_at: string
          customer_confirmed_at: string | null
          customer_confirmed_by: string | null
          customer_handoff_code: string | null
          customer_id: string
          delivery_photo_url: string | null
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
          merchant_handoff_code: string | null
          merchant_id: string | null
          merchant_store_id: string | null
          payload_summary: string | null
          pickup_address: string | null
          pickup_confirmed_at: string | null
          pickup_confirmed_by: string | null
          pickup_lat: number | null
          pickup_lng: number | null
          pickup_photo_url: string | null
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
          customer_confirmed_at?: string | null
          customer_confirmed_by?: string | null
          customer_handoff_code?: string | null
          customer_id: string
          delivery_photo_url?: string | null
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
          merchant_handoff_code?: string | null
          merchant_id?: string | null
          merchant_store_id?: string | null
          payload_summary?: string | null
          pickup_address?: string | null
          pickup_confirmed_at?: string | null
          pickup_confirmed_by?: string | null
          pickup_lat?: number | null
          pickup_lng?: number | null
          pickup_photo_url?: string | null
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
          customer_confirmed_at?: string | null
          customer_confirmed_by?: string | null
          customer_handoff_code?: string | null
          customer_id?: string
          delivery_photo_url?: string | null
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
          merchant_handoff_code?: string | null
          merchant_id?: string | null
          merchant_store_id?: string | null
          payload_summary?: string | null
          pickup_address?: string | null
          pickup_confirmed_at?: string | null
          pickup_confirmed_by?: string | null
          pickup_lat?: number | null
          pickup_lng?: number | null
          pickup_photo_url?: string | null
          ref_food_order_id?: string | null
          ref_market_order_id?: string | null
          ref_ride_id?: string | null
          state?: Database["public"]["Enums"]["mission_state"]
          type?: Database["public"]["Enums"]["mission_type"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "missions_merchant_store_id_fkey"
            columns: ["merchant_store_id"]
            isOneToOne: false
            referencedRelation: "merchant_stores"
            referencedColumns: ["id"]
          },
        ]
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
      package_deliveries: {
        Row: {
          cancellation_fee_gnf: number
          cancellation_reason: string | null
          cancelled_at: string | null
          category: string
          claim_state: string
          created_at: string
          declared_value_gnf: number
          delivered_at: string | null
          description: string | null
          destination_label: string | null
          destination_lat: number
          destination_lng: number
          distance_meters: number | null
          duration_seconds: number | null
          environment: string
          finance_snapshot: Json
          handling_notes: string | null
          id: string
          idempotency_key: string
          is_sandbox: boolean
          metadata: Json
          mission_id: string | null
          package_status: string
          payment_intent_id: string | null
          payment_status: string
          pickup_label: string | null
          pickup_lat: number
          pickup_lng: number
          quote_id: string | null
          quoted_amount_gnf: number
          recipient_confirmed_name: string | null
          recipient_name: string
          recipient_phone: string
          reference: string
          refund_request_id: string | null
          sender_name: string | null
          sender_phone: string | null
          sender_user_id: string
          support_issue_id: string | null
          tender: string | null
          test_run_id: string | null
          updated_at: string
          value_attestation_statement: string | null
          value_attestation_version: string | null
          value_attested_at: string | null
          value_attested_by: string | null
        }
        Insert: {
          cancellation_fee_gnf?: number
          cancellation_reason?: string | null
          cancelled_at?: string | null
          category: string
          claim_state?: string
          created_at?: string
          declared_value_gnf?: number
          delivered_at?: string | null
          description?: string | null
          destination_label?: string | null
          destination_lat: number
          destination_lng: number
          distance_meters?: number | null
          duration_seconds?: number | null
          environment?: string
          finance_snapshot?: Json
          handling_notes?: string | null
          id?: string
          idempotency_key: string
          is_sandbox?: boolean
          metadata?: Json
          mission_id?: string | null
          package_status?: string
          payment_intent_id?: string | null
          payment_status?: string
          pickup_label?: string | null
          pickup_lat: number
          pickup_lng: number
          quote_id?: string | null
          quoted_amount_gnf: number
          recipient_confirmed_name?: string | null
          recipient_name: string
          recipient_phone: string
          reference: string
          refund_request_id?: string | null
          sender_name?: string | null
          sender_phone?: string | null
          sender_user_id: string
          support_issue_id?: string | null
          tender?: string | null
          test_run_id?: string | null
          updated_at?: string
          value_attestation_statement?: string | null
          value_attestation_version?: string | null
          value_attested_at?: string | null
          value_attested_by?: string | null
        }
        Update: {
          cancellation_fee_gnf?: number
          cancellation_reason?: string | null
          cancelled_at?: string | null
          category?: string
          claim_state?: string
          created_at?: string
          declared_value_gnf?: number
          delivered_at?: string | null
          description?: string | null
          destination_label?: string | null
          destination_lat?: number
          destination_lng?: number
          distance_meters?: number | null
          duration_seconds?: number | null
          environment?: string
          finance_snapshot?: Json
          handling_notes?: string | null
          id?: string
          idempotency_key?: string
          is_sandbox?: boolean
          metadata?: Json
          mission_id?: string | null
          package_status?: string
          payment_intent_id?: string | null
          payment_status?: string
          pickup_label?: string | null
          pickup_lat?: number
          pickup_lng?: number
          quote_id?: string | null
          quoted_amount_gnf?: number
          recipient_confirmed_name?: string | null
          recipient_name?: string
          recipient_phone?: string
          reference?: string
          refund_request_id?: string | null
          sender_name?: string | null
          sender_phone?: string | null
          sender_user_id?: string
          support_issue_id?: string | null
          tender?: string | null
          test_run_id?: string | null
          updated_at?: string
          value_attestation_statement?: string | null
          value_attestation_version?: string | null
          value_attested_at?: string | null
          value_attested_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "package_deliveries_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "package_delivery_quotes"
            referencedColumns: ["id"]
          },
        ]
      }
      package_delivery_quotes: {
        Row: {
          amount_gnf: number
          category: string
          consumed_at: string | null
          created_at: string
          destination_label: string | null
          destination_lat: number
          destination_lng: number
          distance_meters: number | null
          duration_seconds: number | null
          expires_at: string
          id: string
          pickup_label: string | null
          pickup_lat: number
          pickup_lng: number
          tariff_snapshot: Json
          user_id: string
        }
        Insert: {
          amount_gnf: number
          category: string
          consumed_at?: string | null
          created_at?: string
          destination_label?: string | null
          destination_lat: number
          destination_lng: number
          distance_meters?: number | null
          duration_seconds?: number | null
          expires_at: string
          id?: string
          pickup_label?: string | null
          pickup_lat: number
          pickup_lng: number
          tariff_snapshot?: Json
          user_id: string
        }
        Update: {
          amount_gnf?: number
          category?: string
          consumed_at?: string | null
          created_at?: string
          destination_label?: string | null
          destination_lat?: number
          destination_lng?: number
          distance_meters?: number | null
          duration_seconds?: number | null
          expires_at?: string
          id?: string
          pickup_label?: string | null
          pickup_lat?: number
          pickup_lng?: number
          tariff_snapshot?: Json
          user_id?: string
        }
        Relationships: []
      }
      package_delivery_secrets: {
        Row: {
          created_at: string
          delivery_attempts: number
          delivery_code: string
          delivery_verified_at: string | null
          package_id: string
          pickup_attempts: number
          pickup_code: string
          pickup_verified_at: string | null
        }
        Insert: {
          created_at?: string
          delivery_attempts?: number
          delivery_code: string
          delivery_verified_at?: string | null
          package_id: string
          pickup_attempts?: number
          pickup_code: string
          pickup_verified_at?: string | null
        }
        Update: {
          created_at?: string
          delivery_attempts?: number
          delivery_code?: string
          delivery_verified_at?: string | null
          package_id?: string
          pickup_attempts?: number
          pickup_code?: string
          pickup_verified_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "package_delivery_secrets_package_id_fkey"
            columns: ["package_id"]
            isOneToOne: true
            referencedRelation: "package_deliveries"
            referencedColumns: ["id"]
          },
        ]
      }
      package_evidence_photos: {
        Row: {
          byte_size: number | null
          content_type: string | null
          created_at: string
          id: string
          kind: string
          owner_user_id: string
          package_id: string | null
          quote_id: string
          storage_bucket: string
          storage_path: string
          updated_at: string
        }
        Insert: {
          byte_size?: number | null
          content_type?: string | null
          created_at?: string
          id?: string
          kind?: string
          owner_user_id: string
          package_id?: string | null
          quote_id: string
          storage_bucket?: string
          storage_path: string
          updated_at?: string
        }
        Update: {
          byte_size?: number | null
          content_type?: string | null
          created_at?: string
          id?: string
          kind?: string
          owner_user_id?: string
          package_id?: string | null
          quote_id?: string
          storage_bucket?: string
          storage_path?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "package_evidence_photos_package_id_fkey"
            columns: ["package_id"]
            isOneToOne: false
            referencedRelation: "package_deliveries"
            referencedColumns: ["id"]
          },
        ]
      }
      package_runtime: {
        Row: {
          accepted_at: string | null
          cancelled_at: string | null
          cash_due_gnf: number
          claim_opened_at: string | null
          claim_paid_gnf: number
          claim_state: string
          claims_exposure_gnf: number
          collateral_gnf: number
          completed_at: string | null
          created_at: string
          customer_hold_gnf: number
          customer_user_id: string
          declared_value_gnf: number
          delivery_fee_gnf: number
          documented_actual_value_gnf: number | null
          documented_value_at: string | null
          documented_value_by: string | null
          documented_value_evidence_ref: string | null
          driver_earning_gnf: number
          driver_user_id: string | null
          id: string
          is_sandbox: boolean
          mission_id: string | null
          mission_type: string
          order_key: string
          package_id: string
          picked_up_at: string | null
          platform_fee_gnf: number
          platform_revenue_gnf: number
          policy_snapshot: Json
          resolved_at: string | null
          source_module: string
          state: string
          tender: string
          updated_at: string
        }
        Insert: {
          accepted_at?: string | null
          cancelled_at?: string | null
          cash_due_gnf?: number
          claim_opened_at?: string | null
          claim_paid_gnf?: number
          claim_state?: string
          claims_exposure_gnf?: number
          collateral_gnf?: number
          completed_at?: string | null
          created_at?: string
          customer_hold_gnf?: number
          customer_user_id: string
          declared_value_gnf: number
          delivery_fee_gnf: number
          documented_actual_value_gnf?: number | null
          documented_value_at?: string | null
          documented_value_by?: string | null
          documented_value_evidence_ref?: string | null
          driver_earning_gnf?: number
          driver_user_id?: string | null
          id?: string
          is_sandbox?: boolean
          mission_id?: string | null
          mission_type?: string
          order_key: string
          package_id: string
          picked_up_at?: string | null
          platform_fee_gnf?: number
          platform_revenue_gnf?: number
          policy_snapshot?: Json
          resolved_at?: string | null
          source_module?: string
          state?: string
          tender: string
          updated_at?: string
        }
        Update: {
          accepted_at?: string | null
          cancelled_at?: string | null
          cash_due_gnf?: number
          claim_opened_at?: string | null
          claim_paid_gnf?: number
          claim_state?: string
          claims_exposure_gnf?: number
          collateral_gnf?: number
          completed_at?: string | null
          created_at?: string
          customer_hold_gnf?: number
          customer_user_id?: string
          declared_value_gnf?: number
          delivery_fee_gnf?: number
          documented_actual_value_gnf?: number | null
          documented_value_at?: string | null
          documented_value_by?: string | null
          documented_value_evidence_ref?: string | null
          driver_earning_gnf?: number
          driver_user_id?: string | null
          id?: string
          is_sandbox?: boolean
          mission_id?: string | null
          mission_type?: string
          order_key?: string
          package_id?: string
          picked_up_at?: string | null
          platform_fee_gnf?: number
          platform_revenue_gnf?: number
          policy_snapshot?: Json
          resolved_at?: string | null
          source_module?: string
          state?: string
          tender?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "package_runtime_package_id_fkey"
            columns: ["package_id"]
            isOneToOne: true
            referencedRelation: "package_deliveries"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_intents: {
        Row: {
          amount_gnf: number
          authorized_at: string | null
          cancelled_at: string | null
          captured_at: string | null
          captured_tx_id: string | null
          checkout_session_id: string | null
          created_at: string
          currency: string
          description: string | null
          environment: string
          expires_at: string | null
          id: string
          internal_reference: string
          is_sandbox: boolean
          ledger_release_tx_id: string | null
          metadata: Json
          payee_user_id: string | null
          payer_phone: string | null
          provider: Database["public"]["Enums"]["payment_provider"]
          provider_event_id: string | null
          provider_reference: string | null
          purpose: Database["public"]["Enums"]["payment_purpose"]
          rejected_at: string | null
          rejection_reason: string | null
          related_listing_id: string | null
          related_mission_id: string | null
          related_order_id: string | null
          related_store_id: string | null
          settlement_tx_id: string | null
          source_id: string | null
          source_module: string | null
          state: Database["public"]["Enums"]["payment_state"]
          test_run_id: string | null
          updated_at: string
          user_id: string
          wallet_hold_tx_id: string | null
        }
        Insert: {
          amount_gnf: number
          authorized_at?: string | null
          cancelled_at?: string | null
          captured_at?: string | null
          captured_tx_id?: string | null
          checkout_session_id?: string | null
          created_at?: string
          currency?: string
          description?: string | null
          environment?: string
          expires_at?: string | null
          id?: string
          internal_reference: string
          is_sandbox?: boolean
          ledger_release_tx_id?: string | null
          metadata?: Json
          payee_user_id?: string | null
          payer_phone?: string | null
          provider?: Database["public"]["Enums"]["payment_provider"]
          provider_event_id?: string | null
          provider_reference?: string | null
          purpose: Database["public"]["Enums"]["payment_purpose"]
          rejected_at?: string | null
          rejection_reason?: string | null
          related_listing_id?: string | null
          related_mission_id?: string | null
          related_order_id?: string | null
          related_store_id?: string | null
          settlement_tx_id?: string | null
          source_id?: string | null
          source_module?: string | null
          state?: Database["public"]["Enums"]["payment_state"]
          test_run_id?: string | null
          updated_at?: string
          user_id: string
          wallet_hold_tx_id?: string | null
        }
        Update: {
          amount_gnf?: number
          authorized_at?: string | null
          cancelled_at?: string | null
          captured_at?: string | null
          captured_tx_id?: string | null
          checkout_session_id?: string | null
          created_at?: string
          currency?: string
          description?: string | null
          environment?: string
          expires_at?: string | null
          id?: string
          internal_reference?: string
          is_sandbox?: boolean
          ledger_release_tx_id?: string | null
          metadata?: Json
          payee_user_id?: string | null
          payer_phone?: string | null
          provider?: Database["public"]["Enums"]["payment_provider"]
          provider_event_id?: string | null
          provider_reference?: string | null
          purpose?: Database["public"]["Enums"]["payment_purpose"]
          rejected_at?: string | null
          rejection_reason?: string | null
          related_listing_id?: string | null
          related_mission_id?: string | null
          related_order_id?: string | null
          related_store_id?: string | null
          settlement_tx_id?: string | null
          source_id?: string | null
          source_module?: string | null
          state?: Database["public"]["Enums"]["payment_state"]
          test_run_id?: string | null
          updated_at?: string
          user_id?: string
          wallet_hold_tx_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payment_intents_captured_tx_id_fkey"
            columns: ["captured_tx_id"]
            isOneToOne: false
            referencedRelation: "wallet_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_intents_ledger_release_tx_id_fkey"
            columns: ["ledger_release_tx_id"]
            isOneToOne: false
            referencedRelation: "wallet_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_intents_provider_event_id_fkey"
            columns: ["provider_event_id"]
            isOneToOne: false
            referencedRelation: "payment_provider_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_intents_settlement_tx_id_fkey"
            columns: ["settlement_tx_id"]
            isOneToOne: false
            referencedRelation: "wallet_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_intents_wallet_hold_tx_id_fkey"
            columns: ["wallet_hold_tx_id"]
            isOneToOne: false
            referencedRelation: "wallet_transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_provider_events: {
        Row: {
          amount_gnf: number
          created_at: string
          currency: string
          environment: string
          event_type: string
          id: string
          is_sandbox: boolean
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
          test_run_id: string | null
        }
        Insert: {
          amount_gnf: number
          created_at?: string
          currency?: string
          environment?: string
          event_type?: string
          id?: string
          is_sandbox?: boolean
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
          test_run_id?: string | null
        }
        Update: {
          amount_gnf?: number
          created_at?: string
          currency?: string
          environment?: string
          event_type?: string
          id?: string
          is_sandbox?: boolean
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
          test_run_id?: string | null
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
          environment: string
          event_type: Database["public"]["Enums"]["payment_recon_event"]
          id: string
          intent_id: string
          is_sandbox: boolean
          payload: Json
          provider: Database["public"]["Enums"]["payment_provider"] | null
          provider_reference: string | null
          test_run_id: string | null
        }
        Insert: {
          actor_user_id?: string | null
          created_at?: string
          environment?: string
          event_type: Database["public"]["Enums"]["payment_recon_event"]
          id?: string
          intent_id: string
          is_sandbox?: boolean
          payload?: Json
          provider?: Database["public"]["Enums"]["payment_provider"] | null
          provider_reference?: string | null
          test_run_id?: string | null
        }
        Update: {
          actor_user_id?: string | null
          created_at?: string
          environment?: string
          event_type?: Database["public"]["Enums"]["payment_recon_event"]
          id?: string
          intent_id?: string
          is_sandbox?: boolean
          payload?: Json
          provider?: Database["public"]["Enums"]["payment_provider"] | null
          provider_reference?: string | null
          test_run_id?: string | null
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
      payment_refund_requests: {
        Row: {
          amount_gnf: number
          created_at: string
          environment: string
          fee_gnf: number
          id: string
          is_sandbox: boolean
          metadata: Json
          original_amount_gnf: number
          payment_intent_id: string
          provider: string
          provider_event_id: string | null
          provider_reference: string | null
          reason: string | null
          requested_at: string
          resolved_at: string | null
          source_id: string
          source_module: string
          status: string
          support_issue_id: string | null
          test_run_id: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_gnf: number
          created_at?: string
          environment?: string
          fee_gnf?: number
          id?: string
          is_sandbox?: boolean
          metadata?: Json
          original_amount_gnf: number
          payment_intent_id: string
          provider?: string
          provider_event_id?: string | null
          provider_reference?: string | null
          reason?: string | null
          requested_at?: string
          resolved_at?: string | null
          source_id: string
          source_module: string
          status?: string
          support_issue_id?: string | null
          test_run_id?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_gnf?: number
          created_at?: string
          environment?: string
          fee_gnf?: number
          id?: string
          is_sandbox?: boolean
          metadata?: Json
          original_amount_gnf?: number
          payment_intent_id?: string
          provider?: string
          provider_event_id?: string | null
          provider_reference?: string | null
          reason?: string | null
          requested_at?: string
          resolved_at?: string | null
          source_id?: string
          source_module?: string
          status?: string
          support_issue_id?: string | null
          test_run_id?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_refund_requests_payment_intent_id_fkey"
            columns: ["payment_intent_id"]
            isOneToOne: false
            referencedRelation: "payment_intents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_refund_requests_provider_event_id_fkey"
            columns: ["provider_event_id"]
            isOneToOne: false
            referencedRelation: "payment_provider_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_refund_requests_support_issue_id_fkey"
            columns: ["support_issue_id"]
            isOneToOne: false
            referencedRelation: "support_issues"
            referencedColumns: ["id"]
          },
        ]
      }
      payout_orders: {
        Row: {
          created_at: string
          created_by: string | null
          destination_msisdn: string
          environment: string
          evidence_id: string | null
          expected_provider_transfer_gnf: number
          fee_borne_by: string
          id: string
          merchant_liability_debit_gnf: number
          merchant_store_id: string | null
          order_key: string
          party_type: Database["public"]["Enums"]["party_type"]
          party_user_id: string
          policy_snapshot: Json
          provider: string
          provider_fee_gnf: number
          recipient_net_gnf: number
          reject_reason: string | null
          released_at: string | null
          requested_principal_gnf: number
          reservation_gnf: number
          settled_at: string | null
          settled_gnf: number
          source_kind: string
          source_request_id: string | null
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          destination_msisdn: string
          environment: string
          evidence_id?: string | null
          expected_provider_transfer_gnf: number
          fee_borne_by?: string
          id?: string
          merchant_liability_debit_gnf: number
          merchant_store_id?: string | null
          order_key: string
          party_type: Database["public"]["Enums"]["party_type"]
          party_user_id: string
          policy_snapshot?: Json
          provider?: string
          provider_fee_gnf?: number
          recipient_net_gnf: number
          reject_reason?: string | null
          released_at?: string | null
          requested_principal_gnf: number
          reservation_gnf: number
          settled_at?: string | null
          settled_gnf?: number
          source_kind: string
          source_request_id?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          destination_msisdn?: string
          environment?: string
          evidence_id?: string | null
          expected_provider_transfer_gnf?: number
          fee_borne_by?: string
          id?: string
          merchant_liability_debit_gnf?: number
          merchant_store_id?: string | null
          order_key?: string
          party_type?: Database["public"]["Enums"]["party_type"]
          party_user_id?: string
          policy_snapshot?: Json
          provider?: string
          provider_fee_gnf?: number
          recipient_net_gnf?: number
          reject_reason?: string | null
          released_at?: string | null
          requested_principal_gnf?: number
          reservation_gnf?: number
          settled_at?: string | null
          settled_gnf?: number
          source_kind?: string
          source_request_id?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      payout_provider_evidence: {
        Row: {
          amount_gnf: number | null
          created_at: string
          environment: string | null
          fee_gnf: number | null
          id: string
          mismatch_reason: string | null
          net_gnf: number | null
          normalized_reference: string | null
          payout_order_id: string | null
          provider: string
          provider_reference: string
          provider_status: string | null
          raw: Json
          recipient_msisdn: string | null
          reconciled_at: string | null
          reconciliation_state: string
          recorded_by: string | null
          transferred_at: string | null
          updated_at: string
        }
        Insert: {
          amount_gnf?: number | null
          created_at?: string
          environment?: string | null
          fee_gnf?: number | null
          id?: string
          mismatch_reason?: string | null
          net_gnf?: number | null
          normalized_reference?: string | null
          payout_order_id?: string | null
          provider: string
          provider_reference: string
          provider_status?: string | null
          raw?: Json
          recipient_msisdn?: string | null
          reconciled_at?: string | null
          reconciliation_state?: string
          recorded_by?: string | null
          transferred_at?: string | null
          updated_at?: string
        }
        Update: {
          amount_gnf?: number | null
          created_at?: string
          environment?: string | null
          fee_gnf?: number | null
          id?: string
          mismatch_reason?: string | null
          net_gnf?: number | null
          normalized_reference?: string | null
          payout_order_id?: string | null
          provider?: string
          provider_reference?: string
          provider_status?: string | null
          raw?: Json
          recipient_msisdn?: string | null
          reconciled_at?: string | null
          reconciliation_state?: string
          recorded_by?: string | null
          transferred_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payout_provider_evidence_payout_order_id_fkey"
            columns: ["payout_order_id"]
            isOneToOne: false
            referencedRelation: "payout_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      payout_settlement_allocations: {
        Row: {
          amount_gnf: number
          created_at: string
          id: string
          merchant_payable_id: string
          payout_order_id: string
        }
        Insert: {
          amount_gnf: number
          created_at?: string
          id?: string
          merchant_payable_id: string
          payout_order_id: string
        }
        Update: {
          amount_gnf?: number
          created_at?: string
          id?: string
          merchant_payable_id?: string
          payout_order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "payout_settlement_allocations_merchant_payable_id_fkey"
            columns: ["merchant_payable_id"]
            isOneToOne: false
            referencedRelation: "merchant_payables"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payout_settlement_allocations_payout_order_id_fkey"
            columns: ["payout_order_id"]
            isOneToOne: false
            referencedRelation: "payout_orders"
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
      provider_fee_schedules: {
        Row: {
          created_at: string
          created_by: string | null
          effective_from: string
          enabled: boolean
          fee_bps: number
          fee_fixed_gnf: number
          id: string
          max_fee_gnf: number | null
          min_fee_gnf: number
          note: string | null
          passthrough_to_recipient: boolean
          provider: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          effective_from?: string
          enabled?: boolean
          fee_bps?: number
          fee_fixed_gnf?: number
          id?: string
          max_fee_gnf?: number | null
          min_fee_gnf?: number
          note?: string | null
          passthrough_to_recipient?: boolean
          provider?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          effective_from?: string
          enabled?: boolean
          fee_bps?: number
          fee_fixed_gnf?: number
          id?: string
          max_fee_gnf?: number | null
          min_fee_gnf?: number
          note?: string | null
          passthrough_to_recipient?: boolean
          provider?: string
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
          ride_mode: Database["public"]["Enums"]["ride_mode"] | null
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
          ride_mode?: Database["public"]["Enums"]["ride_mode"] | null
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
          ride_mode?: Database["public"]["Enums"]["ride_mode"] | null
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
      sandbox_test_runs: {
        Row: {
          archived_at: string | null
          archived_by: string | null
          completed_at: string | null
          completed_by: string | null
          created_at: string
          created_by: string | null
          id: string
          label: string | null
          metadata: Json
          notes: string | null
          started_at: string
          status: string
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          archived_by?: string | null
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          created_by?: string | null
          id: string
          label?: string | null
          metadata?: Json
          notes?: string | null
          started_at?: string
          status?: string
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          archived_by?: string | null
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          label?: string | null
          metadata?: Json
          notes?: string | null
          started_at?: string
          status?: string
          updated_at?: string
        }
        Relationships: []
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
          environment: string
          expires_at: string
          id: string
          matched_event_id: string | null
          matched_provider_transaction_id: string | null
          notes: string | null
          provider: string
          receiving_account_id: string | null
          reference: string
          review_reason: string | null
          status: Database["public"]["Enums"]["topup_status"]
          target_party_type: string
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
          environment?: string
          expires_at?: string
          id?: string
          matched_event_id?: string | null
          matched_provider_transaction_id?: string | null
          notes?: string | null
          provider?: string
          receiving_account_id?: string | null
          reference: string
          review_reason?: string | null
          status?: Database["public"]["Enums"]["topup_status"]
          target_party_type?: string
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
          environment?: string
          expires_at?: string
          id?: string
          matched_event_id?: string | null
          matched_provider_transaction_id?: string | null
          notes?: string | null
          provider?: string
          receiving_account_id?: string | null
          reference?: string
          review_reason?: string | null
          status?: Database["public"]["Enums"]["topup_status"]
          target_party_type?: string
          transaction_id?: string | null
          updated_at?: string
          user_phone?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "topup_requests_matched_event_id_fkey"
            columns: ["matched_event_id"]
            isOneToOne: false
            referencedRelation: "payment_provider_events"
            referencedColumns: ["id"]
          },
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
      welcome_email_dispatches: {
        Row: {
          created_at: string
          error_message: string | null
          http_request_id: number | null
          message_key: string
          recipient_email: string
          template_version: string
          user_id: string
        }
        Insert: {
          created_at?: string
          error_message?: string | null
          http_request_id?: number | null
          message_key: string
          recipient_email: string
          template_version?: string
          user_id: string
        }
        Update: {
          created_at?: string
          error_message?: string | null
          http_request_id?: number | null
          message_key?: string
          recipient_email?: string
          template_version?: string
          user_id?: string
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
      ledger_account_totals: {
        Row: {
          account_code: string | null
          kind: string | null
          net_debit_gnf: number | null
          posting_count: number | null
          restricted: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "ledger_postings_account_code_fkey"
            columns: ["account_code"]
            isOneToOne: false
            referencedRelation: "ledger_accounts"
            referencedColumns: ["code"]
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
      _as_user_claims: { Args: { p_user: string }; Returns: string }
      _cancellation_compute: {
        Args: {
          p_delivery_fee_gnf?: number
          p_fare_gnf?: number
          p_merchandise_subtotal_gnf?: number
          p_responsible_party?: string
          p_snapshot: Json
          p_stage: string
        }
        Returns: Json
      }
      _capture_revenue_account: { Args: { p_kind: string }; Returns: string }
      _cash_order_accept_internal: {
        Args: { p_driver: string; p_source_id: string; p_source_module: string }
        Returns: Json
      }
      _cash_order_capture_platform_fee: {
        Args: { p_actor?: string; p_source_id: string; p_source_module: string }
        Returns: Json
      }
      _cash_order_complete_internal: {
        Args: {
          p_actor: string
          p_from_dispute?: boolean
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      _cash_order_deactivate_source: {
        Args: {
          p_mission_id: string
          p_source_id: string
          p_source_module: string
        }
        Returns: undefined
      }
      _cash_order_economics: { Args: { p_facts: Json }; Returns: Json }
      _cash_order_facts: {
        Args: { p_source_id: string; p_source_module: string }
        Returns: Json
      }
      _cash_order_is_cash: {
        Args: { p_source_id: string; p_source_module: string }
        Returns: boolean
      }
      _chop_pay_accept_internal: {
        Args: { p_driver: string; p_source_id: string; p_source_module: string }
        Returns: Json
      }
      _chop_pay_cancel_internal: {
        Args: {
          p_actor: string
          p_reason: string
          p_responsible_party: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      _chop_pay_complete_internal: {
        Args: {
          p_actor: string
          p_from_dispute?: boolean
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      _chop_pay_customer_capture_internal: {
        Args: {
          p_actor?: string
          p_amount: number
          p_purpose: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      _chop_pay_customer_hold_internal: {
        Args: { p_actor: string; p_source_id: string; p_source_module: string }
        Returns: Json
      }
      _chop_pay_customer_release_internal: {
        Args: {
          p_actor?: string
          p_reason?: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      _chop_pay_deactivate_source: {
        Args: {
          p_mission_id: string
          p_source_id: string
          p_source_module: string
        }
        Returns: undefined
      }
      _chop_pay_economics: { Args: { p_facts: Json }; Returns: Json }
      _chop_pay_facts: {
        Args: { p_source_id: string; p_source_module: string }
        Returns: Json
      }
      _chop_pay_is_chop_pay: {
        Args: { p_source_id: string; p_source_module: string }
        Returns: boolean
      }
      _chop_pay_merchant_capture_reverse_internal: {
        Args: {
          p_actor?: string
          p_reason: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      _customer_cancellation_debt_create_internal: {
        Args: {
          p_actor?: string
          p_customer: string
          p_delivery_fee_gnf?: number
          p_fare_gnf?: number
          p_is_sandbox?: boolean
          p_merchandise_subtotal_gnf?: number
          p_mission_type: string
          p_policy_snapshot?: Json
          p_preparation_started?: boolean
          p_responsible_party?: string
          p_source_id: string
          p_source_module: string
          p_stage: string
        }
        Returns: Json
      }
      _customer_cancellation_debt_settle_internal: {
        Args: { p_actor: string; p_amount_gnf: number; p_debt_id: string }
        Returns: Json
      }
      _customer_cash_restricted: { Args: { p_user: string }; Returns: boolean }
      _driver_exact_hold_place_internal: {
        Args: {
          p_amount: number
          p_basis_value_gnf?: number
          p_driver: string
          p_is_sandbox?: boolean
          p_kind?: string
          p_mission_type: string
          p_policy_id?: string
          p_snapshot?: Json
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      _driver_finance_eligible: { Args: { p_driver: string }; Returns: boolean }
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
      _driver_mission_hold_release_internal: {
        Args: {
          p_actor?: string
          p_kind?: string
          p_reason?: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      _envoyer_enabled: { Args: never; Returns: boolean }
      _finance_evidence_claim: {
        Args: {
          p_actor: string
          p_amount: number
          p_evidence_ref: string
          p_target: string
          p_usage_kind: string
        }
        Returns: undefined
      }
      _finance_flag: { Args: { p_key: string }; Returns: boolean }
      _finance_privileged: { Args: { p_caller: string }; Returns: boolean }
      _finance_treasury_facts: { Args: never; Returns: Json }
      _finance_treasury_gate: { Args: never; Returns: string }
      _hold_account: { Args: { p_kind: string }; Returns: string }
      _is_approved_service_agent: {
        Args: { _user_id: string }
        Returns: boolean
      }
      _is_god_admin: { Args: { _user: string }; Returns: boolean }
      _is_ops_or_god_admin: { Args: { _user: string }; Returns: boolean }
      _leader_group_id: { Args: { _uid: string }; Returns: string }
      _ledger_post: {
        Args: {
          p_action: string
          p_actor?: string
          p_evidence?: string
          p_is_sandbox?: boolean
          p_journal_key: string
          p_lines: Json
          p_mission_type?: string
          p_policy?: Json
          p_reason?: string
          p_reverses?: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      _ledger_reverse: {
        Args: {
          p_actor?: string
          p_evidence?: string
          p_original_key: string
          p_reason: string
        }
        Returns: Json
      }
      _map_distance_meters: {
        Args: { a_lat: number; a_lng: number; b_lat: number; b_lng: number }
        Returns: number
      }
      _merchant_payable_create_internal: {
        Args: {
          p_deduction_gnf?: number
          p_is_sandbox?: boolean
          p_merchant_store_id: string
          p_mission_type?: string
          p_snapshot?: Json
          p_source_id: string
          p_source_module: string
          p_subtotal_gnf: number
        }
        Returns: Json
      }
      _merchant_payable_fund_internal: {
        Args: {
          p_actor?: string
          p_funding_source: string
          p_merchant_store_id: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      _merchant_payable_reverse_internal: {
        Args: {
          p_actor?: string
          p_beneficiary: string
          p_merchant_store_id: string
          p_reason: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      _merchant_settlement_request_queue_internal: {
        Args: {
          p_amount_gnf: number
          p_note: string
          p_request_key: string
          p_store_id: string
        }
        Returns: {
          amount_gnf: number
          channel: string
          created_at: string
          currency: string
          eligible_snapshot_gnf: number
          evidence_ref: string | null
          id: string
          merchant_store_id: string
          merchant_user_id: string
          note: string | null
          reject_reason: string | null
          request_key: string
          reviewed_at: string | null
          reviewed_by: string | null
          settled_at: string | null
          status: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "merchant_settlement_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      _mission_cash_source: {
        Args: { _m: Database["public"]["Tables"]["missions"]["Row"] }
        Returns: Json
      }
      _normalize_guinea_phone: { Args: { p_raw: string }; Returns: string }
      _notify_account_event: {
        Args: {
          _body: string
          _template: string
          _title: string
          _user: string
        }
        Returns: undefined
      }
      _om_sandbox_register_test_run: {
        Args: { p_actor?: string; p_test_run_id: string }
        Returns: undefined
      }
      _om_sandbox_require_active: { Args: never; Returns: undefined }
      _package_accept_internal: {
        Args: { p_driver: string; p_package_id: string }
        Returns: Json
      }
      _package_authorize_internal: {
        Args: { p_actor?: string; p_package_id: string }
        Returns: Json
      }
      _package_cancel_release_internal:
        | {
            Args: { p_actor?: string; p_package_id: string; p_reason?: string }
            Returns: Json
          }
        | {
            Args: {
              p_actor?: string
              p_package_id: string
              p_reason?: string
              p_responsible_party?: string
            }
            Returns: Json
          }
      _package_choppay_capture_internal: {
        Args: {
          p_actor?: string
          p_amount: number
          p_package_id: string
          p_purpose: string
        }
        Returns: Json
      }
      _package_choppay_hold_internal: {
        Args: { p_actor?: string; p_package_id: string }
        Returns: Json
      }
      _package_choppay_release_internal: {
        Args: { p_actor?: string; p_package_id: string; p_reason?: string }
        Returns: Json
      }
      _package_claim_freeze_internal: {
        Args: { p_actor?: string; p_package_id: string; p_reason: string }
        Returns: Json
      }
      _package_collateral_capture_internal: {
        Args: {
          p_actor: string
          p_amount: number
          p_evidence_ref: string
          p_package_id: string
          p_reason: string
        }
        Returns: Json
      }
      _package_complete_internal: {
        Args: { p_actor?: string; p_package_id: string }
        Returns: Json
      }
      _package_dispatch_internal: {
        Args: { p_package_id: string }
        Returns: Json
      }
      _package_economics: {
        Args: {
          p_declared_value_gnf: number
          p_delivery_fee_gnf: number
          p_is_sandbox?: boolean
          p_tender: string
        }
        Returns: Json
      }
      _package_new_code: { Args: never; Returns: string }
      _package_notify: {
        Args: {
          _payload?: Json
          _priority?: Database["public"]["Enums"]["notification_priority"]
          _template: string
          _user_id: string
        }
        Returns: undefined
      }
      _payout_env: { Args: never; Returns: string }
      _payout_evidence_mismatch_reason: {
        Args: {
          p_amount: number
          p_environment: string
          p_fee: number
          p_msisdn: string
          p_order: Database["public"]["Tables"]["payout_orders"]["Row"]
          p_provider: string
          p_reference: string
          p_status: string
        }
        Returns: string
      }
      _payout_fee_snapshot: {
        Args: { p_principal: number; p_provider: string }
        Returns: Json
      }
      _payout_order_create_internal: {
        Args: {
          p_actor: string
          p_msisdn: string
          p_order_key: string
          p_party_type: Database["public"]["Enums"]["party_type"]
          p_party_user_id: string
          p_principal: number
          p_provider: string
          p_source_kind: string
          p_source_request_id: string
          p_store_id: string
        }
        Returns: {
          created_at: string
          created_by: string | null
          destination_msisdn: string
          environment: string
          evidence_id: string | null
          expected_provider_transfer_gnf: number
          fee_borne_by: string
          id: string
          merchant_liability_debit_gnf: number
          merchant_store_id: string | null
          order_key: string
          party_type: Database["public"]["Enums"]["party_type"]
          party_user_id: string
          policy_snapshot: Json
          provider: string
          provider_fee_gnf: number
          recipient_net_gnf: number
          reject_reason: string | null
          released_at: string | null
          requested_principal_gnf: number
          reservation_gnf: number
          settled_at: string | null
          settled_gnf: number
          source_kind: string
          source_request_id: string | null
          status: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "payout_orders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      _payout_settle_internal: {
        Args: { p_actor: string; p_evidence_id: string; p_order_id: string }
        Returns: Json
      }
      _promo_consume: {
        Args: { p_amount: number; p_driver: string }
        Returns: number
      }
      _promo_restore: {
        Args: { p_amount: number; p_driver: string }
        Returns: number
      }
      _qa_node0_course: { Args: never; Returns: Json }
      _qa_node1_bonbonna: { Args: never; Returns: Json }
      _qa_node1_bonbonna_full: { Args: never; Returns: Json }
      _qa_node1_bonbonna_matrix: { Args: never; Returns: Json }
      _qa_node1_bonbonna_sweeper: { Args: never; Returns: Json }
      _qa_node2_taxi_full: { Args: never; Returns: Json }
      _qa_node3_repas_r1_r4: { Args: never; Returns: Json }
      _qa_s13_admin: { Args: { p_id: string }; Returns: undefined }
      _qa_s13_driver: {
        Args: { p_bal: number; p_tag: string; p_uid: string }
        Returns: undefined
      }
      _qa_s13_flag: {
        Args: { p_key: string; p_val: boolean }
        Returns: undefined
      }
      _qa_s13_ok: {
        Args: { p_detail?: string; p_label: string; p_ok: boolean }
        Returns: Json
      }
      _qa_s13_om_case: {
        Args: {
          p_acct_req: string
          p_amount: number
          p_code: string
          p_ev_acct: string
          p_ev_amount: number
          p_ev_phone: string
          p_god: string
          p_party: string
          p_user: string
        }
        Returns: Json
      }
      _qa_s13_om_forced: {
        Args: {
          p_acct_ok: string
          p_acct_other: string
          p_amount: number
          p_code: string
          p_mutate: string
          p_user: string
        }
        Returns: Json
      }
      _qa_s13_om_rolecall: {
        Args: {
          p_a1: string
          p_a2: string
          p_role: string
          p_sql: string
          p_uid: string
        }
        Returns: string
      }
      _qa_s13_rls_probe: {
        Args: {
          p_bucket: string
          p_name: string
          p_op: string
          p_role: string
          p_uid: string
        }
        Returns: Json
      }
      _qa_s13_run1: { Args: never; Returns: Json }
      _qa_s13_run2: { Args: never; Returns: Json }
      _qa_s13_run3: { Args: never; Returns: Json }
      _qa_s13_run4: { Args: never; Returns: Json }
      _qa_s13_run5: { Args: never; Returns: Json }
      _qa_s13_run6: { Args: never; Returns: Json }
      _qa_s13_run7: { Args: never; Returns: Json }
      _qa_s13_summary: { Args: { p_part: number; r: Json }; Returns: Json }
      _qa_s13_user: {
        Args: { p_id: string; p_tag: string }
        Returns: undefined
      }
      _qa_s13_wallet: {
        Args: {
          p_bal: number
          p_held: number
          p_owner: string
          p_party: Database["public"]["Enums"]["party_type"]
        }
        Returns: string
      }
      _ride_expire_unfulfilled_internal: {
        Args: { p_ride_id: string }
        Returns: Json
      }
      _ride_mission_type: { Args: { p_mode: string }; Returns: string }
      _ride_payment_mode: {
        Args: { p_ride: Database["public"]["Tables"]["rides"]["Row"] }
        Returns: string
      }
      _ride_required_vehicle: {
        Args: { p_mode: string }
        Returns: Database["public"]["Enums"]["driver_vehicle_type"]
      }
      _topup_stage: {
        Args: {
          p_code_at: string
          p_expires_at: string
          p_status: string
          p_tx: string
        }
        Returns: string
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
      admin_backfill_missing_driver_earnings: {
        Args: { p_dry_run?: boolean; p_limit?: number; p_reason?: string }
        Returns: Json
      }
      admin_ban_user: {
        Args: { _expires_at?: string; _reason: string; _target: string }
        Returns: Json
      }
      admin_cash_order_dispute_resolve: {
        Args: {
          p_outcome: string
          p_reason?: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      admin_check_email_reuse_blocker: {
        Args: { p_email: string }
        Returns: Json
      }
      admin_chop_pay_cancel: {
        Args: {
          p_reason?: string
          p_responsible_party: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      admin_chop_pay_dispute_resolve: {
        Args: {
          p_outcome: string
          p_reason?: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      admin_clear_must_change_password: { Args: never; Returns: Json }
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
      admin_link_restaurant_to_merchant_store: {
        Args: { p_merchant_store_id: string; p_restaurant_id: string }
        Returns: Json
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
      admin_manual_om_credit: {
        Args: { p_event_id: string; p_topup_request_id: string }
        Returns: Json
      }
      admin_marche_capture_and_settle_offer: {
        Args: { p_offer_id: string; p_reason?: string }
        Returns: Json
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
          commune: string | null
          cover_url: string | null
          created_at: string
          created_by: string | null
          delivery_available: boolean
          district: string | null
          id: string
          id_photo_path: string | null
          landmark: string | null
          landmark_note: string | null
          latitude: number | null
          location_accuracy_m: number | null
          location_capture_method: string | null
          location_confirmed_at: string | null
          location_notes: string | null
          location_source: string | null
          location_submission_status: string
          location_submitted_at: string | null
          location_verified_at: string | null
          location_verified_by: string | null
          longitude: number | null
          map_place_id: string | null
          market_id: string | null
          market_name: string | null
          member_since: string
          merchant_account_number: string | null
          merchant_qr_payload: string | null
          merchant_status: string
          name: string
          onboarding_branch: string
          onboarding_status: string
          operating_hours: string | null
          owner_name: string | null
          owner_user_id: string
          phone: string | null
          product_categories: string[]
          rejection_reason: string | null
          selfie_photo_path: string | null
          service_agent_decided_at: string | null
          service_agent_decided_by: string | null
          service_agent_notes: string | null
          service_agent_requested: boolean
          service_agent_status: string
          slug: string
          stall_number: string | null
          status: string
          storefront_photo_path: string | null
          submitted_at: string | null
          updated_at: string
          verification_state: string
          wants_food: boolean
          wants_marketplace: boolean
          wants_wallet_agent: boolean
          whatsapp: string | null
        }
        SetofOptions: {
          from: "*"
          to: "merchant_stores"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_merchant_service_agent_decision: {
        Args: { _decision: string; _notes?: string; _store_id: string }
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
          commune: string | null
          cover_url: string | null
          created_at: string
          created_by: string | null
          delivery_available: boolean
          district: string | null
          id: string
          id_photo_path: string | null
          landmark: string | null
          landmark_note: string | null
          latitude: number | null
          location_accuracy_m: number | null
          location_capture_method: string | null
          location_confirmed_at: string | null
          location_notes: string | null
          location_source: string | null
          location_submission_status: string
          location_submitted_at: string | null
          location_verified_at: string | null
          location_verified_by: string | null
          longitude: number | null
          map_place_id: string | null
          market_id: string | null
          market_name: string | null
          member_since: string
          merchant_account_number: string | null
          merchant_qr_payload: string | null
          merchant_status: string
          name: string
          onboarding_branch: string
          onboarding_status: string
          operating_hours: string | null
          owner_name: string | null
          owner_user_id: string
          phone: string | null
          product_categories: string[]
          rejection_reason: string | null
          selfie_photo_path: string | null
          service_agent_decided_at: string | null
          service_agent_decided_by: string | null
          service_agent_notes: string | null
          service_agent_requested: boolean
          service_agent_status: string
          slug: string
          stall_number: string | null
          status: string
          storefront_photo_path: string | null
          submitted_at: string | null
          updated_at: string
          verification_state: string
          wants_food: boolean
          wants_marketplace: boolean
          wants_wallet_agent: boolean
          whatsapp: string | null
        }
        SetofOptions: {
          from: "*"
          to: "merchant_stores"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_package_claim_resolve: {
        Args: {
          p_evidence_ref: string
          p_outcome: string
          p_package_id: string
          p_pay_customer_gnf?: number
          p_reason: string
        }
        Returns: Json
      }
      admin_package_claim_set_documented_value: {
        Args: {
          p_documented_actual_value_gnf: number
          p_evidence_ref: string
          p_package_id: string
          p_reason: string
        }
        Returns: Json
      }
      admin_pre_purge_test_user: { Args: { _target: string }; Returns: Json }
      admin_preview_marche_payment_intents:
        | {
            Args: { p_limit?: number }
            Returns: {
              amount_gnf: number
              authorized_at: string
              buyer_user_id: string
              captured_tx_id: string
              created_at: string
              listing_id: string
              listing_title: string
              merchant_store_id: string
              merchant_user_id: string
              offer_id: string
              offer_status: string
              payment_intent_id: string
              payment_intent_state: Database["public"]["Enums"]["payment_state"]
              payment_status: string
              settlement_tx_id: string
              wallet_hold_tx_id: string
            }[]
          }
        | {
            Args: { p_include_sandbox?: boolean; p_limit?: number }
            Returns: {
              amount_gnf: number
              authorized_at: string
              buyer_user_id: string
              captured_tx_id: string
              created_at: string
              listing_id: string
              listing_title: string
              merchant_store_id: string
              merchant_user_id: string
              offer_id: string
              offer_status: string
              payment_intent_id: string
              payment_intent_state: Database["public"]["Enums"]["payment_state"]
              payment_status: string
              settlement_tx_id: string
              wallet_hold_tx_id: string
            }[]
          }
      admin_preview_marche_payment_settlement: {
        Args: { p_limit?: number }
        Returns: {
          amount_gnf: number
          buyer_user_id: string
          created_at: string
          eligible_for_capture: boolean
          eligible_for_settlement: boolean
          fulfillment_status: string
          listing_id: string
          listing_title: string
          merchant_store_id: string
          offer_id: string
          offer_status: string
          payment_intent_id: string
          payment_intent_state: string
          payment_status: string
          reason: string
          seller_user_id: string
          settlement_state: string
        }[]
      }
      admin_preview_missing_driver_earnings: {
        Args: never
        Returns: {
          calculated_driver_earn_gnf: number
          client_id: string
          completed_at: string
          driver_earning_gnf: number
          driver_id: string
          eligible: boolean
          existing_wallet_tx_count: number
          fare_gnf: number
          hold_tx_id: string
          platform_fee_gnf: number
          reason: string
          ride_id: string
          ride_status: string
        }[]
      }
      admin_preview_missing_merchant_revenue: {
        Args: { p_source_module?: string }
        Returns: {
          amount_gnf: number
          created_at: string
          merchant_owner_user_id: string
          merchant_store_id: string
          metadata: Json
          reference: string
          source_id: string
          source_module: string
          status: string
          tx_id: string
        }[]
      }
      admin_preview_missing_mission_earnings: {
        Args: never
        Returns: {
          courier_id: string
          delivered_at: string
          earning_amount_gnf: number
          eligible: boolean
          mission_id: string
          mission_type: string
          reason: string
        }[]
      }
      admin_preview_p2p_transfers: {
        Args: { p_limit?: number }
        Returns: {
          amount_gnf: number
          created_at: string
          note: string
          recipient_user_id: string
          reference: string
          sender_user_id: string
          status: string
        }[]
      }
      admin_preview_payment_intents:
        | {
            Args: {
              p_limit?: number
              p_source_module?: string
              p_state?: string
            }
            Returns: {
              amount_gnf: number
              cancelled_at: string
              captured_at: string
              captured_tx_id: string
              created_at: string
              id: string
              internal_reference: string
              merchant_store_id: string
              metadata: Json
              payee_user_id: string
              payer_user_id: string
              provider: Database["public"]["Enums"]["payment_provider"]
              settlement_tx_id: string
              source_id: string
              source_module: string
              state: Database["public"]["Enums"]["payment_state"]
              wallet_hold_tx_id: string
            }[]
          }
        | {
            Args: {
              p_include_sandbox?: boolean
              p_limit?: number
              p_source_module?: string
              p_state?: string
            }
            Returns: {
              amount_gnf: number
              cancelled_at: string
              captured_at: string
              captured_tx_id: string
              created_at: string
              id: string
              internal_reference: string
              is_sandbox: boolean
              merchant_store_id: string
              metadata: Json
              payee_user_id: string
              payer_user_id: string
              provider: Database["public"]["Enums"]["payment_provider"]
              settlement_tx_id: string
              source_id: string
              source_module: string
              state: Database["public"]["Enums"]["payment_state"]
              test_run_id: string
              wallet_hold_tx_id: string
            }[]
          }
      admin_preview_repas_payment_settlement: {
        Args: { p_limit?: number }
        Returns: {
          created_at: string
          eligible_for_capture: boolean
          eligible_for_settlement: boolean
          food_order_id: string
          merchant_store_id: string
          payment_intent_id: string
          payment_intent_state: string
          payment_method: string
          payment_status: string
          reason: string
          restaurant_id: string
          settlement_state: string
          subtotal_gnf: number
          user_id: string
        }[]
      }
      admin_preview_service_agent_cashins: {
        Args: { p_limit?: number }
        Returns: {
          agent_user_id: string
          amount_gnf: number
          created_at: string
          customer_user_id: string
          merchant_store_id: string
          note: string
          reference: string
          status: Database["public"]["Enums"]["txn_status"]
          transaction_id: string
        }[]
      }
      admin_promotional_credit_treasury: { Args: never; Returns: Json }
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
      admin_repas_capture_and_settle_order: {
        Args: { p_food_order_id: string; p_reason?: string }
        Returns: Json
      }
      admin_request_driver_info: {
        Args: { p_missing: string[]; p_note: string; p_user_id: string }
        Returns: undefined
      }
      admin_retry_om_credit: { Args: { p_event_id: string }; Returns: Json }
      admin_reverse_starter_credit: {
        Args: { p_driver: string; p_reason: string }
        Returns: Json
      }
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
      admin_set_driver_capability: {
        Args: { _capability: string; _driver_user_id: string; _grant: boolean }
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
      admin_set_feature_flag: {
        Args: { p_enabled: boolean; p_key: string; p_note?: string }
        Returns: {
          description: string | null
          enabled: boolean
          key: string
          updated_at: string
          updated_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "feature_flags"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_set_finance_delegation: {
        Args: { p_note?: string; p_provider_fee_to_finance_admin: boolean }
        Returns: Json
      }
      admin_set_finance_policy: {
        Args: {
          p_cancel_after_dispatch_bps?: number
          p_cancel_basis?: string
          p_cancel_before_dispatch_bps?: number
          p_cash_funding_max_gnf?: number
          p_cash_funding_mode?: string
          p_cash_funding_pct_bps?: number
          p_claims_exposure_max_gnf?: number
          p_collateral_basis?: string
          p_collateral_fixed_gnf?: number
          p_collateral_max_gnf?: number
          p_collateral_min_gnf?: number
          p_collateral_mode?: string
          p_collateral_pct_bps?: number
          p_commission_bps?: number
          p_effective_from?: string
          p_fee_basis?: string
          p_fixed_commission_gnf?: number
          p_max_declared_value_gnf?: number
          p_min_driver_balance_gnf?: number
          p_mission_type: string
          p_note?: string
          p_require_collateral_before_offer?: boolean
          p_transaction_fee_bps?: number
        }
        Returns: {
          cancel_after_dispatch_bps: number
          cancel_basis: string
          cancel_before_dispatch_bps: number
          cash_funding_max_gnf: number | null
          cash_funding_mode: string
          cash_funding_pct_bps: number
          claims_exposure_max_gnf: number | null
          collateral_basis: string
          collateral_fixed_gnf: number
          collateral_max_gnf: number | null
          collateral_min_gnf: number
          collateral_mode: string
          collateral_pct_bps: number
          commission_bps: number
          created_at: string
          created_by: string | null
          effective_from: string
          enabled: boolean
          fee_basis: string
          fixed_commission_gnf: number
          id: string
          max_declared_value_gnf: number | null
          min_driver_balance_gnf: number
          mission_type: string
          note: string | null
          require_collateral_before_offer: boolean
          transaction_fee_bps: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "finance_policies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_set_merchant_location_status: {
        Args: { p_note?: string; p_status: string; p_store_id: string }
        Returns: undefined
      }
      admin_set_merchant_settlement_policy: {
        Args: {
          p_cadence?: string
          p_configured?: boolean
          p_effective_from?: string
          p_fee_bps?: number
          p_fee_fixed_gnf?: number
          p_fee_passthrough?: boolean
          p_max_settlement_gnf?: number
          p_min_settlement_gnf?: number
          p_note?: string
        }
        Returns: {
          cadence: string | null
          configured: boolean
          created_at: string
          created_by: string | null
          effective_from: string
          enabled: boolean
          fee_bps: number | null
          fee_fixed_gnf: number | null
          fee_passthrough: boolean | null
          id: string
          max_settlement_gnf: number | null
          min_settlement_gnf: number | null
          note: string | null
          requires_evidence_reconciliation: boolean
        }
        SetofOptions: {
          from: "*"
          to: "merchant_settlement_policies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_set_payout_policy: {
        Args: {
          p_cancel_window_seconds?: number
          p_daily_limit_gnf: number
          p_effective_from?: string
          p_max_request_gnf: number
          p_min_request_gnf: number
          p_note?: string
          p_processing_estimate_max_minutes?: number
          p_processing_estimate_min_minutes?: number
          p_provider_fee_passthrough?: boolean
        }
        Returns: {
          block_on_dispute_or_freeze: boolean
          cancel_window_seconds: number
          created_at: string
          created_by: string | null
          daily_limit_gnf: number
          effective_from: string
          enabled: boolean
          id: string
          max_request_gnf: number
          min_request_gnf: number
          note: string | null
          one_pending_request_only: boolean
          processing_estimate_max_minutes: number
          processing_estimate_min_minutes: number
          provider_fee_passthrough: boolean
          registered_om_phone_only: boolean
          restricted_funds_withdrawable: boolean
        }
        SetofOptions: {
          from: "*"
          to: "driver_payout_policies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_set_provider_fee_schedule: {
        Args: {
          p_effective_from?: string
          p_fee_bps: number
          p_fee_fixed_gnf?: number
          p_max_fee_gnf?: number
          p_min_fee_gnf?: number
          p_note?: string
          p_passthrough_to_recipient?: boolean
          p_provider: string
        }
        Returns: {
          created_at: string
          created_by: string | null
          effective_from: string
          enabled: boolean
          fee_bps: number
          fee_fixed_gnf: number
          id: string
          max_fee_gnf: number | null
          min_fee_gnf: number
          note: string | null
          passthrough_to_recipient: boolean
          provider: string
        }
        SetofOptions: {
          from: "*"
          to: "provider_fee_schedules"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_set_starter_credit_policy: {
        Args: {
          p_amount_gnf: number
          p_effective_from?: string
          p_enabled?: boolean
          p_note?: string
        }
        Returns: {
          amount_gnf: number
          created_at: string
          created_by: string | null
          effective_from: string
          enabled: boolean
          id: string
          note: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "driver_starter_credit_policies"
          isOneToOne: true
          isSetofReturn: false
        }
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
      agent_cash_in_customer_wallet: {
        Args: {
          p_amount_gnf: number
          p_customer_user_id: string
          p_idempotency_key?: string
          p_reference_note?: string
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
      agent_lookup_customer_wallet: {
        Args: { p_phone: string }
        Returns: {
          customer_user_id: string
          display_name: string
          masked_phone: string
          wallet_exists: boolean
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
          authorized_at: string | null
          cancelled_at: string | null
          captured_at: string | null
          captured_tx_id: string | null
          checkout_session_id: string | null
          created_at: string
          currency: string
          description: string | null
          environment: string
          expires_at: string | null
          id: string
          internal_reference: string
          is_sandbox: boolean
          ledger_release_tx_id: string | null
          metadata: Json
          payee_user_id: string | null
          payer_phone: string | null
          provider: Database["public"]["Enums"]["payment_provider"]
          provider_event_id: string | null
          provider_reference: string | null
          purpose: Database["public"]["Enums"]["payment_purpose"]
          rejected_at: string | null
          rejection_reason: string | null
          related_listing_id: string | null
          related_mission_id: string | null
          related_order_id: string | null
          related_store_id: string | null
          settlement_tx_id: string | null
          source_id: string | null
          source_module: string | null
          state: Database["public"]["Enums"]["payment_state"]
          test_run_id: string | null
          updated_at: string
          user_id: string
          wallet_hold_tx_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "payment_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      cancellation_quote: {
        Args: {
          p_service: string
          p_source_id: string
          p_source_module?: string
        }
        Returns: Json
      }
      cash_order_accept: {
        Args: { p_source_id: string; p_source_module: string }
        Returns: Json
      }
      cash_order_complete_cash: {
        Args: { p_source_id: string; p_source_module: string }
        Returns: Json
      }
      cash_order_customer_cancel: {
        Args: {
          p_reason?: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      cash_order_dispute_open: {
        Args: { p_reason: string; p_source_id: string; p_source_module: string }
        Returns: Json
      }
      cash_order_merchant_accept: {
        Args: { p_source_id: string; p_source_module: string }
        Returns: Json
      }
      cash_order_merchant_prepare: {
        Args: { p_source_id: string; p_source_module: string }
        Returns: Json
      }
      cash_order_merchant_reject: {
        Args: {
          p_reason?: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      cash_order_quote: {
        Args: { p_source_id: string; p_source_module: string }
        Returns: Json
      }
      check_signup_allowed: {
        Args: { _email: string; _phone: string }
        Returns: Json
      }
      chop_pay_authorize_order: {
        Args: { p_source_id: string; p_source_module: string }
        Returns: Json
      }
      chop_pay_customer_cancel: {
        Args: {
          p_reason?: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      chop_pay_customer_capture: {
        Args: {
          p_commission_gnf: number
          p_driver: string
          p_driver_earning_gnf: number
          p_fee_gnf: number
          p_merchant_gnf: number
          p_merchant_store_id: string
          p_refund_remainder?: boolean
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      chop_pay_customer_hold_place: {
        Args: {
          p_amount_gnf: number
          p_customer?: string
          p_is_sandbox?: boolean
          p_mission_type?: string
          p_snapshot?: Json
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      chop_pay_customer_refund: {
        Args: {
          p_reason?: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      chop_pay_dispute_open: {
        Args: { p_reason: string; p_source_id: string; p_source_module: string }
        Returns: Json
      }
      chop_pay_merchant_accept: {
        Args: { p_source_id: string; p_source_module: string }
        Returns: Json
      }
      chop_pay_merchant_prepare: {
        Args: { p_source_id: string; p_source_module: string }
        Returns: Json
      }
      chop_pay_merchant_reject: {
        Args: {
          p_reason?: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      chop_pay_quote: {
        Args: { p_source_id: string; p_source_module: string }
        Returns: Json
      }
      choppay_cancel_payment_intent: {
        Args: { p_payment_intent_id: string; p_reason?: string }
        Returns: {
          amount_gnf: number
          authorized_at: string | null
          cancelled_at: string | null
          captured_at: string | null
          captured_tx_id: string | null
          checkout_session_id: string | null
          created_at: string
          currency: string
          description: string | null
          environment: string
          expires_at: string | null
          id: string
          internal_reference: string
          is_sandbox: boolean
          ledger_release_tx_id: string | null
          metadata: Json
          payee_user_id: string | null
          payer_phone: string | null
          provider: Database["public"]["Enums"]["payment_provider"]
          provider_event_id: string | null
          provider_reference: string | null
          purpose: Database["public"]["Enums"]["payment_purpose"]
          rejected_at: string | null
          rejection_reason: string | null
          related_listing_id: string | null
          related_mission_id: string | null
          related_order_id: string | null
          related_store_id: string | null
          settlement_tx_id: string | null
          source_id: string | null
          source_module: string | null
          state: Database["public"]["Enums"]["payment_state"]
          test_run_id: string | null
          updated_at: string
          user_id: string
          wallet_hold_tx_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "payment_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      choppay_capture_payment_intent: {
        Args: { p_payment_intent_id: string; p_reason?: string }
        Returns: {
          amount_gnf: number
          authorized_at: string | null
          cancelled_at: string | null
          captured_at: string | null
          captured_tx_id: string | null
          checkout_session_id: string | null
          created_at: string
          currency: string
          description: string | null
          environment: string
          expires_at: string | null
          id: string
          internal_reference: string
          is_sandbox: boolean
          ledger_release_tx_id: string | null
          metadata: Json
          payee_user_id: string | null
          payer_phone: string | null
          provider: Database["public"]["Enums"]["payment_provider"]
          provider_event_id: string | null
          provider_reference: string | null
          purpose: Database["public"]["Enums"]["payment_purpose"]
          rejected_at: string | null
          rejection_reason: string | null
          related_listing_id: string | null
          related_mission_id: string | null
          related_order_id: string | null
          related_store_id: string | null
          settlement_tx_id: string | null
          source_id: string | null
          source_module: string | null
          state: Database["public"]["Enums"]["payment_state"]
          test_run_id: string | null
          updated_at: string
          user_id: string
          wallet_hold_tx_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "payment_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      choppay_create_payment_intent: {
        Args: {
          p_amount_gnf: number
          p_description?: string
          p_merchant_store_id?: string
          p_metadata?: Json
          p_payee_user_id?: string
          p_purpose: Database["public"]["Enums"]["payment_purpose"]
          p_source_id: string
          p_source_module: string
          p_use_wallet?: boolean
        }
        Returns: {
          amount_gnf: number
          authorized_at: string | null
          cancelled_at: string | null
          captured_at: string | null
          captured_tx_id: string | null
          checkout_session_id: string | null
          created_at: string
          currency: string
          description: string | null
          environment: string
          expires_at: string | null
          id: string
          internal_reference: string
          is_sandbox: boolean
          ledger_release_tx_id: string | null
          metadata: Json
          payee_user_id: string | null
          payer_phone: string | null
          provider: Database["public"]["Enums"]["payment_provider"]
          provider_event_id: string | null
          provider_reference: string | null
          purpose: Database["public"]["Enums"]["payment_purpose"]
          rejected_at: string | null
          rejection_reason: string | null
          related_listing_id: string | null
          related_mission_id: string | null
          related_order_id: string | null
          related_store_id: string | null
          settlement_tx_id: string | null
          source_id: string | null
          source_module: string | null
          state: Database["public"]["Enums"]["payment_state"]
          test_run_id: string | null
          updated_at: string
          user_id: string
          wallet_hold_tx_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "payment_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      claim_first_admin: { Args: never; Returns: boolean }
      claims_reserve_allocate: {
        Args: {
          p_authorized_gnf: number
          p_customer?: string
          p_declared_value_gnf?: number
          p_driver?: string
          p_evidence_ref: string
          p_is_sandbox?: boolean
          p_mission_type?: string
          p_reason: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      claims_reserve_resolve: {
        Args: { p_claim_id: string; p_pay_gnf: number; p_reason: string }
        Returns: Json
      }
      confirm_payment_intent: {
        Args: {
          p_intent_id: string
          p_note?: string
          p_provider_reference?: string
        }
        Returns: {
          amount_gnf: number
          authorized_at: string | null
          cancelled_at: string | null
          captured_at: string | null
          captured_tx_id: string | null
          checkout_session_id: string | null
          created_at: string
          currency: string
          description: string | null
          environment: string
          expires_at: string | null
          id: string
          internal_reference: string
          is_sandbox: boolean
          ledger_release_tx_id: string | null
          metadata: Json
          payee_user_id: string | null
          payer_phone: string | null
          provider: Database["public"]["Enums"]["payment_provider"]
          provider_event_id: string | null
          provider_reference: string | null
          purpose: Database["public"]["Enums"]["payment_purpose"]
          rejected_at: string | null
          rejection_reason: string | null
          related_listing_id: string | null
          related_mission_id: string | null
          related_order_id: string | null
          related_store_id: string | null
          settlement_tx_id: string | null
          source_id: string | null
          source_module: string | null
          state: Database["public"]["Enums"]["payment_state"]
          test_run_id: string | null
          updated_at: string
          user_id: string
          wallet_hold_tx_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "payment_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_marketplace_offer: {
        Args: {
          p_amount_gnf: number
          p_listing_id: string
          p_message?: string
          p_payment_method?: string
        }
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
      customer_cancellation_debt_collect: {
        Args: { p_debt_id: string }
        Returns: Json
      }
      customer_cancellation_debt_create: {
        Args: {
          p_customer: string
          p_delivery_fee_gnf?: number
          p_fare_gnf?: number
          p_is_sandbox?: boolean
          p_merchandise_subtotal_gnf?: number
          p_mission_type: string
          p_policy_snapshot?: Json
          p_preparation_started?: boolean
          p_responsible_party?: string
          p_source_id: string
          p_source_module: string
          p_stage: string
        }
        Returns: Json
      }
      customer_cancellation_debt_repay: {
        Args: { p_amount_gnf?: number; p_debt_id: string }
        Returns: Json
      }
      customer_cancellation_debt_waive: {
        Args: { p_debt_id: string; p_reason: string }
        Returns: Json
      }
      customer_cancellation_debts_overview: { Args: never; Returns: Json }
      customer_cash_eligibility: { Args: never; Returns: Json }
      customer_finance_history: {
        Args: { p_limit?: number }
        Returns: {
          amount_gnf: number
          counts_as_balance: boolean
          direction: string
          event_id: string
          kind: string
          label: string
          module: string
          occurred_at: string
          reference: string
          source: string
          status: string
        }[]
      }
      customer_finance_overview: { Args: never; Returns: Json }
      customer_receipt: { Args: { p_transaction_id: string }; Returns: Json }
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
      driver_balance_summary: { Args: { p_driver?: string }; Returns: Json }
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
      driver_cashout_cancel_request: {
        Args: { p_id: string }
        Returns: {
          admin_note: string | null
          amount_gnf: number
          created_at: string
          driver_note: string | null
          driver_user_id: string
          id: string
          paid_at: string | null
          paid_by: string | null
          payout_method: string
          payout_phone: string
          provider_reference: string | null
          rejected_reason: string | null
          requested_at: string
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          updated_at: string
          wallet_id: string
        }
        SetofOptions: {
          from: "*"
          to: "driver_cashout_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      driver_cashout_create_request: {
        Args: {
          p_amount_gnf: number
          p_driver_note?: string
          p_payout_phone: string
        }
        Returns: string
      }
      driver_cashout_mark_paid: {
        Args: {
          p_admin_note?: string
          p_id: string
          p_provider_reference: string
        }
        Returns: {
          admin_note: string | null
          amount_gnf: number
          created_at: string
          driver_note: string | null
          driver_user_id: string
          id: string
          paid_at: string | null
          paid_by: string | null
          payout_method: string
          payout_phone: string
          provider_reference: string | null
          rejected_reason: string | null
          requested_at: string
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          updated_at: string
          wallet_id: string
        }
        SetofOptions: {
          from: "*"
          to: "driver_cashout_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      driver_cashout_reject_request: {
        Args: { p_id: string; p_reason: string }
        Returns: {
          admin_note: string | null
          amount_gnf: number
          created_at: string
          driver_note: string | null
          driver_user_id: string
          id: string
          paid_at: string | null
          paid_by: string | null
          payout_method: string
          payout_phone: string
          provider_reference: string | null
          rejected_reason: string | null
          requested_at: string
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          updated_at: string
          wallet_id: string
        }
        SetofOptions: {
          from: "*"
          to: "driver_cashout_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      driver_collateral_resolve: {
        Args: {
          p_capture_gnf: number
          p_reason: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      driver_financial_eligibility: {
        Args: {
          p_driver?: string
          p_mission_type: string
          p_value_gnf?: number
        }
        Returns: Json
      }
      driver_funding_allocate: {
        Args: { p_amount: number; p_driver: string; p_kind: string }
        Returns: Json
      }
      driver_has_capability: {
        Args: { _capability: string; _user_id: string }
        Returns: boolean
      }
      driver_mark_offline_signal: { Args: never; Returns: undefined }
      driver_mission_capture_reverse: {
        Args: {
          p_evidence?: string
          p_kind: string
          p_reason: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      driver_mission_commission_capture: {
        Args: {
          p_final_value_gnf: number
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      driver_mission_fee_capture: {
        Args: {
          p_final_fee_basis_gnf?: number
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      driver_mission_hold_freeze: {
        Args: { p_reason: string; p_source_id: string; p_source_module: string }
        Returns: Json
      }
      driver_mission_hold_place: {
        Args: {
          p_declared_value_gnf?: number
          p_delivery_fee_gnf?: number
          p_driver?: string
          p_fare_gnf?: number
          p_is_sandbox?: boolean
          p_kinds?: string[]
          p_merchandise_subtotal_gnf?: number
          p_mission_type: string
          p_payment_mode?: string
          p_source_id: string
          p_source_module: string
          p_value_gnf?: number
        }
        Returns: Json
      }
      driver_mission_hold_release: {
        Args: {
          p_kind?: string
          p_reason?: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
      }
      driver_mission_hold_unfreeze: {
        Args: { p_reason: string; p_source_id: string; p_source_module: string }
        Returns: Json
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
          ride_mode: Database["public"]["Enums"]["ride_mode"] | null
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
      driver_offer_accept_for_ride: {
        Args: { p_ride_id: string }
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
          ride_mode: Database["public"]["Enums"]["ride_mode"] | null
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
          ride_mode: Database["public"]["Enums"]["ride_mode"] | null
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
      driver_payout_cancel: {
        Args: { p_reason: string; p_request_id: string }
        Returns: Json
      }
      driver_payout_confirm: {
        Args: { p_evidence_ref: string; p_request_id: string }
        Returns: Json
      }
      driver_payout_hold_place: {
        Args: { p_amount_gnf: number; p_driver: string; p_request_id: string }
        Returns: Json
      }
      driver_payout_policy_at: {
        Args: { p_as_of?: string }
        Returns: {
          block_on_dispute_or_freeze: boolean
          cancel_window_seconds: number
          created_at: string
          created_by: string | null
          daily_limit_gnf: number
          effective_from: string
          enabled: boolean
          id: string
          max_request_gnf: number
          min_request_gnf: number
          note: string | null
          one_pending_request_only: boolean
          processing_estimate_max_minutes: number
          processing_estimate_min_minutes: number
          provider_fee_passthrough: boolean
          registered_om_phone_only: boolean
          restricted_funds_withdrawable: boolean
        }
        SetofOptions: {
          from: "*"
          to: "driver_payout_policies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      driver_payout_request_create: {
        Args: {
          p_amount_gnf: number
          p_idempotency_key: string
          p_payout_phone: string
        }
        Returns: Json
      }
      driver_promo_balance: { Args: { p_driver: string }; Returns: Json }
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
      driver_starter_credit_grant: {
        Args: { p_driver?: string }
        Returns: Json
      }
      driver_topup_history: {
        Args: { p_limit?: number }
        Returns: {
          amount_gnf: number
          cancelled_reason: string
          confirmed_at: string
          created_at: string
          credited: boolean
          credited_transaction_id: string
          id: string
          provider: string
          receiving_label: string
          receiving_phone: string
          reference: string
          review_reason: string
          stage: string
          status: string
        }[]
      }
      driver_update_location_signal: {
        Args: {
          p_accuracy_meters?: number
          p_active_mission_id?: string
          p_active_ride_id?: string
          p_heading?: number
          p_lat: number
          p_lng: number
          p_source?: string
          p_speed_mps?: number
        }
        Returns: {
          accuracy_meters: number | null
          active_mission_id: string | null
          active_ride_id: string | null
          capabilities: Json | null
          created_at: string
          driver_user_id: string
          heading: number | null
          last_ping_at: string
          lat: number
          lng: number
          service_zone_id: string | null
          source: string
          speed_mps: number | null
          status: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "driver_location_signals"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      driver_wallet_topup_om_create: {
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
          environment: string
          expires_at: string
          id: string
          matched_event_id: string | null
          matched_provider_transaction_id: string | null
          notes: string | null
          provider: string
          receiving_account_id: string | null
          reference: string
          review_reason: string | null
          status: Database["public"]["Enums"]["topup_status"]
          target_party_type: string
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
      email_get_health: { Args: never; Returns: Json }
      email_queue_dispatch: { Args: never; Returns: undefined }
      enqueue_email: {
        Args: { payload: Json; queue_name: string }
        Returns: number
      }
      fail_payment_intent: {
        Args: { p_intent_id: string; p_reason?: string }
        Returns: {
          amount_gnf: number
          authorized_at: string | null
          cancelled_at: string | null
          captured_at: string | null
          captured_tx_id: string | null
          checkout_session_id: string | null
          created_at: string
          currency: string
          description: string | null
          environment: string
          expires_at: string | null
          id: string
          internal_reference: string
          is_sandbox: boolean
          ledger_release_tx_id: string | null
          metadata: Json
          payee_user_id: string | null
          payer_phone: string | null
          provider: Database["public"]["Enums"]["payment_provider"]
          provider_event_id: string | null
          provider_reference: string | null
          purpose: Database["public"]["Enums"]["payment_purpose"]
          rejected_at: string | null
          rejection_reason: string | null
          related_listing_id: string | null
          related_mission_id: string | null
          related_order_id: string | null
          related_store_id: string | null
          settlement_tx_id: string | null
          source_id: string | null
          source_module: string | null
          state: Database["public"]["Enums"]["payment_state"]
          test_run_id: string | null
          updated_at: string
          user_id: string
          wallet_hold_tx_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "payment_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      field_submit_visit: {
        Args: {
          p_address_text?: string
          p_entrance_note?: string
          p_interest_level?: Database["public"]["Enums"]["field_visit_interest"]
          p_landmark_note?: string
          p_lat?: number
          p_lng?: number
          p_merchant_category?: string
          p_merchant_name: string
          p_merchant_phone?: string
          p_notes?: string
          p_pickup_note?: string
          p_pilot_id: string
          p_zone_id?: string
        }
        Returns: string
      }
      finance_confirm_manual_om_payout: {
        Args: {
          p_attestation?: boolean
          p_payout_order_id: string
          p_provider_reference: string
          p_transferred_at?: string
        }
        Returns: Json
      }
      finance_mission_requirement: {
        Args: { p_mission_type: string; p_value_gnf?: number }
        Returns: Json
      }
      finance_mission_requirement_v2: {
        Args: {
          p_declared_value_gnf?: number
          p_delivery_fee_gnf?: number
          p_fare_gnf?: number
          p_merchandise_subtotal_gnf?: number
          p_mission_type: string
          p_payment_mode?: string
        }
        Returns: Json
      }
      finance_payout_queue: {
        Args: { p_bucket?: string; p_limit?: number }
        Returns: Json
      }
      finance_policy_at: {
        Args: { p_as_of?: string; p_mission_type: string }
        Returns: {
          cancel_after_dispatch_bps: number
          cancel_basis: string
          cancel_before_dispatch_bps: number
          cash_funding_max_gnf: number | null
          cash_funding_mode: string
          cash_funding_pct_bps: number
          claims_exposure_max_gnf: number | null
          collateral_basis: string
          collateral_fixed_gnf: number
          collateral_max_gnf: number | null
          collateral_min_gnf: number
          collateral_mode: string
          collateral_pct_bps: number
          commission_bps: number
          created_at: string
          created_by: string | null
          effective_from: string
          enabled: boolean
          fee_basis: string
          fixed_commission_gnf: number
          id: string
          max_declared_value_gnf: number | null
          min_driver_balance_gnf: number
          mission_type: string
          note: string | null
          require_collateral_before_offer: boolean
          transaction_fee_bps: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "finance_policies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      finance_policy_current: {
        Args: { p_mission_type: string }
        Returns: {
          cancel_after_dispatch_bps: number
          cancel_basis: string
          cancel_before_dispatch_bps: number
          cash_funding_max_gnf: number | null
          cash_funding_mode: string
          cash_funding_pct_bps: number
          claims_exposure_max_gnf: number | null
          collateral_basis: string
          collateral_fixed_gnf: number
          collateral_max_gnf: number | null
          collateral_min_gnf: number
          collateral_mode: string
          collateral_pct_bps: number
          commission_bps: number
          created_at: string
          created_by: string | null
          effective_from: string
          enabled: boolean
          fee_basis: string
          fixed_commission_gnf: number
          id: string
          max_declared_value_gnf: number | null
          min_driver_balance_gnf: number
          mission_type: string
          note: string | null
          require_collateral_before_offer: boolean
          transaction_fee_bps: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "finance_policies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      finance_policy_predecessor: {
        Args: { p_effective_from: string; p_mission_type: string }
        Returns: {
          cancel_after_dispatch_bps: number
          cancel_basis: string
          cancel_before_dispatch_bps: number
          cash_funding_max_gnf: number | null
          cash_funding_mode: string
          cash_funding_pct_bps: number
          claims_exposure_max_gnf: number | null
          collateral_basis: string
          collateral_fixed_gnf: number
          collateral_max_gnf: number | null
          collateral_min_gnf: number
          collateral_mode: string
          collateral_pct_bps: number
          commission_bps: number
          created_at: string
          created_by: string | null
          effective_from: string
          enabled: boolean
          fee_basis: string
          fixed_commission_gnf: number
          id: string
          max_declared_value_gnf: number | null
          min_driver_balance_gnf: number
          mission_type: string
          note: string | null
          require_collateral_before_offer: boolean
          transaction_fee_bps: number
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "finance_policies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      finance_policy_snapshot: {
        Args: {
          p_as_of?: string
          p_declared_value_gnf?: number
          p_delivery_fee_gnf?: number
          p_fare_gnf?: number
          p_is_sandbox?: boolean
          p_merchandise_subtotal_gnf?: number
          p_mission_type: string
          p_payment_mode?: string
        }
        Returns: Json
      }
      finance_policy_snapshot_validate: {
        Args: { p_snapshot: Json }
        Returns: boolean
      }
      finance_treasury_drilldown: {
        Args: { p_code: string; p_limit?: number }
        Returns: {
          amount_gnf: number
          label: string
          occurred_at: string
          ref: string
          source_module: string
          source_ref: string
          state: string
        }[]
      }
      finance_treasury_exceptions: {
        Args: never
        Returns: {
          account_code: string
          amount_gnf: number
          code: string
          detail: string
          entity_count: number
          occurred_at: string
          severity: string
          source_module: string
          state: string
        }[]
      }
      finance_treasury_overview: { Args: never; Returns: Json }
      find_user_by_phone: {
        Args: { p_phone: string }
        Returns: {
          full_name: string
          user_id: string
        }[]
      }
      gen_topup_reference: { Args: never; Returns: string }
      generate_merchant_account_number: {
        Args: { _commune: string }
        Returns: string
      }
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
          review_reason: string
          stage: string
          status: string
          target_party_type: string
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
      is_assigned_to_pilot: {
        Args: { _pilot: string; _user: string }
        Returns: boolean
      }
      is_field_captain_of_pilot: {
        Args: { _pilot: string; _user: string }
        Returns: boolean
      }
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
          review_reason: string
          stage: string
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
      map_default_confidence: {
        Args: {
          _status: Database["public"]["Enums"]["map_verification_status"]
        }
        Returns: number
      }
      map_detect_place_duplicates: {
        Args: { p_place_id?: string; p_radius_meters?: number }
        Returns: number
      }
      map_mark_place_duplicate: {
        Args: {
          p_candidate_id?: string
          p_reason?: string
          p_source_place_id: string
          p_target_place_id: string
        }
        Returns: undefined
      }
      map_merge_places: {
        Args: {
          p_candidate_id?: string
          p_reason?: string
          p_source_place_id: string
          p_target_place_id: string
        }
        Returns: Json
      }
      marche_complete_offer: {
        Args: { p_offer_id: string; p_reason?: string }
        Returns: Json
      }
      marche_create_offer_payment_intent: {
        Args: { p_offer_id: string }
        Returns: {
          amount_gnf: number
          authorized_at: string | null
          cancelled_at: string | null
          captured_at: string | null
          captured_tx_id: string | null
          checkout_session_id: string | null
          created_at: string
          currency: string
          description: string | null
          environment: string
          expires_at: string | null
          id: string
          internal_reference: string
          is_sandbox: boolean
          ledger_release_tx_id: string | null
          metadata: Json
          payee_user_id: string | null
          payer_phone: string | null
          provider: Database["public"]["Enums"]["payment_provider"]
          provider_event_id: string | null
          provider_reference: string | null
          purpose: Database["public"]["Enums"]["payment_purpose"]
          rejected_at: string | null
          rejection_reason: string | null
          related_listing_id: string | null
          related_mission_id: string | null
          related_order_id: string | null
          related_store_id: string | null
          settlement_tx_id: string | null
          source_id: string | null
          source_module: string | null
          state: Database["public"]["Enums"]["payment_state"]
          test_run_id: string | null
          updated_at: string
          user_id: string
          wallet_hold_tx_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "payment_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      marche_increment_listing_metric: {
        Args: { _kind: string; _listing_id: string }
        Returns: undefined
      }
      marche_offer_set_tender: {
        Args: { p_method: string; p_offer_id: string }
        Returns: Json
      }
      marche_toggle_listing_save: {
        Args: { _listing_id: string }
        Returns: boolean
      }
      marketplace_create_delivery_mission: {
        Args: {
          _dropoff_address: string
          _dropoff_lat: number
          _dropoff_lng: number
          _dropoff_notes?: string
          _estimated_earning_gnf?: number
          _offer_id: string
          _payload_summary: string
        }
        Returns: {
          courier_id: string | null
          created_at: string
          customer_confirmed_at: string | null
          customer_confirmed_by: string | null
          customer_handoff_code: string | null
          customer_id: string
          delivery_photo_url: string | null
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
          merchant_handoff_code: string | null
          merchant_id: string | null
          merchant_store_id: string | null
          payload_summary: string | null
          pickup_address: string | null
          pickup_confirmed_at: string | null
          pickup_confirmed_by: string | null
          pickup_lat: number | null
          pickup_lng: number | null
          pickup_photo_url: string | null
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
      merchant_ensure_wallet: {
        Args: { p_merchant_id: string }
        Returns: string
      }
      merchant_finance_overview: {
        Args: { p_store_id?: string }
        Returns: Json
      }
      merchant_payable_create: {
        Args: {
          p_deduction_gnf?: number
          p_is_sandbox?: boolean
          p_merchant_store_id: string
          p_mission_type?: string
          p_snapshot?: Json
          p_source_id: string
          p_source_module: string
          p_subtotal_gnf: number
        }
        Returns: Json
      }
      merchant_payable_fund: {
        Args: {
          p_funding_source: string
          p_merchant_store_id: string
          p_source_id: string
          p_source_module: string
        }
        Returns: Json
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
      merchant_settlement_complete: {
        Args: { p_evidence_ref: string; p_payable_id: string }
        Returns: Json
      }
      merchant_settlement_fail: {
        Args: { p_payable_id: string; p_reason: string }
        Returns: Json
      }
      merchant_settlement_hold: {
        Args: { p_payable_id: string }
        Returns: Json
      }
      merchant_settlement_policy_at: {
        Args: { p_as_of?: string }
        Returns: {
          cadence: string | null
          configured: boolean
          created_at: string
          created_by: string | null
          effective_from: string
          enabled: boolean
          fee_bps: number | null
          fee_fixed_gnf: number | null
          fee_passthrough: boolean | null
          id: string
          max_settlement_gnf: number | null
          min_settlement_gnf: number | null
          note: string | null
          requires_evidence_reconciliation: boolean
        }
        SetofOptions: {
          from: "*"
          to: "merchant_settlement_policies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      merchant_settlement_receipt: {
        Args: { p_request_id: string }
        Returns: Json
      }
      merchant_settlement_request_create: {
        Args: {
          p_amount_gnf: number
          p_idempotency_key: string
          p_note?: string
          p_store_id?: string
        }
        Returns: Json
      }
      merchant_settlement_requests_list: {
        Args: { p_limit?: number; p_store_id?: string }
        Returns: {
          amount_gnf: number
          channel: string
          created_at: string
          evidence_ref: string
          id: string
          note: string
          reject_reason: string
          request_key: string
          reviewed_at: string
          settled_at: string
          status: string
        }[]
      }
      merchant_settlement_schedule_generate: {
        Args: { p_as_of?: string }
        Returns: Json
      }
      merchant_submit_location: {
        Args: {
          p_address_text?: string
          p_entrance_note?: string
          p_landmark_note?: string
          p_lat: number
          p_lng: number
          p_operational_note?: string
          p_pickup_note?: string
          p_store_id: string
        }
        Returns: string
      }
      mission_claim: {
        Args: { _mission_id: string }
        Returns: {
          courier_id: string | null
          created_at: string
          customer_confirmed_at: string | null
          customer_confirmed_by: string | null
          customer_handoff_code: string | null
          customer_id: string
          delivery_photo_url: string | null
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
          merchant_handoff_code: string | null
          merchant_id: string | null
          merchant_store_id: string | null
          payload_summary: string | null
          pickup_address: string | null
          pickup_confirmed_at: string | null
          pickup_confirmed_by: string | null
          pickup_lat: number | null
          pickup_lng: number | null
          pickup_photo_url: string | null
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
          customer_confirmed_at: string | null
          customer_confirmed_by: string | null
          customer_handoff_code: string | null
          customer_id: string
          delivery_photo_url: string | null
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
          merchant_handoff_code: string | null
          merchant_id: string | null
          merchant_store_id: string | null
          payload_summary: string | null
          pickup_address: string | null
          pickup_confirmed_at: string | null
          pickup_confirmed_by: string | null
          pickup_lat: number | null
          pickup_lng: number | null
          pickup_photo_url: string | null
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
      mission_confirm_dropoff_with_proof: {
        Args: {
          _customer_code: string
          _mission_id: string
          _photo_url: string
        }
        Returns: {
          courier_id: string | null
          created_at: string
          customer_confirmed_at: string | null
          customer_confirmed_by: string | null
          customer_handoff_code: string | null
          customer_id: string
          delivery_photo_url: string | null
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
          merchant_handoff_code: string | null
          merchant_id: string | null
          merchant_store_id: string | null
          payload_summary: string | null
          pickup_address: string | null
          pickup_confirmed_at: string | null
          pickup_confirmed_by: string | null
          pickup_lat: number | null
          pickup_lng: number | null
          pickup_photo_url: string | null
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
          customer_confirmed_at: string | null
          customer_confirmed_by: string | null
          customer_handoff_code: string | null
          customer_id: string
          delivery_photo_url: string | null
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
          merchant_handoff_code: string | null
          merchant_id: string | null
          merchant_store_id: string | null
          payload_summary: string | null
          pickup_address: string | null
          pickup_confirmed_at: string | null
          pickup_confirmed_by: string | null
          pickup_lat: number | null
          pickup_lng: number | null
          pickup_photo_url: string | null
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
      mission_confirm_pickup_with_proof: {
        Args: {
          _merchant_code: string
          _mission_id: string
          _photo_url: string
        }
        Returns: {
          courier_id: string | null
          created_at: string
          customer_confirmed_at: string | null
          customer_confirmed_by: string | null
          customer_handoff_code: string | null
          customer_id: string
          delivery_photo_url: string | null
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
          merchant_handoff_code: string | null
          merchant_id: string | null
          merchant_store_id: string | null
          payload_summary: string | null
          pickup_address: string | null
          pickup_confirmed_at: string | null
          pickup_confirmed_by: string | null
          pickup_lat: number | null
          pickup_lng: number | null
          pickup_photo_url: string | null
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
      mission_customer_confirm_delivery: {
        Args: { _mission_id: string }
        Returns: {
          courier_id: string | null
          created_at: string
          customer_confirmed_at: string | null
          customer_confirmed_by: string | null
          customer_handoff_code: string | null
          customer_id: string
          delivery_photo_url: string | null
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
          merchant_handoff_code: string | null
          merchant_id: string | null
          merchant_store_id: string | null
          payload_summary: string | null
          pickup_address: string | null
          pickup_confirmed_at: string | null
          pickup_confirmed_by: string | null
          pickup_lat: number | null
          pickup_lng: number | null
          pickup_photo_url: string | null
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
          customer_confirmed_at: string | null
          customer_confirmed_by: string | null
          customer_handoff_code: string | null
          customer_id: string
          delivery_photo_url: string | null
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
          merchant_handoff_code: string | null
          merchant_id: string | null
          merchant_store_id: string | null
          payload_summary: string | null
          pickup_address: string | null
          pickup_confirmed_at: string | null
          pickup_confirmed_by: string | null
          pickup_lat: number | null
          pickup_lng: number | null
          pickup_photo_url: string | null
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
          customer_confirmed_at: string | null
          customer_confirmed_by: string | null
          customer_handoff_code: string | null
          customer_id: string
          delivery_photo_url: string | null
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
          merchant_handoff_code: string | null
          merchant_id: string | null
          merchant_store_id: string | null
          payload_summary: string | null
          pickup_address: string | null
          pickup_confirmed_at: string | null
          pickup_confirmed_by: string | null
          pickup_lat: number | null
          pickup_lng: number | null
          pickup_photo_url: string | null
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
      my_account_recovery_status: { Args: never; Returns: Json }
      next_wongo_reference: { Args: never; Returns: string }
      normalize_om_code: { Args: { p_code: string }; Returns: string }
      om_auto_match: { Args: { p_event_id: string }; Returns: Json }
      om_payment_submit_sandbox_reference: {
        Args: {
          p_payer_phone?: string
          p_payment_intent_id: string
          p_provider_reference: string
          p_test_run_id?: string
        }
        Returns: Json
      }
      om_pending_topups_for_event: {
        Args: { p_event_id: string }
        Returns: {
          account_match: boolean
          amount_gnf: number
          amount_match: boolean
          client_name: string
          client_phone: string
          client_user_id: string
          code_match: boolean
          created_at: string
          environment: string
          expires_at: string
          phone_match: boolean
          reference: string
          status: string
          target_party_type: string
          topup_id: string
        }[]
      }
      om_sandbox_admin_list_runs: {
        Args: { p_limit?: number }
        Returns: {
          archived_at: string
          created_by: string
          event_count: number
          id: string
          intent_count: number
          label: string
          last_activity_at: string
          modules: string[]
          refund_count: number
          started_at: string
          status: string
          support_count: number
          unresolved_count: number
        }[]
      }
      om_sandbox_admin_metrics: { Args: never; Returns: Json }
      om_sandbox_admin_run_detail: {
        Args: { p_test_run_id: string }
        Returns: Json
      }
      om_sandbox_archive_test_run: {
        Args: { p_notes?: string; p_test_run_id: string }
        Returns: Json
      }
      om_sandbox_assign_mock_driver: {
        Args: { p_driver_user_id: string; p_ride_id: string }
        Returns: Json
      }
      om_sandbox_cancel_ride: {
        Args: { p_ride_id: string; p_test_run_id?: string }
        Returns: Json
      }
      om_sandbox_complete_test_run: {
        Args: { p_notes?: string; p_test_run_id: string }
        Returns: Json
      }
      om_sandbox_create_marche_intent: {
        Args: { p_offer_id: string; p_test_run_id?: string }
        Returns: {
          amount_gnf: number
          authorized_at: string | null
          cancelled_at: string | null
          captured_at: string | null
          captured_tx_id: string | null
          checkout_session_id: string | null
          created_at: string
          currency: string
          description: string | null
          environment: string
          expires_at: string | null
          id: string
          internal_reference: string
          is_sandbox: boolean
          ledger_release_tx_id: string | null
          metadata: Json
          payee_user_id: string | null
          payer_phone: string | null
          provider: Database["public"]["Enums"]["payment_provider"]
          provider_event_id: string | null
          provider_reference: string | null
          purpose: Database["public"]["Enums"]["payment_purpose"]
          rejected_at: string | null
          rejection_reason: string | null
          related_listing_id: string | null
          related_mission_id: string | null
          related_order_id: string | null
          related_store_id: string | null
          settlement_tx_id: string | null
          source_id: string | null
          source_module: string | null
          state: Database["public"]["Enums"]["payment_state"]
          test_run_id: string | null
          updated_at: string
          user_id: string
          wallet_hold_tx_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "payment_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      om_sandbox_create_repas_intent: {
        Args: { p_food_order_id: string; p_test_run_id?: string }
        Returns: {
          amount_gnf: number
          authorized_at: string | null
          cancelled_at: string | null
          captured_at: string | null
          captured_tx_id: string | null
          checkout_session_id: string | null
          created_at: string
          currency: string
          description: string | null
          environment: string
          expires_at: string | null
          id: string
          internal_reference: string
          is_sandbox: boolean
          ledger_release_tx_id: string | null
          metadata: Json
          payee_user_id: string | null
          payer_phone: string | null
          provider: Database["public"]["Enums"]["payment_provider"]
          provider_event_id: string | null
          provider_reference: string | null
          purpose: Database["public"]["Enums"]["payment_purpose"]
          rejected_at: string | null
          rejection_reason: string | null
          related_listing_id: string | null
          related_mission_id: string | null
          related_order_id: string | null
          related_store_id: string | null
          settlement_tx_id: string | null
          source_id: string | null
          source_module: string | null
          state: Database["public"]["Enums"]["payment_state"]
          test_run_id: string | null
          updated_at: string
          user_id: string
          wallet_hold_tx_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "payment_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      om_sandbox_create_ride_intent: {
        Args: {
          p_checkout_session_id: string
          p_client_display_fare_gnf?: number
          p_dest_lat: number
          p_dest_lng: number
          p_mode: Database["public"]["Enums"]["ride_mode"]
          p_pickup_lat: number
          p_pickup_lng: number
          p_test_run_id?: string
        }
        Returns: {
          amount_gnf: number
          authorized_at: string | null
          cancelled_at: string | null
          captured_at: string | null
          captured_tx_id: string | null
          checkout_session_id: string | null
          created_at: string
          currency: string
          description: string | null
          environment: string
          expires_at: string | null
          id: string
          internal_reference: string
          is_sandbox: boolean
          ledger_release_tx_id: string | null
          metadata: Json
          payee_user_id: string | null
          payer_phone: string | null
          provider: Database["public"]["Enums"]["payment_provider"]
          provider_event_id: string | null
          provider_reference: string | null
          purpose: Database["public"]["Enums"]["payment_purpose"]
          rejected_at: string | null
          rejection_reason: string | null
          related_listing_id: string | null
          related_mission_id: string | null
          related_order_id: string | null
          related_store_id: string | null
          settlement_tx_id: string | null
          source_id: string | null
          source_module: string | null
          state: Database["public"]["Enums"]["payment_state"]
          test_run_id: string | null
          updated_at: string
          user_id: string
          wallet_hold_tx_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "payment_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      om_sandbox_finalize_authorized_intent: {
        Args: { p_payment_intent_id: string }
        Returns: Json
      }
      om_sandbox_reference_outcome: {
        Args: { p_reference: string }
        Returns: string
      }
      om_sandbox_refund_reference_outcome: {
        Args: { p_ref: string }
        Returns: string
      }
      om_sandbox_request_marche_refund: {
        Args: { p_offer_id: string; p_reason?: string; p_test_run_id?: string }
        Returns: Json
      }
      om_sandbox_request_repas_refund: {
        Args: {
          p_food_order_id: string
          p_reason?: string
          p_test_run_id?: string
        }
        Returns: Json
      }
      om_sandbox_submit_refund_reference: {
        Args: {
          p_provider_reference: string
          p_refund_request_id: string
          p_test_run_id?: string
        }
        Returns: Json
      }
      open_food_order_thread: {
        Args: {
          _food_order_id: string
          _thread_type: Database["public"]["Enums"]["food_order_thread_type"]
        }
        Returns: string
      }
      package_claim_open: {
        Args: {
          p_evidence_ref?: string
          p_package_id: string
          p_reason: string
        }
        Returns: Json
      }
      package_courier_cancel: {
        Args: { p_package_id: string; p_reason?: string }
        Returns: Json
      }
      package_delivery_cancel: {
        Args: { p_package_id: string; p_reason?: string }
        Returns: Json
      }
      package_delivery_cancel_preview: {
        Args: { p_package_id: string }
        Returns: Json
      }
      package_delivery_courier_view: {
        Args: { p_mission_id: string }
        Returns: Json
      }
      package_delivery_create_checkout: {
        Args: {
          p_attestation_statement?: string
          p_declared_value_gnf?: number
          p_description?: string
          p_idempotency_key?: string
          p_instructions?: string
          p_provider?: string
          p_quote_id: string
          p_recipient_name: string
          p_recipient_phone: string
          p_sandbox?: boolean
          p_sender_phone?: string
          p_tender?: string
          p_test_run_id?: string
          p_value_attested?: boolean
        }
        Returns: Json
      }
      package_delivery_finalize_from_intent: {
        Args: { p_intent_id: string }
        Returns: Json
      }
      package_delivery_quote: {
        Args: {
          p_category: string
          p_dest_label?: string
          p_dest_lat: number
          p_dest_lng: number
          p_pickup_label?: string
          p_pickup_lat: number
          p_pickup_lng: number
        }
        Returns: Json
      }
      package_evidence_register: {
        Args: {
          p_byte_size?: number
          p_content_type?: string
          p_kind?: string
          p_quote_id: string
          p_storage_path: string
        }
        Returns: Json
      }
      package_verify_delivery: {
        Args: {
          p_code: string
          p_package_id: string
          p_recipient_name?: string
        }
        Returns: Json
      }
      package_verify_pickup: {
        Args: { p_code: string; p_package_id: string }
        Returns: Json
      }
      payout_reconcile_evidence: {
        Args: { p_evidence_id: string }
        Returns: Json
      }
      payout_record_provider_evidence: {
        Args: {
          p_amount_gnf: number
          p_environment: string
          p_fee_gnf?: number
          p_payout_order_id: string
          p_provider: string
          p_provider_reference: string
          p_provider_status: string
          p_raw?: Json
          p_recipient_msisdn: string
          p_transferred_at?: string
        }
        Returns: Json
      }
      payout_reject_release: {
        Args: { p_payout_order_id: string; p_reason: string }
        Returns: Json
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
      provider_fee_schedule_at: {
        Args: { p_as_of?: string; p_provider?: string }
        Returns: {
          created_at: string
          created_by: string | null
          effective_from: string
          enabled: boolean
          fee_bps: number
          fee_fixed_gnf: number
          id: string
          max_fee_gnf: number | null
          min_fee_gnf: number
          note: string | null
          passthrough_to_recipient: boolean
          provider: string
        }
        SetofOptions: {
          from: "*"
          to: "provider_fee_schedules"
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
      repas_capture_and_settle_order: {
        Args: { p_food_order_id: string; p_reason?: string }
        Returns: Json
      }
      repas_complete_order: {
        Args: { p_food_order_id: string; p_reason?: string }
        Returns: Json
      }
      repas_customer_cancel_order: {
        Args: { p_order_id: string; p_reason?: string }
        Returns: Json
      }
      repas_delivery_earning_gnf: { Args: never; Returns: number }
      repas_merchant_transition: {
        Args: { p_action: string; p_order_id: string; p_reason?: string }
        Returns: Json
      }
      repas_order_create: {
        Args: {
          p_client_request_id: string
          p_delivery_address?: string
          p_delivery_lat?: number
          p_delivery_lng?: number
          p_fulfillment: string
          p_items: Json
          p_notes?: string
          p_payment_method: string
          p_restaurant_id: string
        }
        Returns: Json
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
      ride_compute_quote_gnf: {
        Args: {
          p_dest_lat: number
          p_dest_lng: number
          p_mode: Database["public"]["Enums"]["ride_mode"]
          p_pickup_lat: number
          p_pickup_lng: number
        }
        Returns: number
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
      ride_expire_unfulfilled: { Args: { p_ride_id: string }; Returns: Json }
      ride_get_quote: {
        Args: {
          p_dest_lat?: number
          p_dest_lng?: number
          p_mode: Database["public"]["Enums"]["ride_mode"]
          p_pickup_lat: number
          p_pickup_lng: number
        }
        Returns: Json
      }
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
      ride_request_create: {
        Args: {
          p_client_request_id: string
          p_dest_label?: string
          p_dest_lat: number
          p_dest_lng: number
          p_mode: Database["public"]["Enums"]["ride_mode"]
          p_payment_mode: string
          p_pickup_label?: string
          p_pickup_lat: number
          p_pickup_lng: number
        }
        Returns: Json
      }
      ride_request_dispatch: { Args: { p_ride_id: string }; Returns: string }
      ride_reservation_amount_gnf: {
        Args: { p_fare_gnf: number }
        Returns: number
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
      ride_sweep_unfulfilled: { Args: { p_limit?: number }; Returns: Json }
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
      starter_credit_policy_at: {
        Args: { p_as_of?: string }
        Returns: {
          amount_gnf: number
          created_at: string
          created_by: string | null
          effective_from: string
          enabled: boolean
          id: string
          note: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "driver_starter_credit_policies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      starter_credit_policy_current: {
        Args: never
        Returns: {
          amount_gnf: number
          created_at: string
          created_by: string | null
          effective_from: string
          enabled: boolean
          id: string
          note: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "driver_starter_credit_policies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
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
      wallet_credit_mission_earning: {
        Args: { p_mission_id: string; p_reason?: string }
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
      wallet_ensure_master: { Args: never; Returns: string }
      wallet_get_master_balance: { Args: never; Returns: number }
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
          p_reference?: string
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
      wallet_internal_transfer_v2: {
        Args: {
          p_amount_gnf: number
          p_description?: string
          p_from_wallet_id: string
          p_metadata?: Json
          p_reference: string
          p_source_id?: string
          p_source_module?: string
          p_to_wallet_id: string
          p_transfer_type?: string
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
      wallet_p2p_lookup_recipient: {
        Args: { p_phone: string }
        Returns: {
          display_name: string
          masked_phone: string
          user_id: string
        }[]
      }
      wallet_p2p_transfer: {
        Args: {
          p_amount_gnf: number
          p_idempotency_key?: string
          p_note?: string
          p_recipient_user_id: string
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
      wallet_pay_merchant_store: {
        Args: {
          p_amount_gnf: number
          p_description?: string
          p_merchant_store_id: string
          p_metadata?: Json
          p_reference: string
          p_source_id?: string
          p_source_module?: string
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
      wallet_settle_merchant_revenue: {
        Args: {
          p_amount_gnf: number
          p_description?: string
          p_merchant_store_id: string
          p_metadata?: Json
          p_reference: string
          p_source_id: string
          p_source_module: string
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
          environment: string
          expires_at: string
          id: string
          matched_event_id: string | null
          matched_provider_transaction_id: string | null
          notes: string | null
          provider: string
          receiving_account_id: string | null
          reference: string
          review_reason: string | null
          status: Database["public"]["Enums"]["topup_status"]
          target_party_type: string
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
          environment: string
          expires_at: string
          id: string
          matched_event_id: string | null
          matched_provider_transaction_id: string | null
          notes: string | null
          provider: string
          receiving_account_id: string | null
          reference: string
          review_reason: string | null
          status: Database["public"]["Enums"]["topup_status"]
          target_party_type: string
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
          environment: string
          expires_at: string
          id: string
          matched_event_id: string | null
          matched_provider_transaction_id: string | null
          notes: string | null
          provider: string
          receiving_account_id: string | null
          reference: string
          review_reason: string | null
          status: Database["public"]["Enums"]["topup_status"]
          target_party_type: string
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
          environment: string
          expires_at: string
          id: string
          matched_event_id: string | null
          matched_provider_transaction_id: string | null
          notes: string | null
          provider: string
          receiving_account_id: string | null
          reference: string
          review_reason: string | null
          status: Database["public"]["Enums"]["topup_status"]
          target_party_type: string
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
          environment: string
          expires_at: string
          id: string
          matched_event_id: string | null
          matched_provider_transaction_id: string | null
          notes: string | null
          provider: string
          receiving_account_id: string | null
          reference: string
          review_reason: string | null
          status: Database["public"]["Enums"]["topup_status"]
          target_party_type: string
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
        | "field_captain"
        | "field_agent"
      approval_status: "pending" | "approved" | "rejected" | "cancelled"
      driver_application_decision:
        | "pending"
        | "approved"
        | "rejected"
        | "more_info"
      driver_presence: "offline" | "online" | "on_trip"
      driver_status: "pending" | "approved" | "rejected" | "suspended"
      driver_vehicle_type: "moto" | "toktok" | "livraison" | "auto"
      field_assignment_role: "field_captain" | "field_agent" | "verifier"
      field_assignment_status: "active" | "paused" | "completed" | "removed"
      field_pilot_status:
        | "planned"
        | "active"
        | "paused"
        | "completed"
        | "cancelled"
      field_report_status:
        | "submitted"
        | "reviewed"
        | "needs_correction"
        | "approved"
      field_visit_interest:
        | "cold"
        | "interested"
        | "signed_up"
        | "needs_follow_up"
        | "rejected"
      field_visit_status:
        | "visited"
        | "submitted"
        | "duplicate_possible"
        | "needs_review"
        | "converted"
        | "rejected"
      food_fulfillment: "pickup" | "delivery"
      food_order_sender_role: "client" | "restaurant" | "courier" | "admin"
      food_order_state:
        | "placed"
        | "confirmed"
        | "preparing"
        | "ready"
        | "out_for_delivery"
        | "completed"
        | "cancelled"
      food_order_thread_type:
        | "restaurant_client_order"
        | "restaurant_courier_order"
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
      map_verification_status:
        | "unverified"
        | "submitted"
        | "field_checked"
        | "admin_verified"
        | "trusted"
        | "needs_review"
        | "duplicate"
        | "closed"
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
        | "package_payment"
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
        | "proof_submitted"
        | "in_review"
        | "authorized"
        | "needs_review"
      rating_direction: "client_to_driver" | "driver_to_client"
      report_status: "open" | "reviewed" | "actioned" | "dismissed"
      ride_mode: "moto" | "toktok" | "food" | "auto"
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
        | "ride_earning"
        | "mission_earning"
        | "merchant_revenue"
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
        "field_captain",
        "field_agent",
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
      field_assignment_role: ["field_captain", "field_agent", "verifier"],
      field_assignment_status: ["active", "paused", "completed", "removed"],
      field_pilot_status: [
        "planned",
        "active",
        "paused",
        "completed",
        "cancelled",
      ],
      field_report_status: [
        "submitted",
        "reviewed",
        "needs_correction",
        "approved",
      ],
      field_visit_interest: [
        "cold",
        "interested",
        "signed_up",
        "needs_follow_up",
        "rejected",
      ],
      field_visit_status: [
        "visited",
        "submitted",
        "duplicate_possible",
        "needs_review",
        "converted",
        "rejected",
      ],
      food_fulfillment: ["pickup", "delivery"],
      food_order_sender_role: ["client", "restaurant", "courier", "admin"],
      food_order_state: [
        "placed",
        "confirmed",
        "preparing",
        "ready",
        "out_for_delivery",
        "completed",
        "cancelled",
      ],
      food_order_thread_type: [
        "restaurant_client_order",
        "restaurant_courier_order",
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
      map_verification_status: [
        "unverified",
        "submitted",
        "field_checked",
        "admin_verified",
        "trusted",
        "needs_review",
        "duplicate",
        "closed",
      ],
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
        "package_payment",
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
        "proof_submitted",
        "in_review",
        "authorized",
        "needs_review",
      ],
      rating_direction: ["client_to_driver", "driver_to_client"],
      report_status: ["open", "reviewed", "actioned", "dismissed"],
      ride_mode: ["moto", "toktok", "food", "auto"],
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
        "ride_earning",
        "mission_earning",
        "merchant_revenue",
      ],
      wallet_status: ["active", "frozen", "closed"],
    },
  },
} as const
