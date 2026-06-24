/**
 * BrgySync — Seed Data Script
 *
 * Seeds the Firestore database with realistic demo data for thesis defense.
 * Run: node scripts/seed-data.js
 *
 * Required env var:
 *   FIREBASE_SERVICE_ACCOUNT — stringified Firebase Admin service account JSON
 *
 * This script creates:
 *   - 4 test users (one per role: resident, staff, officer, captain)
 *   - SLA config defaults (4 entries)
 *   - Budget programs (7 programs)
 *   - 25+ sample cases across all 7 categories in various statuses
 *   - Sample distributions (senior citizens, PWD, education)
 *   - Sample resolved cases for analytics
 */

const admin = require('firebase-admin');

const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

// ─── Helpers ──────────────────────────────────────────────────────
function ts(dateStr) {
  return admin.firestore.Timestamp.fromDate(new Date(dateStr));
}

function randomId() {
  return db.collection('_').doc().id; // generates a random Firestore ID
}

// ─── Test Users ───────────────────────────────────────────────────
const TEST_USERS = [
  {
    uid: 'test-resident-001',
    name: 'Ana Garcia',
    email: 'resident@brgysync.demo',
    mobile: '09171234567',
    role: 'resident',
    password: 'Password123!',
  },
  {
    uid: 'test-staff-001',
    name: 'Pedro Reyes',
    email: 'staff@brgysync.demo',
    mobile: '09182345678',
    role: 'staff',
    password: 'Password123!',
  },
  {
    uid: 'test-officer-001',
    name: 'Maria Santos',
    email: 'officer@brgysync.demo',
    mobile: '09193456789',
    role: 'officer',
    password: 'Password123!',
  },
  {
    uid: 'test-captain-001',
    name: 'Juan Dela Cruz',
    email: 'captain@brgysync.demo',
    mobile: '09204567890',
    role: 'captain',
    password: 'Password123!',
  },
];

// ─── SLA Config ───────────────────────────────────────────────────
const SLA_CONFIG = [
  { category: 'documents',     deadlineValue: 15, deadlineUnit: 'minutes' },
  { category: 'bass_standard', deadlineValue: 3,  deadlineUnit: 'working_days' },
  { category: 'bass_medical',  deadlineValue: 5,  deadlineUnit: 'working_days' },
  { category: 'vaw',           deadlineValue: 1,  deadlineUnit: 'working_days' },
];

// ─── Budget Programs ──────────────────────────────────────────────
const BUDGET_PROGRAMS = [
  { name: 'BASS – Medical Assistance',     allocated: 500000, utilized: 120000, thresholdPercent: 10 },
  { name: 'BASS – Burial Assistance',      allocated: 150000, utilized: 45000,  thresholdPercent: 10 },
  { name: 'BASS – Drug Rehabilitation',    allocated: 100000, utilized: 20000,  thresholdPercent: 10 },
  { name: 'BASS – Fire Relief',            allocated: 80000,  utilized: 75000,  thresholdPercent: 10 },
  { name: 'Senior Citizen Birthday Assist', allocated: 200000, utilized: 80000,  thresholdPercent: 10 },
  { name: 'PWD Birthday Assistance',        allocated: 120000, utilized: 30000,  thresholdPercent: 10 },
  { name: 'Education Incentive',           allocated: 300000, utilized: 95000,  thresholdPercent: 10 },
];

// ─── Sample Data Arrays ───────────────────────────────────────────
const FIRST_NAMES = ['Ana', 'Juan', 'Maria', 'Pedro', 'Rosa', 'Carlos', 'Elena', 'Miguel', 'Sofia', 'Rafael', 'Isabella', 'Gabriel', 'Lucia', 'Antonio', 'Carmen', 'Fernando', 'Teresa', 'Roberto', 'Beatriz', 'Eduardo'];
const LAST_NAMES = ['Garcia', 'Reyes', 'Santos', 'Cruz', 'Torres', 'Ramos', 'Mendoza', 'Villanueva', 'Fernando', 'Aquino', 'Dela Cruz', 'Bautista', 'Pascual', 'Castillo', 'Rivera'];
const ADDRESSES = ['Blk 1 Lot 5, Phase 2, Brgy. Calzada-Tipas, Taguig City', '143 Mabini St., Calzada-Tipas, Taguig', '27 Sampaguita Ave., Calzada-Tipas, Taguig', '88 Riverside Dr., Calzada-Tipas, Taguig', '5 Kalayaan St., Calzada-Tipas, Taguig', '62 Maligaya Rd., Calzada-Tipas, Taguig', '19 Gitna St., Calzada-Tipas, Taguig', '45 Bayanihan Ave., Calzada-Tipas, Taguig', '3 Pag-asa St., Calzada-Tipas, Taguig', '71 Bagong Silang, Calzada-Tipas, Taguig'];

