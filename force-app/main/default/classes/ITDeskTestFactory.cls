/**
 * Shared builders for the Campus IT Apex tests.
 *
 * Two routing modes are available and every test must pick one explicitly:
 *
 * - useTestRouting()      isolated CIT_Test_* queues, so a test never depends on the
 *                         packaged Campus_IT_* queues or on the shipped Custom Metadata.
 * - useDeployedRouting()  the real IT_Category_Queue_Map__mdt rows and Campus_IT_* queues,
 *                         used by ITDeskQueueRoutingTest to prove the shipped configuration
 *                         actually routes. Queues and Custom Metadata are setup/metadata
 *                         objects, so tests can read them without SeeAllData.
 *
 * Test classes never rely on org transaction data: Contacts and Cases are created here.
 */
@IsTest
public class ITDeskTestFactory {
    public static final String QUEUE_NETWORK = 'CIT_Test_Network';
    public static final String QUEUE_HARDWARE = 'CIT_Test_Hardware';
    public static final String QUEUE_SOFTWARE = 'CIT_Test_Software';
    public static final String QUEUE_IDENTITY = 'CIT_Test_Identity';
    public static final String QUEUE_GENERAL = 'CIT_Test_General';

    /** A queue that exists but is not enabled for the Case object, so owner assignment fails. */
    public static final String QUEUE_NOT_ENABLED_FOR_CASE = 'CIT_Test_Unsupported';

    /** A DeveloperName no queue uses, standing in for a rule that points at a removed queue. */
    public static final String QUEUE_MISSING = 'CIT_Test_Does_Not_Exist';

    /** The five queues the shipped Custom Metadata routes to. */
    public static final List<String> DEPLOYED_QUEUES = new List<String>{
        'Campus_IT_Network',
        'Campus_IT_Hardware',
        'Campus_IT_Software',
        'Campus_IT_Identity',
        'Campus_IT_General'
    };

