import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';

class CitizenRegistryService {
  final FirebaseFirestore _db;

  CitizenRegistryService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> watchRegistry() =>
      _db.collection('citizenRegistry').orderBy('legalName').snapshots();

  static String normalizeMobile(String value) =>
      value.replaceAll(RegExp(r'\D'), '');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchRecordByMobile(
    String mobile,
  ) => _db
      .collection('citizenRegistry')
      .where('mobile', isEqualTo: normalizeMobile(mobile))
      .limit(1)
      .snapshots();

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> findByMobile(
    String mobile,
  ) async {
    final result = await _db
        .collection('citizenRegistry')
        .where('mobile', isEqualTo: normalizeMobile(mobile))
        .limit(1)
        .get();
    return result.docs.firstOrNull;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingCorrections() => _db
      .collection('registryCorrections')
      .where('status', isEqualTo: 'pending')
      .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchResidentRequests(
    String mobile,
  ) => _db
      .collection('cases')
      .where('residentMobile', isEqualTo: normalizeMobile(mobile))
      .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchCaseActionLog(
    String caseId,
  ) => _db.collection('cases').doc(caseId).collection('actionLog').snapshots();

  Future<int> generateSyntheticRecords(
    UserModel actor, {
    int count = 200,
  }) async {
    await removeAccountDerivedRecords();
    final oldSeed = await _db
        .collection('citizenRegistry')
        .where('source', isEqualTo: 'synthetic_seed')
        .get();
    for (var start = 0; start < oldSeed.docs.length; start += 450) {
      final batch = _db.batch();
      for (final document in oldSeed.docs.skip(start).take(450)) {
        batch.delete(document.reference);
      }
      await batch.commit();
    }
    final operations = <void Function(WriteBatch)>[];
    const firstNames = [
      'Ana',
      'Juan',
      'Maria',
      'Pedro',
      'Rosa',
      'Carlos',
      'Elena',
      'Miguel',
      'Sofia',
      'Rafael',
      'Isabella',
      'Gabriel',
      'Lucia',
      'Antonio',
      'Carmen',
      'Fernando',
      'Teresa',
      'Roberto',
      'Beatriz',
      'Eduardo',
    ];
    const lastNames = [
      'Garcia',
      'Reyes',
      'Santos',
      'Dela Cruz',
      'Torres',
      'Ramos',
      'Mendoza',
      'Villanueva',
      'Aquino',
      'Bautista',
    ];
    const streets = [
      'Mabini Street',
      'Sampaguita Street',
      'Kalayaan Street',
      'Bayanihan Avenue',
      'Pag-asa Street',
      'Maligaya Road',
    ];
    const civilStatuses = ['Single', 'Married', 'Widowed', 'Separated'];
    const employmentStatuses = [
      'Employed',
      'Self-employed',
      'Unemployed',
      'Student',
      'Retired',
    ];
    const occupations = [
      'Teacher',
      'Driver',
      'Vendor',
      'Office worker',
      'Construction worker',
      'Healthcare worker',
      'Service crew',
      'Small business owner',
      'Student',
      'Retired',
      'Homemaker',
      'Freelancer',
    ];
    const incomeBrackets = [
      'Below ₱10,000',
      '₱10,000–₱19,999',
      '₱20,000–₱39,999',
      '₱40,000 and above',
    ];
    const classifications = [
      <String>[],
      ['Senior citizen'],
      ['PWD'],
      ['Solo parent'],
      ['Student'],
      ['4Ps beneficiary'],
    ];
    for (var index = 1; index <= count; index++) {
      final mobile = '0955${index.toString().padLeft(7, '0')}';
      final firstName = firstNames[(index - 1) % firstNames.length];
      final lastName =
          lastNames[((index - 1) ~/ firstNames.length) % lastNames.length];
      final legalName = '$firstName M. $lastName';
      final houseLot = ((index * 7) % 250 + 1).toString();
      final street = streets[(index - 1) % streets.length];
      final birthYear = 1945 + (index % 55);
      final birthMonth = (index % 12) + 1;
      final birthDay = (index % 27) + 1;
      final residencyYear = 1990 + (index % 30);
      final ref = _db.collection('citizenRegistry').doc(mobile);
      operations.add(
        (batch) => batch.set(ref, {
          'registryId': mobile,
          'legalName': legalName,
          'dateOfBirth':
              '${birthYear.toString().padLeft(4, '0')}-${birthMonth.toString().padLeft(2, '0')}-${birthDay.toString().padLeft(2, '0')}',
          'sex': index.isEven ? 'Female' : 'Male',
          'civilStatus': civilStatuses[index % civilStatuses.length],
          'nationality': 'Filipino',
          'houseLotNumber': houseLot,
          'street': street,
          'barangay': 'Calzada-Tipas',
          'city': 'Taguig City',
          'postalCode': '1637',
          'permanentAddress':
              '$houseLot $street, Barangay Calzada-Tipas, Taguig City 1637',
          'temporaryAddress':
              '$houseLot $street, Barangay Calzada-Tipas, Taguig City 1637',
          'residencySince': '$residencyYear-01-01',
          'mobile': mobile,
          'email': 'citizen${index.toString().padLeft(3, '0')}@example.com',
          'householdId':
              'HH-${((index - 1) ~/ 4 + 1).toString().padLeft(4, '0')}',
          'familyComposition': '${2 + (index % 6)} household members',
          'dependencies': (index % 4).toString(),
          'employmentStatus':
              employmentStatuses[index % employmentStatuses.length],
          'occupation': occupations[(index - 1) % occupations.length],
          'incomeBracket': incomeBrackets[index % incomeBrackets.length],
          'classifications': classifications[index % classifications.length],
          'voterStatus': index % 4 == 0 ? 'Not registered' : 'Registered',
          'precinctNumber': 'CT-${(index % 20 + 1).toString().padLeft(3, '0')}',
          'emergencyContactName':
              '${firstNames[index % firstNames.length]} ${lastNames[(index + 2) % lastNames.length]}',
          'emergencyContactMobile': '0966${index.toString().padLeft(7, '0')}',
          'emergencyContactRelationship': index.isEven ? 'Sibling' : 'Parent',
          'verificationStatus': 'verified',
          'source': 'synthetic_seed',
          'isSynthetic': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'verifiedAt': FieldValue.serverTimestamp(),
          'verifiedBy': actor.uid,
          'verifiedByName': actor.name,
        }),
      );
    }
    for (var start = 0; start < operations.length; start += 450) {
      final batch = _db.batch();
      for (final operation in operations.skip(start).take(450)) {
        operation(batch);
      }
      await batch.commit();
    }
    return count;
  }

  /// Removes only legacy registry entries that were copied from login
  /// accounts. Independent, manually maintained, and synthetic records remain.
  Future<int> removeAccountDerivedRecords() async {
    final residents = await _db
        .collection('users')
        .where('role', isEqualTo: 'resident')
        .get();
    final residentIds = residents.docs.map((document) => document.id).toSet();
    final registry = await _db.collection('citizenRegistry').get();
    final legacySources = {
      'resident_account',
      'resident_account_import',
      'account_import',
      'user_account',
    };
    final accountDerived = registry.docs.where((document) {
      final data = document.data();
      final linkedIds = [
        document.id,
        data['residentId'],
        data['userId'],
        data['accountId'],
        data['uid'],
      ].map((value) => (value ?? '').toString());
      final source = (data['source'] ?? '').toString().toLowerCase();
      return legacySources.contains(source) ||
          linkedIds.any(residentIds.contains);
    }).toList();

    for (var start = 0; start < accountDerived.length; start += 450) {
      final batch = _db.batch();
      for (final document in accountDerived.skip(start).take(450)) {
        batch.delete(document.reference);
      }
      await batch.commit();
    }
    return accountDerived.length;
  }

  Future<void> saveRecord({
    required String registryId,
    required Map<String, dynamic> values,
    required UserModel actor,
    required bool verify,
  }) async {
    final mobile = normalizeMobile((values['mobile'] ?? '').toString());
    if (mobile.isEmpty) {
      throw StateError('A valid mobile number is required.');
    }
    final duplicate = await _db
        .collection('citizenRegistry')
        .where('mobile', isEqualTo: mobile)
        .limit(2)
        .get();
    if (duplicate.docs.any((document) => document.id != registryId)) {
      throw StateError(
        'This mobile number already belongs to another registry record.',
      );
    }
    await _db.collection('citizenRegistry').doc(registryId).set({
      ...values,
      'mobile': mobile,
      'registryId': registryId,
      'verificationStatus': verify ? 'verified' : 'pending_verification',
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': actor.uid,
      'updatedByName': actor.name,
      if (verify) ...{
        'verifiedAt': FieldValue.serverTimestamp(),
        'verifiedBy': actor.uid,
        'verifiedByName': actor.name,
      },
    }, SetOptions(merge: true));
  }

  Future<void> submitCorrection({
    required String registryId,
    required UserModel resident,
    required String field,
    required String proposedValue,
    required String reason,
  }) async {
    await _db.collection('registryCorrections').add({
      'registryId': registryId,
      'residentId': resident.uid,
      'residentName': resident.name,
      'requestedChanges': {
        field: field == 'classifications'
            ? proposedValue
                  .split(',')
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty)
                  .toList()
            : proposedValue.trim(),
      },
      'reason': reason.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> resolveCorrection({
    required String correctionId,
    required UserModel reviewer,
    required bool approve,
    String rejectionReason = '',
  }) async {
    final correctionRef = _db
        .collection('registryCorrections')
        .doc(correctionId);
    await _db.runTransaction((transaction) async {
      final correction = await transaction.get(correctionRef);
      if (!correction.exists || correction.data()?['status'] != 'pending') {
        throw StateError('This correction request is no longer pending.');
      }
      final data = correction.data()!;
      if (approve) {
        final registryId = (data['registryId'] ?? '').toString();
        final changes = Map<String, dynamic>.from(
          data['requestedChanges'] as Map? ?? const {},
        );
        transaction.set(
          _db.collection('citizenRegistry').doc(registryId),
          {
            ...changes,
            'verificationStatus': 'verified',
            'updatedAt': FieldValue.serverTimestamp(),
            'verifiedAt': FieldValue.serverTimestamp(),
            'verifiedBy': reviewer.uid,
            'verifiedByName': reviewer.name,
          },
          SetOptions(merge: true),
        );
      }
      transaction.update(correctionRef, {
        'status': approve ? 'approved' : 'rejected',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': reviewer.uid,
        'reviewedByName': reviewer.name,
        if (!approve) 'rejectionReason': rejectionReason.trim(),
      });
    });
  }
}