function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }
function pad(n) { return String(n).padStart(5, '0'); }

function makeName() { return `${pick(FIRST_NAMES)} ${pick(LAST_NAMES)}`; }
function makeMobile() { return '09' + String(Math.floor(100000000 + Math.random() * 900000000)); }
function makeAddress() { return pick(ADDRESSES); }

// ─── Case Definitions ─────────────────────────────────────────────
const CASE_TEMPLATES = [
  // Barangay Documents
  { category: 'documents', subType: 'Barangay Clearance',        status: 'pending_review', count: 3 },
  { category: 'documents', subType: 'Indigency Certificate',      status: 'processing',     count: 2 },
  { category: 'documents', subType: 'Barangay ID',                status: 'approved',       count: 2 },
  { category: 'documents', subType: 'Barangay Clearance',         status: 'released',       count: 2 },
  // BASS
  { category: 'bass',      subType: 'Medical – Dialysis',        status: 'processing',     count: 2 },
  { category: 'bass',      subType: 'Medical – Chemotherapy',    status: 'approved',       count: 1 },
  { category: 'bass',      subType: 'Burial Assistance',         status: 'released',       count: 2, amount: 15000 },
  { category: 'bass',      subType: 'Drug Rehabilitation',       status: 'pending_review', count: 1 },
  { category: 'bass',      subType: 'Fire Relief',               status: 'released',       count: 1, amount: 25000 },
  // Community Services
  { category: 'community', subType: 'Infrastructure Concern',    status: 'processing',     count: 2 },
  { category: 'community', subType: 'Equipment Loan',            status: 'approved',       count: 1 },
  // Beneficiary
  { category: 'beneficiary', subType: 'Senior Citizen Birthday Program', status: 'pending_review', count: 2 },
  { category: 'beneficiary', subType: 'PWD Birthday Program',           status: 'processing',     count: 1 },
  // VAW/BCPC
  { category: 'vaw',       subType: 'VAW Desk Report',           status: 'processing',     count: 1, confidential: true },
  { category: 'vaw',       subType: 'BCPC Child Protection Case', status: 'approved',      count: 1, confidential: true },
  // Education
  { category: 'education', subType: 'Honor Student Application',  status: 'approved',       count: 2 },
  { category: 'education', subType: 'Honor Student Application',  status: 'released',       count: 1 },
  // Ad Hoc
  { category: 'adhoc',     subType: 'One-Time Distribution',     status: 'pending_review', count: 1 },
  { category: 'adhoc',     subType: 'Special Assistance Program', status: 'rejected',      count: 1 },
];

// ─── Distribution Definitions ─────────────────────────────────────
const SENIOR_NAMES = ['Lola Celia Mendoza', 'Lolo Andres Bautista', 'Lola Trinidad Pascual', 'Lolo Ernesto Castillo', 'Lola Rosario Rivera', 'Lolo Simeon Villanueva'];
const PWD_NAMES = ['Rodel Torres', 'Maricel Ramos', 'Jun Santos', 'Nena Cruz'];
const EDUCATION_NAMES = ['Kyle Mendoza', 'Angel Reyes', 'Joshua Santos', 'Princess Cruz'];

// ─── Known Seed Mobile Numbers ───────────────────────────────────
// These are the numbers generated by makeMobile() in this script and
// the test user numbers. Used by the app to route SMS to fallback.
const SEED_MOBILES = new Set();
TEST_USERS.forEach(u => SEED_MOBILES.add(u.mobile));

