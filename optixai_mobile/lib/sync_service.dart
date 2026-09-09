import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final Connectivity _connectivity = Connectivity();
  // We'll use a placeholder URL. Update this with the real Supabase/Next.js URL.
  final String apiEndpoint = 'https://optixai-api.vercel.app/api/triage/sync';

  void initialize() {
    _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (!results.contains(ConnectivityResult.none)) {
        debugPrint('Connectivity restored. Attempting background sync...');
        syncPendingRecords();
      }
    });
  }

  Future<void> syncPendingRecords() async {
    final dbHelper = DatabaseHelper();
    final unsynced = await dbHelper.getUnsyncedRecords();

    if (unsynced.isEmpty) return;

    for (var record in unsynced) {
      try {
        var request = http.MultipartRequest('POST', Uri.parse(apiEndpoint));
        
        request.fields['patient_id'] = record['patient_id']?.toString() ?? '';
        request.fields['patient_name'] = record['patient_name']?.toString() ?? '';
        request.fields['age'] = record['age']?.toString() ?? '';
        request.fields['gender'] = record['gender']?.toString() ?? '';
        request.fields['diabetes_details'] = record['diabetes_details']?.toString() ?? '';
        request.fields['left_dr_grade'] = record['left_dr_grade']?.toString() ?? '';
        request.fields['right_dr_grade'] = record['right_dr_grade']?.toString() ?? '';

        if (record['left_eye_path'] != null && record['left_eye_path'].toString().isNotEmpty) {
          request.files.add(await http.MultipartFile.fromPath('left_eye_image', record['left_eye_path']));
        }
        if (record['right_eye_path'] != null && record['right_eye_path'].toString().isNotEmpty) {
          request.files.add(await http.MultipartFile.fromPath('right_eye_image', record['right_eye_path']));
        }

        var response = await request.send();
        if (response.statusCode == 200 || response.statusCode == 201) {
          await dbHelper.markSynced(record['id']);
          debugPrint('Successfully synced record ID: ${record['id']}');
        } else {
          debugPrint('Sync failed for ID: ${record['id']} with status ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('Error syncing record ID: ${record['id']}. Error: $e');
      }
    }
  }
}
