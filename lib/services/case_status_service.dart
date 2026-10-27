import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/budget_health.dart';
import '../utils/budget_period.dart';
import '../utils/constants.dart';
import 'document_vault_service.dart';
import 'cash_position_service.dart';

class CaseStatusService {
  final FirebaseFirestore _db;

  CaseStatusService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  Future<void> updateStatus({
    required String caseId,
    required String newStatus,
    required String notes,
    required String staffId,
    required String staffName,
    required String staffRole,
    String? referenceNumber,
    bool smsSent = false,
    String? smsError,
    String smsBody = '',
    DateTime? changedAt,
    bool budgetApprovalConfirmed = false,
    double? approvedAssistanceAmount,
    List<String> correctionFields = const [],
    List<String> correctionDocuments = const [],
  }) async {
    final effectiveDate = changedAt ?? DateTime.now();
    if (newStatus == statusReleased) {
      await CashPositionService(
        firestore: _db,
      ).reconcileMaturedTransfers(asOf: effectiveDate);
    }
    final caseRef = _db.collection('cases').doc(caseId);
    final initialCase = await caseRef.get();
    if (!initialCase.exists) throw StateError('Case not found.');

    final initialData = initialCase.data()!;
    final registryRef = await _registryReferenceForCase(initialData);
    DocumentReference<Map<String, dynamic>>? programRef;

    if (newStatus == statusApproved && _requiresBudgetReview(initialData)) {
      final programName = budgetProgramNameForCase(
        (initialData['serviceCategory'] ?? '').toString(),
        (initialData['serviceSubType'] ?? '').toString(),
      );
      if (programName == null) {
        throw StateError(
          'No budget program mapping exists for this assistance case type.',
        );
      }
      programRef = await _findQuarterlyProgram(programName, effectiveDate);
      if (programRef == null) {
        final quarter = quarterForDate(effectiveDate);
        throw StateError(
          'No $programName allocation exists for '
          'FY ${effectiveDate.year} Q$quarter.',
        );
      }
    } else if ((newStatus == statusReleased || newStatus == statusRejected) &&
        (initialData['budgetReservedProgramId'] ?? '').toString().isNotEmpty) {
      programRef = _db
          .collection('budgetPrograms')
          .doc(initialData['budgetReservedProgramId'].toString());
    } else if (_requiresBudgetDeduction(initialData, newStatus)) {
      final programName = budgetProgramNameForCase(
        (initialData['serviceCategory'] ?? '').toString(),
        (initialData['serviceSubType'] ?? '').toString(),
      );
      programRef = programName == null
          ? null
          : await _findQuarterlyProgram(programName, effectiveDate);
    }

    final logRef = caseRef.collection('actionLog').doc();
    final residentNotificationRef = _db.collection('notifications').doc();
    final requesterNotificationRef = _db.collection('notifications').doc();
    final budgetTransactionRef = _db
        .collection('budgetTransactions')
        .doc(caseId);
    final cashPositionRef = _db
        .collection('cashPositions')
        .doc(CashPositionService.positionDocumentId);
    final cashMovementRef = _db.collection('cashMovements').doc('case_$caseId');

    await _db.runTransaction((transaction) async {
      final currentCase = await transaction.get(caseRef);
      if (!currentCase.exists) throw StateError('Case not found.');

      final caseData = currentCase.data()!;
      final previousStatus = (caseData['status'] ?? '').toString();
      final cashDisbursementAmount = newStatus == statusReleased
          ? budgetDeductionAmountForCase(caseData)
          : 0.0;
      final cashPosition = cashDisbursementAmount > 0
          ? await transaction.get(cashPositionRef)
          : null;
      if (!validNextCaseStatuses(previousStatus).contains(newStatus)) {
        throw StateError(
          'Cannot change status from '
          '${caseStatusLabel(previousStatus)} to ${caseStatusLabel(newStatus)}.',
        );
      }
      if (newStatus == statusForClaiming && staffRole != roleCaptain) {
        throw StateError(
          'Barangay Captain approval is required before a case can move to '
          'For Claiming.',
        );
      }
      if (newStatus == statusApproved &&
          _requiresBudgetReview(caseData) &&
          !budgetApprovalConfirmed) {
        throw StateError(
          'Review and confirm the budget impact before approving this case.',
        );
      }
      final updates = <String, dynamic>{
        'status': newStatus,
        'lastUpdated': FieldValue.serverTimestamp(),
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      };
      if (newStatus == statusNeedsCorrection) {
        if (correctionFields.isEmpty && correctionDocuments.isEmpty) {
          throw StateError(
            'Flag at least one information field or document for correction.',
          );
        }
        updates['correctionRequest'] = {
          'status': 'open',
          'reason': notes,
          'fields': correctionFields,
          'documents': correctionDocuments,
          'returnStatus': previousStatus == statusProcessing
              ? statusProcessing
              : statusPendingReview,
          'requestedAt': FieldValue.serverTimestamp(),
          'requestedBy': staffId,
          'requestedByName': staffName,
          'requestedByRole': staffRole,
        };
      }
      if (newStatus == statusForClaiming) {
        updates.addAll({
          'claimingApprovalStatus': 'approved',
          'claimingApprovedBy': staffId,
          'claimingApprovedByName': staffName,
          'claimingApprovedAt': FieldValue.serverTimestamp(),
        });
      }
      final category = (caseData['serviceCategory'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (newStatus == statusApproved && category == 'education') {
        if (approvedAssistanceAmount == null ||
            !approvedAssistanceAmount.isFinite ||
            approvedAssistanceAmount < 500 ||
            approvedAssistanceAmount > 1000) {
          throw StateError(
            'Education Incentive assistance must be from ₱500 to ₱1,000.',
          );
        }
        updates['assistanceAmount'] = approvedAssistanceAmount;
      }
      if (newStatus == statusApproved && category == 'bass') {
        if (approvedAssistanceAmount == null ||
            !approvedAssistanceAmount.isFinite ||
            approvedAssistanceAmount <= 0) {
          throw StateError('Enter a valid final BASS assistance amount.');
        }
        updates['assistanceAmount'] = approvedAssistanceAmount;
      }

      if (newStatus == statusApproved && _requiresBudgetReview(caseData)) {
        if (programRef == null || approvedAssistanceAmount == null) {
          throw StateError('The applicable quarterly budget was not found.');
        }
        final programSnapshot = await transaction.get(programRef);
        if (!programSnapshot.exists) {
          throw StateError('The applicable quarterly budget was not found.');
        }
        final programData = programSnapshot.data()!;
        final allocated = (programData['allocated'] as num?)?.toDouble() ?? 0;
        final utilized = (programData['utilized'] as num?)?.toDouble() ?? 0;
        final reserved = (programData['reserved'] as num?)?.toDouble() ?? 0;
        if (allocated - utilized - reserved < approvedAssistanceAmount) {
          throw StateError(
            'The applicable budget does not have enough available balance.',
          );
        }
        final newReserved = reserved + approvedAssistanceAmount;
        final quarter = quarterForDate(effectiveDate);
        transaction.update(programRef, {
          'reserved': newReserved,
          'remaining': allocated - utilized - newReserved,
          'status': calculateBudgetHealth(
            allocated: allocated,
            utilized: utilized + newReserved,
            fiscalYear: effectiveDate.year,
            quarter: quarter,
            asOf: effectiveDate,
          ),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        updates.addAll({
          'budgetReservedProgramId': programRef.id,
          'budgetReservedAmount': approvedAssistanceAmount,
          'budgetReservedFiscalYear': effectiveDate.year,
          'budgetReservedQuarter': quarter,
          'budgetReservedAt': FieldValue.serverTimestamp(),
        });
      } else if (newStatus == statusReleased &&
          (caseData['budgetReservedAt'] != null ||
              _requiresBudgetDeduction(caseData, newStatus))) {
        if (programRef == null) {
          throw StateError('The applicable quarterly budget was not found.');
        }

        final amount =
            (caseData['budgetReservedAmount'] as num?)?.toDouble() ??
            budgetDeductionAmountForCase(caseData);
        final programSnapshot = await transaction.get(programRef);
        if (!programSnapshot.exists) {
          throw StateError('The applicable quarterly budget was not found.');
        }

        final programData = programSnapshot.data()!;
        final allocated = (programData['allocated'] as num?)?.toDouble() ?? 0;
        final utilized = (programData['utilized'] as num?)?.toDouble() ?? 0;
        final reserved = (programData['reserved'] as num?)?.toDouble() ?? 0;
        final hasReservation = caseData['budgetReservedAt'] != null;
        if (!hasReservation && allocated - utilized - reserved < amount) {
          throw StateError(
            'The applicable budget no longer has enough remaining balance '
            'for this case.',
          );
        }
        final newUtilized = utilized + amount;
        final newReserved = hasReservation
            ? (reserved - amount).clamp(0, double.infinity).toDouble()
            : reserved;
        final quarter =
            (caseData['budgetReservedQuarter'] as num?)?.toInt() ??
            quarterForDate(effectiveDate);
        final fiscalYear =
            (caseData['budgetReservedFiscalYear'] as num?)?.toInt() ??
            effectiveDate.year;
        final budgetStatus = calculateBudgetHealth(
          allocated: allocated,
          utilized: newUtilized + newReserved,
          fiscalYear: fiscalYear,
          quarter: quarter,
          asOf: effectiveDate,
        );

        transaction.update(programRef, {
          'utilized': newUtilized,
          'reserved': newReserved,
          'remaining': allocated - newUtilized - newReserved,
          'status': budgetStatus,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        transaction.set(budgetTransactionRef, {
          'programId': programRef.id,
          'caseId': caseId,
          'referenceNumber':
              referenceNumber ?? caseData['referenceNumber'] ?? '',
          'residentName': caseData['residentName'] ?? '',
          'serviceSubType': caseData['serviceSubType'] ?? '',
          'amount': amount,
          'type': 'deduction',
          'fiscalYear': fiscalYear,
          'quarter': quarter,
          'approvedBy': staffId,
          'releasedBy': staffId,
          'timestamp': FieldValue.serverTimestamp(),
        });

        updates.addAll({
          'budgetProgramId': programRef.id,
          'budgetDeductedAmount': amount,
          'budgetDeductedFiscalYear': fiscalYear,
          'budgetDeductedQuarter': quarter,
          'budgetDeductedAt': FieldValue.serverTimestamp(),
          'budgetReservedAt': FieldValue.delete(),
        });
      } else if (newStatus == statusRejected &&
          caseData['budgetReservedAt'] != null) {
        if (programRef == null) {
          throw StateError('The reserved budget program was not found.');
        }
        final programSnapshot = await transaction.get(programRef);
        if (!programSnapshot.exists) {
          throw StateError('The reserved budget program was not found.');
        }
        final programData = programSnapshot.data()!;
        final allocated = (programData['allocated'] as num?)?.toDouble() ?? 0;
        final utilized = (programData['utilized'] as num?)?.toDouble() ?? 0;
        final reserved = (programData['reserved'] as num?)?.toDouble() ?? 0;
        final amount =
            (caseData['budgetReservedAmount'] as num?)?.toDouble() ?? 0;
        final newReserved = (reserved - amount)
            .clamp(0, double.infinity)
            .toDouble();
        final fiscalYear =
            (caseData['budgetReservedFiscalYear'] as num?)?.toInt() ??
            effectiveDate.year;
        final quarter =
            (caseData['budgetReservedQuarter'] as num?)?.toInt() ??
            quarterForDate(effectiveDate);
        transaction.update(programRef, {
          'reserved': newReserved,
          'remaining': allocated - utilized - newReserved,
          'status': calculateBudgetHealth(
            allocated: allocated,
            utilized: utilized + newReserved,
            fiscalYear: fiscalYear,
            quarter: quarter,
            asOf: effectiveDate,
          ),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        updates.addAll({
          'budgetReservedAt': FieldValue.delete(),
          'budgetReservedAmount': FieldValue.delete(),
          'budgetReservedProgramId': FieldValue.delete(),
        });
      }

      if (newStatus == statusReleased &&
          cashDisbursementAmount > 0 &&
          cashPosition?.exists == true &&
          cashPosition?.data()?['initialized'] == true) {
        final cashData = cashPosition!.data()!;
        final cashOnHand = (cashData['cashOnHand'] as num?)?.toDouble() ?? 0;
        if (cashOnHand < cashDisbursementAmount) {
          throw StateError(
            'Cash on hand is insufficient for this release. Transfer funds '
            'from the bank and wait for them to arrive before releasing the case.',
          );
        }
        transaction.update(cashPositionRef, {
          'cashOnHand': cashOnHand - cashDisbursementAmount,
          'lastMovementId': cashMovementRef.id,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        transaction.set(cashMovementRef, {
          'type': 'case_disbursement',
          'status': 'completed',
          'amount': cashDisbursementAmount,
          'reason': 'Released cash assistance',
          'caseId': caseId,
          'referenceNumber':
              referenceNumber ?? caseData['referenceNumber'] ?? '',
          'residentName': caseData['residentName'] ?? '',
          'serviceSubType': caseData['serviceSubType'] ?? '',
          'requestedAt': FieldValue.serverTimestamp(),
          'effectiveAt': FieldValue.serverTimestamp(),
          'requestedBy': staffId,
          'requestedByName': staffName,
          'requestedByRole': staffRole,
        });
        updates.addAll({
          'cashDisbursedAmount': cashDisbursementAmount,
          'cashDisbursedAt': FieldValue.serverTimestamp(),
          'cashMovementId': cashMovementRef.id,
        });
      }

      // A released case has completed review. Merge the verified personal
      // facts it contains into the authoritative citizen record and retain
      // only conservative identity documents for future requests.
      if (newStatus == statusReleased && registryRef != null) {
        updates['registryId'] = registryRef.id;
        updates['registryMatchStatus'] = 'verified_match';
        updates['registryCheckedAt'] = FieldValue.serverTimestamp();
        _writeReleasedRegistrySync(
          transaction: transaction,
          registryRef: registryRef,
          caseData: caseData,
          caseId: caseId,
          staffId: staffId,
          staffName: staffName,
          effectiveDate: effectiveDate,
          referenceNumber: referenceNumber,
        );
      }

      transaction.update(caseRef, updates);
      transaction.set(logRef, {
        'caseId': caseId,
        'referenceNumber': referenceNumber ?? caseData['referenceNumber'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'staffId': staffId,
        'staffName': staffName,
        'action': 'Status changed: $previousStatus → $newStatus',
        'previousStatus': previousStatus,
        'newStatus': newStatus,
        'notes': notes,
        'smsSent': smsSent,
        'smsError': smsError,
        'smsBody': smsBody,
      });
      final residentId = (caseData['residentId'] ?? '').toString();
      if (residentId.isNotEmpty) {
        transaction.set(residentNotificationRef, {
          'type': _notificationType(newStatus),
          'title': _notificationTitle(newStatus),
          'message': _notificationMessage(
            newStatus: newStatus,
            referenceNumber:
                referenceNumber ?? caseData['referenceNumber'] ?? '',
            notes: notes,
          ),
          'caseId': caseId,
          'referenceNumber':
              referenceNumber ?? caseData['referenceNumber'] ?? '',
          'recipientId': residentId,
          'audienceRoles': <String>[],
          'createdById': staffId,
          'createdAt': FieldValue.serverTimestamp(),
          'readBy': <String>[],
          'deletedBy': <String>[],
        });
      }
      final claimingRequesterId = (caseData['claimingRequestedBy'] ?? '')
          .toString();
      if (newStatus == statusForClaiming &&
          claimingRequesterId.isNotEmpty &&
          claimingRequesterId != staffId) {
        transaction.set(requesterNotificationRef, {
          'type': 'claiming_approved',
          'title': 'For Claiming request approved',
          'message':
              'Case ${referenceNumber ?? caseData['referenceNumber'] ?? ''} was approved by the Barangay Captain.',
          'caseId': caseId,
          'referenceNumber':
              referenceNumber ?? caseData['referenceNumber'] ?? '',
          'recipientId': claimingRequesterId,
          'audienceRoles': <String>[],
          'createdById': staffId,
          'createdAt': FieldValue.serverTimestamp(),
          'readBy': <String>[],
          'deletedBy': <String>[],
        });
      }
    });
  }

  String _notificationType(String status) => switch (status) {
    statusNeedsCorrection => 'needs_correction',
    statusRejected => 'case_rejected',
    statusReleased => 'case_released',
    _ => 'case_status',
  };

  String _notificationTitle(String status) => switch (status) {
    statusNeedsCorrection => 'Corrections requested',
    statusApproved => 'Request approved',
    statusForClaiming => 'Ready for claiming',
    statusReleased => 'Assistance released',
    statusRejected => 'Request rejected',
    statusProcessing => 'Request is being processed',
    _ => 'Case status updated',
  };

  String _notificationMessage({
    required String newStatus,
    required Object referenceNumber,
    required String notes,
  }) {
    final statusText = caseStatusLabel(newStatus);
    final reason = notes.trim();
    return 'Case $referenceNumber is now $statusText.'
        '${reason.isEmpty ? '' : ' Note: $reason'}';
  }

  Future<DocumentReference<Map<String, dynamic>>?> _registryReferenceForCase(
    Map<String, dynamic> caseData,
  ) async {
    if (caseData['requestedForSelf'] == false) return null;
    final mobile =
        (caseData['requesterMobile'] ?? caseData['residentMobile'] ?? '')
            .toString()
            .replaceAll(RegExp(r'\D'), '');
    if (mobile.isNotEmpty) {
      final matches = await _db
          .collection('citizenRegistry')
          .where('mobile', isEqualTo: mobile)
          .get();
      if (matches.docs.isNotEmpty) {
        final canonical = matches.docs.where((doc) => doc.id == mobile);
        if (canonical.isNotEmpty) return canonical.first.reference;
        final linkedId = (caseData['registryId'] ?? '').toString().trim();
        final linked = matches.docs.where((doc) => doc.id == linkedId);
        if (linked.isNotEmpty) return linked.first.reference;
        return matches.docs.first.reference;
      }
    }
    final registryId = (caseData['registryId'] ?? '').toString().trim();
    if (registryId.isEmpty) return null;
    final linked = await _db
        .collection('citizenRegistry')
        .doc(registryId)
        .get();
    return linked.exists ? linked.reference : null;
  }

  void _writeReleasedRegistrySync({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> registryRef,
    required Map<String, dynamic> caseData,
    required String caseId,
    required String staffId,
    required String staffName,
    required DateTime effectiveDate,
    String? referenceNumber,
  }) {
    final resolvedReference =
        referenceNumber ?? caseData['referenceNumber'] ?? '';
    transaction.set(registryRef, {
      ..._registryUpdatesFromReleasedCase(caseData),
      'registryId': registryRef.id,
      'verificationStatus': 'verified',
      'verifiedAt': FieldValue.serverTimestamp(),
      'verifiedBy': staffId,
      'verifiedByName': staffName,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': staffId,
      'updatedByName': staffName,
      'lastVerifiedCaseId': caseId,
      'lastVerifiedReferenceNumber': resolvedReference,
    }, SetOptions(merge: true));

    final documents = caseData['documents'];
    if (documents is! List) return;
    for (final rawDocument in documents) {
      if (rawDocument is! Map) continue;
      final document = Map<String, dynamic>.from(rawDocument);
      final name = (document['name'] ?? '').toString();
      final validityDays = DocumentVaultService.validityDays(name);
      if (validityDays == null ||
          !['uploaded', 'reused', 'verified'].contains(document['status']) ||
          (document['databasePath'] ?? '').toString().isEmpty) {
        continue;
      }
      final vaultRef = registryRef
          .collection('verifiedDocuments')
          .doc(DocumentVaultService.documentKey(name));
      final existingValidUntil = document['validUntil'];
      final validUntil =
          document['status'] != 'uploaded' && existingValidUntil is Timestamp
          ? existingValidUntil
          : Timestamp.fromDate(effectiveDate.add(Duration(days: validityDays)));
      transaction.set(vaultRef, {
        ...document,
        'status': 'verified',
        'verificationStatus': 'verified',
        'sourceCaseId': caseId,
        'sourceReferenceNumber': resolvedReference,
        'verifiedAt': FieldValue.serverTimestamp(),
        'verifiedBy': staffId,
        'verifiedByName': staffName,
        'validUntil': validUntil,
      }, SetOptions(merge: true));
    }
  }

  /// Repairs registry/vault synchronization for a case that was already
  /// released, including cases created with an older or stale registry ID.
  Future<bool> syncReleasedCaseRegistry({
    required String caseId,
    required String staffId,
    required String staffName,
  }) async {
    final caseRef = _db.collection('cases').doc(caseId);
    final initial = await caseRef.get();
    if (!initial.exists ||
        normalizeCaseStatus((initial.data()?['status'] ?? '').toString()) !=
            statusReleased) {
      return false;
    }
    final registryRef = await _registryReferenceForCase(initial.data()!);
    if (registryRef == null) return false;
    await _db.runTransaction((transaction) async {
      final current = await transaction.get(caseRef);
      if (!current.exists ||
          normalizeCaseStatus((current.data()?['status'] ?? '').toString()) !=
              statusReleased) {
        return;
      }
      final data = current.data()!;
      _writeReleasedRegistrySync(
        transaction: transaction,
        registryRef: registryRef,
        caseData: data,
        caseId: caseId,
        staffId: staffId,
        staffName: staffName,
        effectiveDate: DateTime.now(),
      );
      transaction.update(caseRef, {
        'registryId': registryRef.id,
        'registryMatchStatus': 'verified_match',
        'registryCheckedAt': FieldValue.serverTimestamp(),
        'registrySyncedAt': FieldValue.serverTimestamp(),
      });
    });
    return true;
  }

  static Map<String, dynamic> _registryUpdatesFromReleasedCase(
    Map<String, dynamic> caseData,
  ) {
    if (caseData['requestedForSelf'] == false) return const {};
    final details = Map<String, dynamic>.from(
      caseData['requestDetails'] as Map? ?? const {},
    );
    final result = <String, dynamic>{};

    void copy(String registryKey, Iterable<String> caseKeys) {
      for (final key in caseKeys) {
        final value = details[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          result[registryKey] = value is String ? value.trim() : value;
          return;
        }
      }
    }

    copy('legalName', const [
      'fullName',
      'patientName',
      'beneficiaryName',
      'studentName',
      'reporterName',
    ]);
    if (!result.containsKey('legalName')) {
      final first = (details['firstName'] ?? '').toString().trim();
      final middle = (details['middleInitial'] ?? '').toString().trim();
      final surname = (details['surname'] ?? '').toString().trim();
      final name = [
        first,
        middle,
        surname,
      ].where((part) => part.isNotEmpty).join(' ');
      if (name.isNotEmpty) result['legalName'] = name;
    }
    copy('dateOfBirth', const ['birthday']);
    copy('sex', const ['gender']);
    copy('civilStatus', const ['civilStatus']);
    copy('birthplace', const ['birthplace']);
    copy('precinctNumber', const ['precinct']);
    copy('emergencyContactName', const ['emergencyName']);
    copy('emergencyContactMobile', const ['emergencyContact']);
    copy('emergencyContactRelationship', const ['emergencyRelation']);

    final category = (caseData['serviceCategory'] ?? '').toString();
    final subType = (caseData['serviceSubType'] ?? '').toString();
    final isInfrastructureConcern =
        category == 'community' && subType == 'Infrastructure Concern';
    if (!isInfrastructureConcern) {
      copy('permanentAddress', const ['address']);
      if (caseData['addressLocation'] is Map) {
        result['permanentAddressLocation'] = caseData['addressLocation'];
      }
    }
    final mobile = (caseData['requesterMobile'] ?? '').toString().replaceAll(
      RegExp(r'\D'),
      '',
    );
    if (mobile.isNotEmpty) result['mobile'] = mobile;
    return result;
  }

  Future<void> requestForClaimingApproval({
    required String caseId,
    required String notes,
    required String staffId,
    required String staffName,
    required String staffRole,
    String? referenceNumber,
  }) async {
    if (staffRole == roleCaptain) {
      throw StateError('Captains should approve the case directly.');
    }
    if (staffRole != roleStaff && staffRole != roleOfficer) {
      throw StateError(
        'Only barangay staff or officers can submit this request.',
      );
    }

    final caseRef = _db.collection('cases').doc(caseId);
    final logRef = caseRef.collection('actionLog').doc();
    final notificationRef = _db.collection('notifications').doc();
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(caseRef);
      if (!snapshot.exists) throw StateError('Case not found.');
      final data = snapshot.data()!;
      final status = normalizeCaseStatus((data['status'] ?? '').toString());
      if (status != statusApproved) {
        throw StateError(
          'Only Approved cases can be submitted for claiming approval.',
        );
      }
      if (data['claimingApprovalStatus'] == 'pending') {
        throw StateError('This case is already awaiting captain approval.');
      }

      transaction.update(caseRef, {
        'claimingApprovalStatus': 'pending',
        'claimingRequestedBy': staffId,
        'claimingRequestedByName': staffName,
        'claimingRequestedAt': FieldValue.serverTimestamp(),
        'claimingRequestReason': notes,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      transaction.set(logRef, {
        'caseId': caseId,
        'referenceNumber': referenceNumber ?? data['referenceNumber'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'staffId': staffId,
        'staffName': staffName,
        'action': 'For Claiming approval requested',
        'previousStatus': statusApproved,
        'newStatus': '',
        'notes': notes,
        'smsSent': false,
        'smsBody': '',
      });
      transaction.set(notificationRef, {
        'type': 'claiming_approval',
        'title': 'For Claiming approval needed',
        'message':
            '$staffName requested approval for case ${referenceNumber ?? data['referenceNumber'] ?? ''}.',
        'caseId': caseId,
        'referenceNumber': referenceNumber ?? data['referenceNumber'] ?? '',
        'recipientId': '',
        'audienceRoles': const ['captain'],
        'createdById': staffId,
        'createdAt': FieldValue.serverTimestamp(),
        'readBy': <String>[],
        'deletedBy': <String>[],
      });
    });
  }

  Future<void> rejectForClaimingApproval({
    required String caseId,
    required String reason,
    required String captainId,
    required String captainName,
    required String captainRole,
    String? referenceNumber,
  }) async {
    if (captainRole != roleCaptain) {
      throw StateError(
        'Only the Barangay Captain can reject a For Claiming request.',
      );
    }
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw StateError('Enter a reason for rejecting this request.');
    }
    final effectiveDate = DateTime.now();

    final caseRef = _db.collection('cases').doc(caseId);
    final initialCase = await caseRef.get();
    if (!initialCase.exists) throw StateError('Case not found.');
    final initialData = initialCase.data()!;
    final reservedProgramId = (initialData['budgetReservedProgramId'] ?? '')
        .toString();
    final programRef = reservedProgramId.isEmpty
        ? null
        : _db.collection('budgetPrograms').doc(reservedProgramId);
    final logRef = caseRef.collection('actionLog').doc();
    final requesterNotificationRef = _db.collection('notifications').doc();

    await _db.runTransaction((transaction) async {
      final caseSnapshot = await transaction.get(caseRef);
      if (!caseSnapshot.exists) throw StateError('Case not found.');
      final caseData = caseSnapshot.data()!;
      final currentStatus = normalizeCaseStatus(
        (caseData['status'] ?? '').toString(),
      );
      final requestingStaffId = (caseData['claimingRequestedBy'] ?? '')
          .toString();
      if (currentStatus != statusApproved ||
          caseData['claimingApprovalStatus'] != 'pending') {
        throw StateError(
          'This case is not awaiting Barangay Captain approval.',
        );
      }

      final updates = <String, dynamic>{
        'status': statusProcessing,
        'claimingApprovalStatus': 'rejected',
        'claimingRejectedBy': captainId,
        'claimingRejectedByName': captainName,
        'claimingRejectedAt': FieldValue.serverTimestamp(),
        'claimingRejectionReason': trimmedReason,
        'lastUpdated': FieldValue.serverTimestamp(),
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      };

      if (caseData['budgetReservedAt'] != null && programRef != null) {
        final programSnapshot = await transaction.get(programRef);
        if (!programSnapshot.exists) {
          throw StateError('The reserved budget program was not found.');
        }
        final programData = programSnapshot.data()!;
        final allocated = (programData['allocated'] as num?)?.toDouble() ?? 0;
        final utilized = (programData['utilized'] as num?)?.toDouble() ?? 0;
        final reserved = (programData['reserved'] as num?)?.toDouble() ?? 0;
        final amount =
            (caseData['budgetReservedAmount'] as num?)?.toDouble() ?? 0;
        final newReserved = (reserved - amount)
            .clamp(0, double.infinity)
            .toDouble();
        final fiscalYear =
            (caseData['budgetReservedFiscalYear'] as num?)?.toInt() ??
            effectiveDate.year;
        final quarter =
            (caseData['budgetReservedQuarter'] as num?)?.toInt() ??
            quarterForDate(effectiveDate);

        transaction.update(programRef, {
          'reserved': newReserved,
          'remaining': allocated - utilized - newReserved,
          'status': calculateBudgetHealth(
            allocated: allocated,
            utilized: utilized + newReserved,
            fiscalYear: fiscalYear,
            quarter: quarter,
            asOf: effectiveDate,
          ),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        updates.addAll({
          'budgetReservedAt': FieldValue.delete(),
          'budgetReservedAmount': FieldValue.delete(),
          'budgetReservedProgramId': FieldValue.delete(),
          'budgetReservedFiscalYear': FieldValue.delete(),
          'budgetReservedQuarter': FieldValue.delete(),
        });
      }

      transaction.update(caseRef, updates);
      transaction.set(logRef, {
        'caseId': caseId,
        'referenceNumber': referenceNumber ?? caseData['referenceNumber'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'staffId': captainId,
        'staffName': captainName,
        'action': 'For Claiming approval rejected',
        'previousStatus': statusApproved,
        'newStatus': statusProcessing,
        'notes': trimmedReason,
        'smsSent': false,
        'smsBody': '',
      });
      if (requestingStaffId.isNotEmpty) {
        transaction.set(requesterNotificationRef, {
          'type': 'claiming_rejected',
          'title': 'For Claiming request rejected',
          'message':
              'Case ${referenceNumber ?? caseData['referenceNumber'] ?? ''} returned to Processing. Reason: $trimmedReason',
          'caseId': caseId,
          'referenceNumber':
              referenceNumber ?? caseData['referenceNumber'] ?? '',
          'recipientId': requestingStaffId,
          'audienceRoles': <String>[],
          'createdById': captainId,
          'createdAt': FieldValue.serverTimestamp(),
          'readBy': <String>[],
          'deletedBy': <String>[],
        });
      }
    });
  }

  Future<BudgetApprovalPreview> getBudgetApprovalPreview({
    required String caseId,
    DateTime? asOf,
    double? assistanceAmountOverride,
  }) async {
    final effectiveDate = asOf ?? DateTime.now();
    final caseSnapshot = await _db.collection('cases').doc(caseId).get();
    if (!caseSnapshot.exists) throw StateError('Case not found.');

    final caseData = caseSnapshot.data()!;
    final amount =
        assistanceAmountOverride ?? budgetDeductionAmountForCase(caseData);
    final programName = budgetProgramNameForCase(
      (caseData['serviceCategory'] ?? '').toString(),
      (caseData['serviceSubType'] ?? '').toString(),
    );
    if (amount <= 0 || programName == null) {
      return BudgetApprovalPreview(
        fiscalYear: effectiveDate.year,
        quarter: quarterForDate(effectiveDate),
        assistanceAmount: amount,
      );
    }

    final programRef = await _findQuarterlyProgram(programName, effectiveDate);
    if (programRef == null) {
      throw StateError(
        'No $programName allocation exists for '
        'FY ${effectiveDate.year} Q${quarterForDate(effectiveDate)}.',
      );
    }
    final programSnapshot = await programRef.get();
    final programData = programSnapshot.data()!;
    final allocated = (programData['allocated'] as num?)?.toDouble() ?? 0;
    final utilized = (programData['utilized'] as num?)?.toDouble() ?? 0;
    final reserved = (programData['reserved'] as num?)?.toDouble() ?? 0;
    final remaining = allocated - utilized - reserved;

    return BudgetApprovalPreview(
      programId: programRef.id,
      programName: programName,
      fiscalYear: effectiveDate.year,
      quarter: quarterForDate(effectiveDate),
      allocated: allocated,
      utilized: utilized,
      reserved: reserved,
      currentRemaining: remaining,
      assistanceAmount: amount,
      projectedRemaining: remaining - amount,
      currentStatus: (programData['status'] ?? '').toString(),
    );
  }

  bool _requiresBudgetDeduction(
    Map<String, dynamic> caseData,
    String newStatus,
  ) {
    final amount = budgetDeductionAmountForCase(caseData);
    final programName = budgetProgramNameForCase(
      (caseData['serviceCategory'] ?? '').toString(),
      (caseData['serviceSubType'] ?? '').toString(),
    );
    return newStatus == 'released' &&
        amount > 0 &&
        programName != null &&
        caseData['budgetDeductedAt'] == null;
  }

  bool _requiresBudgetReview(Map<String, dynamic> caseData) {
    return budgetProgramNameForCase(
          (caseData['serviceCategory'] ?? '').toString(),
          (caseData['serviceSubType'] ?? '').toString(),
        ) !=
        null;
  }

  Future<DocumentReference<Map<String, dynamic>>?> _findQuarterlyProgram(
    String programName,
    DateTime date,
  ) async {
    final quarter = quarterForDate(date);
    final snapshot = await _db
        .collection('budgetPrograms')
        .where('name', isEqualTo: programName)
        .get();

    QueryDocumentSnapshot<Map<String, dynamic>>? latest;
    for (final doc in snapshot.docs) {
      final period = BudgetPeriod.fromData(doc.data());
      if (period.type != 'quarterly' ||
          period.fiscalYear != date.year ||
          period.quarter != quarter) {
        continue;
      }
      if (latest == null ||
          _lastUpdated(doc.data()) > _lastUpdated(latest.data()) ||
          (_lastUpdated(doc.data()) == _lastUpdated(latest.data()) &&
              doc.id.compareTo(latest.id) > 0)) {
        latest = doc;
      }
    }
    return latest?.reference;
  }

  int _lastUpdated(Map<String, dynamic> data) {
    return (data['lastUpdated'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
  }
}

class BudgetApprovalPreview {
  final String? programId;
  final String? programName;
  final int fiscalYear;
  final int quarter;
  final double allocated;
  final double utilized;
  final double reserved;
  final double currentRemaining;
  final double assistanceAmount;
  final double projectedRemaining;
  final String currentStatus;

  const BudgetApprovalPreview({
    this.programId,
    this.programName,
    required this.fiscalYear,
    required this.quarter,
    this.allocated = 0,
    this.utilized = 0,
    this.reserved = 0,
    this.currentRemaining = 0,
    this.assistanceAmount = 0,
    this.projectedRemaining = 0,
    this.currentStatus = '',
  });

  bool get hasBudgetImpact => programId != null && assistanceAmount > 0;
  bool get hasSufficientBalance => !hasBudgetImpact || projectedRemaining >= 0;
}

int quarterForDate(DateTime date) => ((date.month - 1) ~/ 3) + 1;

/// All budget-linked cases use the final assistance amount stored on the case.
double budgetDeductionAmountForCase(Map<String, dynamic> caseData) {
  return (caseData['assistanceAmount'] as num?)?.toDouble() ?? 0;
}

String? budgetProgramNameForCase(String category, String subType) {
  final normalizedCategory = category.trim().toLowerCase();
  final normalizedSubType = subType.trim().toLowerCase();

  if (normalizedCategory == 'bass') {
    if (normalizedSubType.contains('medical') ||
        normalizedSubType.contains('dialysis') ||
        normalizedSubType.contains('chemotherapy') ||
        normalizedSubType.contains('major operation')) {
      return 'BASS – Medical Assistance';
    }
    if (normalizedSubType.contains('burial')) {
      return 'BASS – Burial Assistance';
    }
    if (normalizedSubType.contains('drug') ||
        normalizedSubType.contains('rehabilitation')) {
      return 'BASS – Drug Rehabilitation';
    }
    if (normalizedSubType.contains('fire')) {
      return 'BASS – Fire Relief';
    }
  }
  if (normalizedCategory == 'education') return 'Education Incentive';
  return null;
}