// ─── Main Seed Function ───────────────────────────────────────────
async function main() {
  console.log('='.repeat(60));
  console.log('BrgySync — Seed Data Script');
  console.log('='.repeat(60));

  // 0. Clean up existing seed data only (preserve real user documents)
  console.log('\n[0/7] Cleaning up existing seed data...');
  const collections = ['cases', 'slaConfig', 'budgetPrograms', 'budgetTransactions', 'distributions', 'reports', 'complianceSnapshots'];
  for (const col of collections) {
    const snapshot = await db.collection(col).where('isSeedData', '==', true).get();
    if (snapshot.empty) continue;
    const batch = db.batch();
    snapshot.docs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
    console.log(`  ✓ Cleared ${snapshot.size} seed documents from ${col}`);
  }
  // Only delete seed user documents (preserve real app-registered users)
  const seedUsers = await db.collection('users').where('isSeedData', '==', true).get();
  if (!seedUsers.empty) {
    const batch = db.batch();
    seedUsers.docs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
    console.log(`  ✓ Cleared ${seedUsers.size} seed users`);
  }

  // 1. Create test users in Firestore
  // Look up real Auth UIDs by email (seed-admin.js creates real Auth users).
  // If no real Auth user exists, use the hardcoded test UID.
  console.log('\n[1/7] Creating test user documents...');
  const auth = admin.auth();
  // Known real Auth emails (created by seed-admin.js / check-captain.js)
  const REAL_AUTH_EMAILS = ['captain@barangay.test'];
  for (const user of TEST_USERS) {
    const { password, ...userData } = user;
    let uid = user.uid;
    // Try the seed email first, then check known real Auth emails for this role
    const emailsToTry = [user.email, ...REAL_AUTH_EMAILS.filter(e => !userData.email.includes(e.split('@')[0]) || true)];
    for (const email of emailsToTry) {
      try {
        const authUser = await auth.getUserByEmail(email);
        uid = authUser.uid;
        console.log(`  ✓ Found real Auth user for ${email} (uid: ${uid})`);
        break;
      } catch (_) {}
    }
    if (uid === user.uid) {
      console.log(`  ⚠ No Auth user for ${user.email} — using test UID ${uid}`);
    }
    const existing = await db.collection('users').doc(uid).get();
    if (existing.exists) {
      if (!existing.data().isSeedData) {
        await db.collection('users').doc(uid).set({ isSeedData: true }, { merge: true });
        console.log(`  ✓ ${user.role}: ${user.name} — updated with isSeedData flag`);
      } else {
        console.log(`  ✓ ${user.role}: ${user.name} — already seeded`);
      }
    } else {
      await db.collection('users').doc(uid).set({
        ...userData,
        isSeedData: true,
        createdAt: ts('2026-01-15'),
      });
      console.log(`  ✓ ${user.role}: ${user.name} (${user.email} / ${password}) — created`);
    }
  }

  // 2. Seed SLA config
  console.log('\n[2/7] Seeding SLA config...');
  for (const sla of SLA_CONFIG) {
    const docRef = db.collection('slaConfig').doc();
    await docRef.set({
      ...sla,
      lastUpdatedBy: 'test-captain-001',
      lastUpdatedAt: ts('2026-01-01'),
    });
    console.log(`  ✓ ${sla.category}: ${sla.deadlineValue} ${sla.deadlineUnit}`);
  }

  // 3. Seed budget programs
  console.log('\n[3/7] Seeding budget programs...');
  const budgetProgramIds = [];
  for (const bp of BUDGET_PROGRAMS) {
    const docRef = db.collection('budgetPrograms').doc();
    const remaining = bp.allocated - bp.utilized;
    const thresholdAmount = bp.allocated * (bp.thresholdPercent / 100);
    let status = 'healthy';
    if (remaining <= bp.allocated * 0.10) status = 'critical';
    else if (remaining <= thresholdAmount) status = 'low';

    await docRef.set({
      name: bp.name,
      fiscalPeriod: 'FY 2026 Q2 (Apr–Jun)',
      allocated: bp.allocated,
      utilized: bp.utilized,
      remaining,
      thresholdPercent: bp.thresholdPercent,
      thresholdAmount,
      status,
      lastUpdated: ts('2026-06-01'),
      isSeedData: true,
    });
    budgetProgramIds.push(docRef.id);
    console.log(`  ✓ ${bp.name}: ₱${bp.allocated.toLocaleString()} (${status})`);
  }

  // 4. Seed cases
  console.log('\n[4/7] Seeding cases...');
  let caseCounter = 1;
  const now = new Date();

  for (const template of CASE_TEMPLATES) {
    for (let i = 0; i < template.count; i++) {
      const caseId = randomId();
      const refNumber = `BRGY-2026-${pad(caseCounter)}`;
      const isConfidential = template.confidential || template.category === 'vaw';
      const residentName = isConfidential ? 'Confidential' : makeName();
      const residentMobile = makeMobile();

      // Stagger submission dates over the past 30 days
      const daysAgo = Math.floor(Math.random() * 30);
      const submittedDate = new Date(now.getTime() - daysAgo * 24 * 60 * 60 * 1000);

      // Compute SLA deadline
      let slaDeadline;
      const slaKey = template.category === 'bass'
        ? (['Medical – Dialysis', 'Medical – Chemotherapy', 'Medical – Major Operations'].includes(template.subType) ? 'bass_medical' : 'bass_standard')
        : template.category;
      const slaMins = { documents: 15, bass_standard: 3 * 24 * 60, bass_medical: 5 * 24 * 60, vaw: 1 * 24 * 60, community: 3 * 24 * 60, beneficiary: 3 * 24 * 60, education: 5 * 24 * 60, adhoc: 5 * 24 * 60 };
      const mins = slaMins[slaKey] || 15;
      slaDeadline = new Date(submittedDate.getTime() + mins * 60 * 1000);

      // Determine SLA status
      const diffMs = slaDeadline.getTime() - now.getTime();
      let slaStatus = 'on_time';
      if (diffMs < 0) slaStatus = 'overdue';
      else if (diffMs < 24 * 60 * 60 * 1000) slaStatus = 'near_deadline';

      // Last updated
      const lastUpdated = ['processing', 'approved', 'released', 'rejected'].includes(template.status)
        ? new Date(submittedDate.getTime() + Math.random() * 48 * 60 * 60 * 1000)
        : null;

      const caseData = {
        referenceNumber: refNumber,
        residentId: 'test-resident-001',
        residentName,
        residentMobile,
        residentAddress: makeAddress(),
        serviceCategory: template.category,
        serviceSubType: template.subType,
        status: template.status,
        submissionChannel: Math.random() > 0.3 ? 'portal' : 'walkin',
        submissionTimestamp: ts(submittedDate.toISOString()),
        lastUpdated: lastUpdated ? ts(lastUpdated.toISOString()) : null,
        slaDeadline: ts(slaDeadline.toISOString()),
        slaStatus,
        isConfidential,
        isSeedData: true,
        documents: [
          { name: 'Valid ID', required: true, status: Math.random() > 0.2 ? 'uploaded' : 'missing', storageRef: '' },
          { name: 'Barangay Certificate', required: true, status: Math.random() > 0.3 ? 'uploaded' : 'missing', storageRef: '' },
        ],
      };

      if (template.amount) {
        caseData.assistanceAmount = template.amount;
        caseData.budgetProgramId = budgetProgramIds[Math.floor(Math.random() * Math.min(4, budgetProgramIds.length))];
      }

      await db.collection('cases').doc(caseId).set(caseData);

      // Add action log entries for non-pending cases
      if (template.status !== 'pending_review') {
        await db.collection('cases').doc(caseId).collection('actionLog').add({
          timestamp: ts(submittedDate.toISOString()),
          staffId: 'test-staff-001',
          staffName: 'Pedro Reyes',
          action: 'Case received and under review',
          previousStatus: '',
          newStatus: 'pending_review',
          notes: 'Initial submission received',
          smsSent: true,
          smsBody: `Good day! Your case ${refNumber} has been received. We will notify you of updates. — BrgySync`,
        });
      }

      if (['processing', 'approved', 'released', 'rejected'].includes(template.status)) {
        const procDate = new Date(submittedDate.getTime() + 2 * 60 * 60 * 1000);
        await db.collection('cases').doc(caseId).collection('actionLog').add({
          timestamp: ts(procDate.toISOString()),
          staffId: 'test-staff-001',
          staffName: 'Pedro Reyes',
          action: 'Case is now being processed',
          previousStatus: 'pending_review',
          newStatus: 'processing',
          notes: 'Documents reviewed, case accepted for processing',
          smsSent: true,
          smsBody: `Your case ${refNumber} is now being processed. — BrgySync`,
        });
      }

      if (['approved', 'released'].includes(template.status)) {
        const apprDate = new Date(submittedDate.getTime() + 24 * 60 * 60 * 1000);
        await db.collection('cases').doc(caseId).collection('actionLog').add({
          timestamp: ts(apprDate.toISOString()),
          staffId: 'test-captain-001',
          staffName: 'Juan Dela Cruz',
          action: 'Case approved',
          previousStatus: 'processing',
          newStatus: 'approved',
          notes: 'Approved by Barangay Captain',
          smsSent: true,
          smsBody: `Your case ${refNumber} has been approved. — BrgySync`,
        });
      }

      if (template.status === 'released') {
        const relDate = new Date(submittedDate.getTime() + 48 * 60 * 60 * 1000);
        await db.collection('cases').doc(caseId).collection('actionLog').add({
          timestamp: ts(relDate.toISOString()),
          staffId: 'test-captain-001',
          staffName: 'Juan Dela Cruz',
          action: 'Case released/resolved',
          previousStatus: 'approved',
          newStatus: 'released',
          notes: template.amount ? `Released with ₱${template.amount.toLocaleString()} assistance` : 'Case resolved and released',
          smsSent: true,
          smsBody: `Your case ${refNumber} has been resolved/released. Please proceed to the barangay hall to claim. — BrgySync`,
        });

        // Create budget transaction for released cases with amounts
        if (template.amount) {
          await db.collection('budgetTransactions').add({
            programId: caseData.budgetProgramId || budgetProgramIds[0],
            caseId,
            amount: template.amount,
            type: 'deduction',
            approvedBy: 'test-captain-001',
            timestamp: ts(relDate.toISOString()),
            isSeedData: true,
          });
        }
      }

      if (template.status === 'rejected') {
        const rejDate = new Date(submittedDate.getTime() + 12 * 60 * 60 * 1000);
        await db.collection('cases').doc(caseId).collection('actionLog').add({
          timestamp: ts(rejDate.toISOString()),
          staffId: 'test-captain-001',
          staffName: 'Juan Dela Cruz',
          action: 'Case rejected',
          previousStatus: 'processing',
          newStatus: 'rejected',
          notes: 'Does not meet eligibility requirements. Resident advised to visit barangay hall.',
          smsSent: true,
          smsBody: `Your case ${refNumber} has been reviewed and could not be approved. Please visit the barangay hall for details. — BrgySync`,
        });
      }

      console.log(`  ✓ ${refNumber} — ${template.subType} (${template.status})`);
      caseCounter++;
    }
  }

  // 5. Seed distributions
  console.log('\n[5/7] Seeding distributions...');

  // Senior citizens
  for (let i = 0; i < SENIOR_NAMES.length; i++) {
    const bMonth = Math.floor(Math.random() * 12) + 1;
    const bDay = Math.floor(Math.random() * 28) + 1;
    const age = 60 + Math.floor(Math.random() * 25);
    const schedMonth = Math.floor(Math.random() * 3) + 7; // Jul–Sep
    await db.collection('distributions').add({
      programType: 'senior_birthday',
      beneficiaryName: SENIOR_NAMES[i],
      birthdate: ts(`19${String(2026 - age).slice(-2)}-${String(bMonth).padStart(2, '0')}-${String(bDay).padStart(2, '0')}`),
      age,
      registrationYear: 2024 + Math.floor(Math.random() * 3),
      status: i < 4 ? 'confirmed' : 'pending',
      scheduledDate: ts(`2026-${String(schedMonth).padStart(2, '0')}-${String(bDay).padStart(2, '0')}`),
      releaseDate: null,
      budgetProgramId: budgetProgramIds[4], // Senior Citizen program
      isSeedData: true,
    });
    console.log(`  ✓ Senior: ${SENIOR_NAMES[i]} (age ${age})`);
  }

  // PWD
  for (let i = 0; i < PWD_NAMES.length; i++) {
    const bMonth = Math.floor(Math.random() * 12) + 1;
    const bDay = Math.floor(Math.random() * 28) + 1;
    const age = 25 + Math.floor(Math.random() * 30);
    const schedMonth = Math.floor(Math.random() * 3) + 7;
    await db.collection('distributions').add({
      programType: 'pwd_birthday',
      beneficiaryName: PWD_NAMES[i],
      birthdate: ts(`19${String(2026 - age).slice(-2)}-${String(bMonth).padStart(2, '0')}-${String(bDay).padStart(2, '0')}`),
      age,
      registrationYear: 2024 + Math.floor(Math.random() * 3),
      status: i < 3 ? 'confirmed' : 'pending',
      scheduledDate: ts(`2026-${String(schedMonth).padStart(2, '0')}-${String(bDay).padStart(2, '0')}`),
      releaseDate: null,
      budgetProgramId: budgetProgramIds[5], // PWD program
      isSeedData: true,
    });
    console.log(`  ✓ PWD: ${PWD_NAMES[i]} (age ${age})`);
  }

  // Education
  for (let i = 0; i < EDUCATION_NAMES.length; i++) {
    const grade = ['Grade 6', 'Grade 10', 'Grade 11', 'Grade 12'][i];
    const honor = ['With Highest Honors', 'With High Honors', 'With Honors', 'With High Honors'][i];
    await db.collection('distributions').add({
      programType: 'education_incentive',
      beneficiaryName: EDUCATION_NAMES[i],
      birthdate: ts(`200${i + 4}-0${i + 3}-15`),
      age: 16 + i,
      registrationYear: 2025,
      gradeLevel: grade,
      honorLevel: honor,
      school: ['Calzada Elementary', 'Tipas National High School', 'Taguig Science High School', 'UP Integrated School'][i],
      status: i < 2 ? 'docs_verified' : 'missing_report_card',
      scheduledDate: ts('2026-08-01'),
      releaseDate: null,
      budgetProgramId: budgetProgramIds[6], // Education program
      isSeedData: true,
    });
    console.log(`  ✓ Education: ${EDUCATION_NAMES[i]} (${grade}, ${honor})`);
  }

  // 6. Seed a sample report
  console.log('\n[6/7] Seeding sample report...');
  await db.collection('reports').add({
    type: 'dswd_summary',
    period: 'Q2 2026',
    periodFrom: ts('2026-04-01'),
    periodTo: ts('2026-06-30'),
    generatedAt: ts('2026-06-15'),
    generatedBy: 'test-captain-001',
    fileUrl: '',
    format: 'pdf',
    isSeedData: true,
  });
  console.log('  ✓ DSWD Social Services Summary (Q2 2026)');

  // 7. Seed a compliance snapshot
  console.log('\n[7/7] Seeding compliance snapshot...');
  await db.collection('complianceSnapshots').add({
    period: '2026-05',
    generatedAt: ts('2026-06-01'),
    isSeedData: true,
    byCategory: [
      { category: 'BASS Assistance', totalReceived: 8, completedOnTime: 5, overdueCount: 1, avgProcessingTime: 72, complianceRate: 63 },
      { category: 'Barangay Documents', totalReceived: 12, completedOnTime: 11, overdueCount: 0, avgProcessingTime: 1, complianceRate: 92 },
      { category: 'Community Services', totalReceived: 4, completedOnTime: 3, overdueCount: 1, avgProcessingTime: 48, complianceRate: 75 },
      { category: 'Beneficiary Registration', totalReceived: 3, completedOnTime: 2, overdueCount: 0, avgProcessingTime: 24, complianceRate: 67 },
      { category: 'VAW / BCPC', totalReceived: 2, completedOnTime: 2, overdueCount: 0, avgProcessingTime: 12, complianceRate: 100 },
      { category: 'Education Incentive', totalReceived: 3, completedOnTime: 2, overdueCount: 0, avgProcessingTime: 96, complianceRate: 67 },
      { category: 'Ad Hoc / Special Program', totalReceived: 2, completedOnTime: 1, overdueCount: 1, avgProcessingTime: 120, complianceRate: 50 },
    ],
  });
  console.log('  ✓ Compliance snapshot for 2026-05');

  // ─── Summary ─────────────────────────────────────────────────────
  console.log('\n' + '='.repeat(60));
  console.log('SEED COMPLETE');
  console.log('='.repeat(60));
  console.log('\nTest Accounts:');
  TEST_USERS.forEach(u => {
    console.log(`  ${u.role.padEnd(10)} ${u.email} / ${u.password}`);
  });
  console.log('\nData seeded:');
  console.log(`  • ${TEST_USERS.length} test users`);
  console.log(`  • ${SLA_CONFIG.length} SLA config entries`);
  console.log(`  • ${BUDGET_PROGRAMS.length} budget programs`);
  console.log(`  • ${caseCounter - 1} cases across all categories`);
  console.log(`  • ${SENIOR_NAMES.length + PWD_NAMES.length + EDUCATION_NAMES.length} distribution records`);
  console.log(`  • 1 sample report`);
  console.log(`  • 1 compliance snapshot`);
  console.log('\nNext: Run the app and log in as any test user to explore the demo.');
}

main().catch(err => {
  console.error('Seed failed:', err);
  process.exit(1);
});
