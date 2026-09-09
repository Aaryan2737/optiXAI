import { NextResponse } from 'next/server';
import { supabase } from '@/lib/supabase';

export async function POST(request: Request) {
  try {
    const formData = await request.formData();
    
    const image = formData.get('image') as File | null;
    const patient_name = formData.get('patient_name') as string | null;
    const dr_grade_str = formData.get('dr_grade') as string | null;
    
    if (!image || !patient_name || !dr_grade_str) {
      return NextResponse.json(
        { error: 'Missing required fields: image, patient_name, or dr_grade' },
        { status: 400 }
      );
    }
    
    const dr_grade = parseInt(dr_grade_str, 10);
    if (isNaN(dr_grade)) {
      return NextResponse.json(
        { error: 'dr_grade must be a valid number' },
        { status: 400 }
      );
    }
    
    // 1. Upload the image file to the Supabase fundus-captures bucket
    const fileExt = image.name.split('.').pop() || 'jpg';
    const fileName = `${Date.now()}-${Math.random().toString(36).substring(7)}.${fileExt}`;
    
    const { error: uploadError } = await supabase.storage
      .from('fundus-captures')
      .upload(fileName, image, {
        contentType: image.type,
        upsert: false,
      });
      
    if (uploadError) {
      console.error('Supabase Storage Upload Error:', uploadError);
      return NextResponse.json(
        { error: 'Failed to upload image to storage' },
        { status: 500 }
      );
    }
    
    // 2. Retrieve the public URL for the uploaded image
    const { data: publicUrlData } = supabase.storage
      .from('fundus-captures')
      .getPublicUrl(fileName);
      
    const image_url = publicUrlData.publicUrl;
    
    // 3. Insert a new row into the triage_records table
    const { data: recordData, error: insertError } = await supabase
      .from('triage_records')
      .insert([
        {
          patient_name,
          dr_grade,
          image_url,
          status: 'pending',
        }
      ])
      .select()
      .single();
      
    if (insertError) {
      console.error('Supabase Database Insert Error:', insertError);
      return NextResponse.json(
        { error: 'Failed to insert triage record' },
        { status: 500 }
      );
    }
    
    // 4. Return a 201 JSON response upon success
    return NextResponse.json(
      { success: true, data: recordData },
      { status: 201 }
    );
    
  } catch (error) {
    console.error('API Route /api/triage/sync Error:', error);
    return NextResponse.json(
      { error: 'Internal Server Error' },
      { status: 500 }
    );
  }
}
