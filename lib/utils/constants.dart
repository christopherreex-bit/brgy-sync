import 'package:flutter/material.dart';

// ─── Brand Colors ───────────────────────────────────────────────
const Color kNavy = Color(0xFF0F2044);
const Color kNavyLight = Color(0xFF1A3260);
const Color kSidebarInactive = Color(0xFFB0BAD0);
const Color kWhite = Colors.white;
const Color kContentBg = Colors.white;

// ─── Roles ──────────────────────────────────────────────────────
const String roleResident = 'resident';
const String roleStaff = 'staff';
const String roleOfficer = 'officer';
const String roleCaptain = 'captain';

// ─── Case Statuses ──────────────────────────────────────────────
const String statusPendingReview = 'pending_review';
const String statusProcessing = 'processing';
const String statusAwaitingDocs = 'awaiting_docs';
const String statusApproved = 'approved';
const String statusReleased = 'released';
const String statusRejected = 'rejected';

// ─── SLA Statuses ───────────────────────────────────────────────
const String slaOnTime = 'on_time';
const String slaNearDeadline = 'near_deadline';
const String slaOverdue = 'overdue';

// ─── Budget Statuses ────────────────────────────────────────────
const String budgetHealthy = 'healthy';
const String budgetLow = 'low';
const String budgetCritical = 'critical';

// ─── Service Categories ─────────────────────────────────────────
const String catBass = 'bass';
const String catDocuments = 'documents';
const String catCommunity = 'community';
const String catBeneficiary = 'beneficiary';
const String catVaw = 'vaw';
const String catEducation = 'education';
const String catAdhoc = 'adhoc';

// ─── Status Badge Colors ────────────────────────────────────────
const Map<String, Color> statusBadgeBg = {
  statusPendingReview: Color(0xFFFFF3CD),
  statusProcessing: Color(0xFFD1ECF1),
  statusAwaitingDocs: Color(0xFFFFE0CC),
  statusApproved: Color(0xFFD4EDDA),
  statusReleased: Color(0xFFD1ECF1),
  statusRejected: Color(0xFFF8D7DA),
  slaOnTime: Color(0xFFD4EDDA),
  slaNearDeadline: Color(0xFFFFE0CC),
  slaOverdue: Color(0xFFF8D7DA),
  'confirmed': Color(0xFFD4EDDA),
  'pending_confirmation': Color(0xFFFFF3CD),
  'docs_verified': Color(0xFFD4EDDA),
  'missing_report_card': Color(0xFFF8D7DA),
  budgetCritical: Color(0xFFF8D7DA),
  budgetLow: Color(0xFFFFE0CC),
  budgetHealthy: Color(0xFFD4EDDA),
  'active': Color(0xFFD4EDDA),
  'inactive': Color(0xFFF8D7DA),
  'captain': Color(0xFFD1ECF1),
  'officer': Color(0xFFD4EDDA),
  'staff': Color(0xFFFFF3CD),
};

const Map<String, Color> statusBadgeText = {
  statusPendingReview: Color(0xFF856404),
  statusProcessing: Color(0xFF0C5460),
  statusAwaitingDocs: Color(0xFF854A00),
  statusApproved: Color(0xFF155724),
  statusReleased: Color(0xFF0C5460),
  statusRejected: Color(0xFF721C24),
  slaOnTime: Color(0xFF155724),
  slaNearDeadline: Color(0xFF854A00),
  slaOverdue: Color(0xFF721C24),
  'confirmed': Color(0xFF155724),
  'pending_confirmation': Color(0xFF856404),
  'docs_verified': Color(0xFF155724),
  'missing_report_card': Color(0xFF721C24),
  budgetCritical: Color(0xFF721C24),
  budgetLow: Color(0xFF854A00),
  budgetHealthy: Color(0xFF155724),
  'active': Color(0xFF155724),
  'inactive': Color(0xFF721C24),
  'captain': Color(0xFF0C5460),
  'officer': Color(0xFF155724),
  'staff': Color(0xFF856404),
};
