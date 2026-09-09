export interface TriageRecord {
  id: string;
  patient_name: string;
  dr_grade: number;
  image_url: string;
  llm_draft_report: string;
  status: 'pending' | 'approved';
  created_at: string;
}
