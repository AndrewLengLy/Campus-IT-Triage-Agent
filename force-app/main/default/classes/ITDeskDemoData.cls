/**
 * Idempotent sample data for a fresh org: student Contacts plus a realistic spread of campus
 * IT traffic across every routing category, seeded by calling the invocable actions rather
 * than by inserting Cases directly.
 *
 * Going through the actions is deliberate. It means the seeded org shows real routing, real
 * SLA due dates, real published Case Comments, and a real audit trail with a believable
 * deflection rate, instead of records that only look right.
 *
 * Run from the CLI:
 *   sf apex run --file scripts/apex/seedSampleData.apex --target-org campus-it-dev
 */
public with sharing class ITDeskDemoData {
    public static final String STUDENT_ALEX = 'S10000001';
    public static final String STUDENT_JORDAN = 'S10000002';
    public static final String STUDENT_SAM = 'S10000003';
    public static final String STUDENT_PRIYA = 'S10000004';
    public static final String STUDENT_MARCUS = 'S10000005';
    public static final String STUDENT_WEI = 'S10000006';
    public static final String STUDENT_NADIA = 'S10000007';
    public static final String STUDENT_TOM = 'S10000008';

    public static final Set<String> SAMPLE_STUDENT_IDS = new Set<String>{
        STUDENT_ALEX,
        STUDENT_JORDAN,
        STUDENT_SAM,
        STUDENT_PRIYA,
        STUDENT_MARCUS,
        STUDENT_WEI,
        STUDENT_NADIA,
        STUDENT_TOM
    };

    /** What the seed produced, so the CLI script can print something useful. */
    public class SeedResult {
        public Integer students = 0;
        public Integer casesOpened = 0;
        public Integer selfServiceDeflections = 0;
        public Integer auditRows = 0;
        public Boolean alreadySeeded = false;

        public String describe() {
            if (alreadySeeded) {
                return 'Sample data already present: ' +
                    students +
                    ' students, ' +
                    casesOpened +
                    ' open Cases, ' +
                    auditRows +
                    ' audit rows. Nothing to do.';
            }
            return 'Seeded ' +
                students +
                ' students, ' +
                casesOpened +
                ' Cases across the Campus IT queues, ' +
                selfServiceDeflections +
                ' self-service deflections, ' +
                auditRows +
                ' audit rows.';
        }
    }

    /**
     * Creates the sample students and, on a first run, the sample traffic. Safe to run more
     * than once: Contacts upsert on Student ID and the traffic is only seeded when no
     * triage-sourced Case exists yet for the sample students.
     *
     * @return counts of what exists after the run
     */
    public static SeedResult seed() {
        upsertStudents();

        SeedResult result = new SeedResult();
        result.students = SAMPLE_STUDENT_IDS.size();

        if (hasExistingSampleTraffic()) {
            result.alreadySeeded = true;
            result.casesOpened = countSampleCases();
            result.auditRows = countSampleAuditRows();
            return result;
        }

        result.selfServiceDeflections = seedSelfServiceDeflections();
        result.casesOpened = seedEscalations();
        result.auditRows = countSampleAuditRows();
        return result;
    }

    /** The eight sample students, upserted on the Student ID external key. */
    public static List<Contact> upsertStudents() {
        List<Contact> students = new List<Contact>{
            newStudent('Alex', 'Rivera', STUDENT_ALEX),
            newStudent('Jordan', 'Chen', STUDENT_JORDAN),
            newStudent('Sam', 'Patel', STUDENT_SAM),
            newStudent('Priya', 'Nair', STUDENT_PRIYA),
            newStudent('Marcus', 'Bell', STUDENT_MARCUS),
            newStudent('Wei', 'Zhang', STUDENT_WEI),
            newStudent('Nadia', 'Haddad', STUDENT_NADIA),
            newStudent('Tom', 'Okafor', STUDENT_TOM)
        };
        upsert students Contact.Student_ID__c;
        return students;
    }

    /**
     * Two students whose problems the known-issue catalog resolves in full. These produce
     * Matched audit rows and no Case, which is what gives the operations snapshot a
     * non-trivial deflection rate on a fresh org.
     */
    private static Integer seedSelfServiceDeflections() {
        List<ITDeskSelfService.SelfServiceRequest> lookups =
            new List<ITDeskSelfService.SelfServiceRequest>{
                selfService('Campus WiFi keeps dropping in the residence hall.', 'Network', STUDENT_ALEX),
                selfService('I forgot my campus password and I am locked out.', 'Account', STUDENT_PRIYA)
            };

        Integer matched = 0;
        for (ITDeskSelfService.SelfServiceResult lookup : ITDeskSelfService.findGuide(lookups)) {
            if (lookup.isMatch == true) {
                matched++;
            }
        }
        return matched;
    }

    /**
     * Seven escalations covering every Campus IT queue, plus one follow-up comment and two
     * status checks so the audit trail shows more than ticket creation.
     */
    private static Integer seedEscalations() {
        List<ITDeskTicketEscalation.EscalationRequest> requests =
            new List<ITDeskTicketEscalation.EscalationRequest>{
                escalation(
                    STUDENT_JORDAN,
                    'Laptop will not power on and I have an exam tomorrow. I already tried a different charger.',
                    'High',
                    'Laptop',
                    'jordan.chen@campus.edu',
                    'Laptop will not power on'
                ),
                escalation(
                    STUDENT_MARCUS,
                    'My course is missing from the LMS even though I am enrolled for this term.',
                    'Medium',
                    'LMS',
                    'marcus.bell@campus.edu',
                    'A course is missing from the LMS'
                ),
                escalation(
                    STUDENT_WEI,
                    'Print jobs never release at the library station even though I have credit left.',
                    'Low',
                    'Printing',
                    'wei.zhang@campus.edu',
                    'Print job will not release'
                ),
                escalation(
                    STUDENT_NADIA,
                    'I enrolled last week and still have no campus account, so I cannot sign in anywhere.',
                    'High',
                    'Provisioning',
                    'nadia.haddad@campus.edu',
                    'New student account has not been provisioned'
                ),
                escalation(
                    STUDENT_TOM,
                    'The VPN client will not connect from off campus. It times out at the authentication step.',
                    'Medium',
                    'VPN',
                    'tom.okafor@campus.edu',
                    'Install the campus VPN client'
                ),
                escalation(
                    STUDENT_PRIYA,
                    'Outlook has been stuck offline since the weekend and will not send.',
                    'Medium',
                    'Outlook',
                    'priya.nair@campus.edu',
                    'Outlook is stuck offline'
                ),
                escalation(
                    STUDENT_SAM,
                    'I need help moving files off the campus file share before my account closes.',
                    'Low',
                    'Other',
                    'sam.patel@campus.edu',
                    null
                )
            };

        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(requests);

        Integer opened = 0;
        String firstCaseNumber;
        for (ITDeskTicketEscalation.EscalationResult result : created) {
            if (result.isSuccess == true) {
                opened++;
                if (firstCaseNumber == null) {
                    firstCaseNumber = result.caseNumber;
                }
            }
        }

        seedFollowUp(created);
        seedStatusChecks(firstCaseNumber);
        return opened;
    }

    /** One student adds detail to their open ticket, so the Case shows a real comment thread. */
    private static void seedFollowUp(List<ITDeskTicketEscalation.EscalationResult> created) {
        if (created.size() < 3 || created[2].isSuccess != true) {
            return;
        }
        ITDeskTicketUpdate.UpdateRequest followUp = new ITDeskTicketUpdate.UpdateRequest();
        followUp.caseNumber = created[2].caseNumber;
        followUp.studentId = STUDENT_WEI;
        followUp.updateDetails =
            'It also fails at the science building release station. The card reader beeps but nothing prints.';
        ITDeskTicketUpdate.addUpdate(new List<ITDeskTicketUpdate.UpdateRequest>{ followUp });
    }

    /** One hit and one miss, so the audit trail shows both status outcomes. */
    private static void seedStatusChecks(String knownCaseNumber) {
        List<ITDeskTicketStatus.StatusRequest> checks = new List<ITDeskTicketStatus.StatusRequest>();
        if (String.isNotBlank(knownCaseNumber)) {
            ITDeskTicketStatus.StatusRequest found = new ITDeskTicketStatus.StatusRequest();
            found.caseNumber = knownCaseNumber;
            checks.add(found);
        }
        // Alex was fully deflected by the WiFi guide, so this lookup is a genuine miss.
        ITDeskTicketStatus.StatusRequest miss = new ITDeskTicketStatus.StatusRequest();
        miss.studentId = STUDENT_ALEX;
        checks.add(miss);

        ITDeskTicketStatus.checkStatus(checks);
    }

    private static Boolean hasExistingSampleTraffic() {
        return countSampleCases() > 0 || countSampleAuditRows() > 0;
    }

    private static Integer countSampleCases() {
        return [
            SELECT COUNT()
            FROM Case
            WHERE Student_ID__c IN :SAMPLE_STUDENT_IDS AND Agent_Sourced__c = TRUE
        ];
    }

    private static Integer countSampleAuditRows() {
        return [SELECT COUNT() FROM Campus_IT_Interaction__c WHERE Student_ID__c IN :SAMPLE_STUDENT_IDS];
    }

    private static Contact newStudent(String firstName, String lastName, String studentId) {
        return new Contact(
            FirstName = firstName,
            LastName = lastName,
            Email = firstName.toLowerCase() + '.' + lastName.toLowerCase() + '@campus.edu',
            Student_ID__c = studentId
        );
    }

    private static ITDeskSelfService.SelfServiceRequest selfService(
        String issueDescription,
        String category,
        String studentId
    ) {
        ITDeskSelfService.SelfServiceRequest request = new ITDeskSelfService.SelfServiceRequest();
        request.issueDescription = issueDescription;
        request.category = category;
        request.studentId = studentId;
        return request;
    }

    private static ITDeskTicketEscalation.EscalationRequest escalation(
        String studentId,
        String issueDescription,
        String urgency,
        String category,
        String studentEmail,
        String selfServiceArticle
    ) {
        ITDeskTicketEscalation.EscalationRequest request = new ITDeskTicketEscalation.EscalationRequest();
        request.studentId = studentId;
        request.issueDescription = issueDescription;
        request.urgency = urgency;
        request.category = category;
        request.studentEmail = studentEmail;
        request.selfServiceAttempted = String.isNotBlank(selfServiceArticle);
        request.selfServiceArticle = selfServiceArticle;
        return request;
    }
}