    /**
     * Creates the isolated CIT_Test_* queues. Call from @TestSetup inside System.runAs so the
     * setup-object DML does not collide with record DML in the same transaction.
     */
    public static void createTestQueues() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            ensureQueue(QUEUE_NETWORK, 'CIT Test Network', true);
            ensureQueue(QUEUE_HARDWARE, 'CIT Test Hardware', true);
            ensureQueue(QUEUE_SOFTWARE, 'CIT Test Software', true);
            ensureQueue(QUEUE_IDENTITY, 'CIT Test Identity', true);
            ensureQueue(QUEUE_GENERAL, 'CIT Test General', true);
            ensureQueue(QUEUE_NOT_ENABLED_FOR_CASE, 'CIT Test Unsupported', false);
        }
    }

    /**
     * Points the routing service at in-memory Custom Metadata rows that resolve to the
     * CIT_Test_* queues. This exercises the same code path production uses.
     */
    public static void useTestRouting() {
        ITDeskRoutingService.useCustomMetadataRouting = true;
        ITDeskRoutingService.defaultQueueDeveloperName = QUEUE_GENERAL;
        ITDeskRoutingService.metadataOverrides = testRoutingRules();
    }

    /** Uses the real IT_Category_Queue_Map__mdt rows and the packaged Campus_IT_* queues. */
    public static void useDeployedRouting() {
        ITDeskRoutingService.useCustomMetadataRouting = true;
        ITDeskRoutingService.metadataOverrides = null;
    }

    /**
     * The in-memory stand-in for the shipped routing rules: one rule per queue, keyword plus
     * aliases, and one default row with no keyword.
     */
    public static List<IT_Category_Queue_Map__mdt> testRoutingRules() {
        return new List<IT_Category_Queue_Map__mdt>{
            newRoutingRule('network', 'wifi,vpn,wireless', QUEUE_NETWORK, false),
            newRoutingRule('hardware', 'laptop,printer,printing', QUEUE_HARDWARE, false),
            newRoutingRule('software', 'application,license,email,outlook,lms', QUEUE_SOFTWARE, false),
            newRoutingRule('account', 'password,login,identity,mfa,provisioning', QUEUE_IDENTITY, false),
            newRoutingRule(null, null, QUEUE_GENERAL, true)
        };
    }

    public static IT_Category_Queue_Map__mdt newRoutingRule(
        String keyword,
        String aliases,
        String queueDeveloperName,
        Boolean isDefault
    ) {
        return new IT_Category_Queue_Map__mdt(
            Keyword__c = keyword,
            Aliases__c = aliases,
            Queue_Developer_Name__c = queueDeveloperName,
            Is_Default__c = isDefault
        );
    }

    public static IT_Known_Issue__mdt newKnownIssue(
        String title,
        String keywords,
        String category,
        Boolean requiresEscalation,
        Boolean isActive
    ) {
        return new IT_Known_Issue__mdt(
            Title__c = title,
            Keywords__c = keywords,
            Category__c = category,
            Resolution_Steps__c = '1. Try the documented fix for ' + title + '.',
            Requires_Escalation__c = requiresEscalation,
            Is_Active__c = isActive
        );
    }

    /** The known-issue catalog the self-service tests match against. */
    public static List<IT_Known_Issue__mdt> knownIssueCatalog() {
        return new List<IT_Known_Issue__mdt>{
            newKnownIssue('Reconnect to campus WiFi', 'wifi,wireless,eduroam', 'Network', false, true),
            newKnownIssue('Reset your campus password', 'password,reset,forgot', 'Account', false, true),
            newKnownIssue('Install the campus VPN client', 'vpn,remote', 'Network', false, true),
            newKnownIssue('Outlook is stuck offline', 'outlook,email,offline', 'Software', false, true),
            newKnownIssue('Laptop will not power on', 'laptop,no power,dead', 'Hardware', true, true),
            newKnownIssue('Retired article', 'retired', 'General', false, false)
        };
    }

    public static Id queueId(String developerName) {
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :developerName
            LIMIT 1
        ];
        return queues.isEmpty() ? null : queues[0].Id;
    }

    public static ITDeskTicketEscalation.EscalationRequest escalation(
        String studentId,
        String issueDescription,
        String urgency,
        String category
    ) {
        ITDeskTicketEscalation.EscalationRequest request = new ITDeskTicketEscalation.EscalationRequest();
        request.studentId = studentId;
        request.issueDescription = issueDescription;
        request.urgency = urgency;
        request.category = category;
        return request;
    }

    public static ITDeskTicketStatus.StatusRequest status(String caseNumber, String studentId) {
        ITDeskTicketStatus.StatusRequest request = new ITDeskTicketStatus.StatusRequest();
        request.caseNumber = caseNumber;
        request.studentId = studentId;
        return request;
    }

    public static ITDeskTicketUpdate.UpdateRequest ticketUpdate(
        String caseNumber,
        String studentId,
        String updateDetails
    ) {
        ITDeskTicketUpdate.UpdateRequest request = new ITDeskTicketUpdate.UpdateRequest();
        request.caseNumber = caseNumber;
        request.studentId = studentId;
        request.updateDetails = updateDetails;
        return request;
    }

    public static ITDeskSelfService.SelfServiceRequest selfService(
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

    public static ITDeskOperationsSnapshot.SnapshotRequest snapshot(String queueName) {
        ITDeskOperationsSnapshot.SnapshotRequest request = new ITDeskOperationsSnapshot.SnapshotRequest();
        request.queueName = queueName;
        return request;
    }

    /** Deterministic student ID for bulk fixtures: index 0 becomes S90000000. */
    public static String bulkStudentId(Integer index) {
        return 'S' + String.valueOf(90000000 + index);
    }

    public static List<Contact> insertStudents(Integer count) {
        List<Contact> students = new List<Contact>();
        for (Integer i = 0; i < count; i++) {
            students.add(
                new Contact(
                    FirstName = 'Bulk',
                    LastName = 'Student ' + i,
                    Student_ID__c = bulkStudentId(i)
                )
            );
        }
        insert students;
        return students;
    }

    /**
     * Inserts open agent-sourced Cases directly, bypassing the invocable actions so bulk
     * lookup tests start from a known fixture rather than from escalation side effects.
     * The returned list is ordered by seeded student ID, so index i belongs to bulkStudentId(i).
     */
    public static List<Case> insertOpenCases(Integer count, String category, Id ownerId) {
        List<Case> tickets = new List<Case>();
        for (Integer i = 0; i < count; i++) {
            Case ticket = new Case(
                Subject = 'Campus IT: ' + category + ' — seeded fixture ' + i,
                Description = 'Seeded by ITDeskTestFactory.',
                Origin = 'Web',
                Status = 'New',
                Priority = 'Medium',
                Student_ID__c = bulkStudentId(i),
                IT_Category__c = category,
                Agent_Sourced__c = true
            );
            if (ownerId != null) {
                ticket.OwnerId = ownerId;
            }
            tickets.add(ticket);
        }
        insert tickets;
        return [
            SELECT Id, CaseNumber, Student_ID__c, OwnerId, IsClosed
            FROM Case
            WHERE Id IN :tickets
            ORDER BY Student_ID__c ASC
        ];
    }

    /** MasterLabel of a closed Case status, so tests do not hardcode 'Closed'. */
    public static String closedCaseStatus() {
        List<CaseStatus> closed = [SELECT MasterLabel FROM CaseStatus WHERE IsClosed = TRUE LIMIT 1];
        Assert.isFalse(closed.isEmpty(), 'The org must define at least one closed Case status.');
        return closed[0].MasterLabel;
    }

    public static List<Campus_IT_Interaction__c> interactions(Integer count) {
        List<Campus_IT_Interaction__c> rows = new List<Campus_IT_Interaction__c>();
        for (Integer i = 0; i < count; i++) {
            rows.add(
                ITDeskAuditService.newInteraction(
                    ITDeskAuditService.ACTION_STATUS,
                    ITDeskAuditService.OUTCOME_FOUND,
                    true,
                    bulkStudentId(i),
                    null,
                    null,
                    'Network',
                    null,
                    'Seeded audit row ' + i
                )
            );
        }
        return rows;
    }

    /**
     * Idempotent queue creation. Re-entrant so leftover queues from an interrupted run do
     * not fail @TestSetup.
     *
     * @param supportsCase when false the queue is created without a Case QueueSobject, which
     *                     makes Case owner assignment to it fail at DML time.
     */
    private static void ensureQueue(String developerName, String name, Boolean supportsCase) {
        List<Group> existing = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :developerName
            LIMIT 1
        ];
        Group queue;
        if (existing.isEmpty()) {
            queue = new Group(Name = name, DeveloperName = developerName, Type = 'Queue');
            insert queue;
        } else {
            queue = existing[0];
        }
        if (!supportsCase) {
            return;
        }

        List<QueueSobject> supported = [
            SELECT Id
            FROM QueueSobject
            WHERE QueueId = :queue.Id AND SobjectType = 'Case'
            LIMIT 1
        ];
        if (supported.isEmpty()) {
            insert new QueueSobject(QueueId = queue.Id, SobjectType = 'Case');
        }
    }
}
