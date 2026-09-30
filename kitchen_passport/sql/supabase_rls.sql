-- Kitchen Passport — Row Level Security for a Supabase (Postgres) deployment.
--
-- Apply after the kp_* tables exist (the Flask app creates them on boot, or
-- run kitchen_passport/schema.py's SCHEMA). The Flask API already enforces
-- the same rules server-side; these policies protect the tables if the
-- Supabase client/PostgREST is ever used directly.
--
-- Roles come from kp_app_roles, a table only the service role can write —
-- NEVER from auth.users.raw_user_meta_data (user-editable). Keep the
-- service-role key on the server only; the client app uses the anon key.

CREATE TABLE IF NOT EXISTS kp_app_roles (
    auth_user_id  uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    role          text NOT NULL CHECK (role IN ('customer', 'technician', 'staff', 'owner')),
    customer_id   text REFERENCES kp_customers(customer_id),
    technician_id text REFERENCES technicians(id)
);
ALTER TABLE kp_app_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY kp_roles_self_read ON kp_app_roles FOR SELECT USING (auth_user_id = auth.uid());

CREATE OR REPLACE FUNCTION kp_role() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS
$$ SELECT role FROM kp_app_roles WHERE auth_user_id = auth.uid() $$;

CREATE OR REPLACE FUNCTION kp_is_staff() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS
$$ SELECT coalesce(kp_role() IN ('staff', 'owner'), false) $$;

-- Kitchens the caller may see: own kitchens (customer) or kitchens with an
-- active job assigned to them (technician).
CREATE OR REPLACE FUNCTION kp_can_access_kitchen(k text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT kp_is_staff()
      OR EXISTS (SELECT 1 FROM kp_kitchens kk
                 JOIN kp_kitchen_passports p ON p.passport_id = kk.passport_id
                 JOIN kp_app_roles r ON r.customer_id = p.customer_id AND r.auth_user_id = auth.uid()
                 WHERE kk.kitchen_id = k)
      OR EXISTS (SELECT 1 FROM kp_technician_jobs j
                 JOIN kp_app_roles r ON r.technician_id = j.technician_id AND r.auth_user_id = auth.uid()
                 WHERE j.kitchen_id = k AND j.status IN ('ASSIGNED', 'IN_PROGRESS'))
$$;

CREATE OR REPLACE FUNCTION kp_can_access_appliance(a text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT kp_can_access_kitchen((SELECT kitchen_id FROM kp_appliances WHERE appliance_id = a))
$$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['kp_config','kp_config_history','kp_counters','kp_customers','kp_kitchen_passports',
    'kp_kitchens','kp_appliance_categories','kp_inspection_parameters','kp_appliances','kp_technician_credentials',
    'kp_technician_jobs','kp_service_records','kp_appliance_inspections','kp_inspection_measurements',
    'kp_health_scores','kp_safety_findings','kp_repair_recommendations','kp_service_schedules','kp_parts',
    'kp_part_replacements','kp_warranties','kp_photos','kp_invoices','kp_notifications','kp_health_timeline',
    'kp_ai_assessments']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

-- Reference data readable by any signed-in user; writes only via service role.
CREATE POLICY kp_cat_read ON kp_appliance_categories FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY kp_param_read ON kp_inspection_parameters FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY kp_parts_read ON kp_parts FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY kp_config_staff ON kp_config FOR SELECT USING (kp_is_staff());
CREATE POLICY kp_config_hist_staff ON kp_config_history FOR SELECT USING (kp_is_staff());
-- kp_counters, kp_technician_credentials: no policies → service role only.

CREATE POLICY kp_customer_self ON kp_customers FOR SELECT USING (
  kp_is_staff() OR customer_id = (SELECT customer_id FROM kp_app_roles WHERE auth_user_id = auth.uid()));
CREATE POLICY kp_customer_self_update ON kp_customers FOR UPDATE USING (
  customer_id = (SELECT customer_id FROM kp_app_roles WHERE auth_user_id = auth.uid()));
-- Technicians see customer contact details only for an active job.
CREATE POLICY kp_customer_tech ON kp_customers FOR SELECT USING (EXISTS (
  SELECT 1 FROM kp_kitchen_passports p JOIN kp_kitchens k ON k.passport_id = p.passport_id
  WHERE p.customer_id = kp_customers.customer_id AND kp_can_access_kitchen(k.kitchen_id)));

CREATE POLICY kp_passport_read ON kp_kitchen_passports FOR SELECT USING (EXISTS (
  SELECT 1 FROM kp_kitchens k WHERE k.passport_id = kp_kitchen_passports.passport_id AND kp_can_access_kitchen(k.kitchen_id)));
CREATE POLICY kp_kitchen_read ON kp_kitchens FOR SELECT USING (kp_can_access_kitchen(kitchen_id));
CREATE POLICY kp_appliance_read ON kp_appliances FOR SELECT USING (kp_can_access_kitchen(kitchen_id));
CREATE POLICY kp_jobs_read ON kp_technician_jobs FOR SELECT USING (
  kp_is_staff() OR technician_id = (SELECT technician_id FROM kp_app_roles WHERE auth_user_id = auth.uid()));

-- Appliance-scoped history tables
CREATE POLICY kp_svc_read ON kp_service_records FOR SELECT USING (kp_can_access_appliance(appliance_id));
CREATE POLICY kp_insp_read ON kp_appliance_inspections FOR SELECT USING (kp_can_access_appliance(appliance_id));
CREATE POLICY kp_meas_read ON kp_inspection_measurements FOR SELECT USING (EXISTS (
  SELECT 1 FROM kp_appliance_inspections i WHERE i.inspection_id = kp_inspection_measurements.inspection_id
  AND kp_can_access_appliance(i.appliance_id)));
CREATE POLICY kp_scores_read ON kp_health_scores FOR SELECT USING (kp_can_access_appliance(appliance_id));
CREATE POLICY kp_safety_read ON kp_safety_findings FOR SELECT USING (kp_can_access_appliance(appliance_id));
CREATE POLICY kp_recs_read ON kp_repair_recommendations FOR SELECT USING (kp_can_access_appliance(appliance_id));
CREATE POLICY kp_sched_read ON kp_service_schedules FOR SELECT USING (kp_can_access_appliance(appliance_id));
CREATE POLICY kp_partrep_read ON kp_part_replacements FOR SELECT USING (kp_can_access_appliance(appliance_id));
CREATE POLICY kp_warranty_read ON kp_warranties FOR SELECT USING (kp_can_access_appliance(appliance_id));
CREATE POLICY kp_photo_read ON kp_photos FOR SELECT USING (kp_can_access_appliance(appliance_id));
CREATE POLICY kp_ai_read ON kp_ai_assessments FOR SELECT USING (
  (appliance_id IS NOT NULL AND kp_can_access_appliance(appliance_id)) OR (kitchen_id IS NOT NULL AND kp_can_access_kitchen(kitchen_id)));
CREATE POLICY kp_invoice_read ON kp_invoices FOR SELECT USING (EXISTS (
  SELECT 1 FROM kp_service_records s WHERE s.service_id = kp_invoices.service_id AND kp_can_access_appliance(s.appliance_id)));
CREATE POLICY kp_timeline_read ON kp_health_timeline FOR SELECT USING (kp_can_access_kitchen(kitchen_id));
CREATE POLICY kp_notif_read ON kp_notifications FOR SELECT USING (
  customer_id = (SELECT customer_id FROM kp_app_roles WHERE auth_user_id = auth.uid()) OR kp_is_staff());

-- All inserts/updates of inspection data, scores and schedules go through
-- the server (service role) so scores are always engine-calculated and a
-- client can never write "Health Score = 85" directly.

-- Private photo storage bucket: signed URLs only.
-- insert into storage.buckets (id, name, public) values ('kp-photos', 'kp-photos', false);
-- Objects are named <appliance_id>/<photo_id>.jpg; read policy:
-- CREATE POLICY kp_photo_objects ON storage.objects FOR SELECT USING (
--   bucket_id = 'kp-photos' AND kp_can_access_appliance(split_part(name, '/', 1)));
