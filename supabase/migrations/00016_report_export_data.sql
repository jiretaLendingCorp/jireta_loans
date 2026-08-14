-- 00016_report_export_data.sql
-- Store the raw report rows so generated reports can be re-downloaded as PDF/Excel.
ALTER TABLE public.reports ADD COLUMN IF NOT EXISTS data jsonb;

COMMENT ON COLUMN public.reports.data IS 'Snapshot of the rows returned when the report was generated, used to rebuild PDF/Excel downloads.';
