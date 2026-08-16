@IsTest
private class ITDeskTicketUpdateTest {
    private static final String TEST_QUEUE_NETWORK = 'CIT_Test_Network';
    private static final String TEST_QUEUE_GENERAL = 'CIT_Test_General';

    @TestSetup
    static void setupTestQueues() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            ensureQueue(TEST_QUEUE_NETWORK, 'CIT Test Network');
            ensureQueue(TEST_QUEUE_GENERAL, 'CIT Test General');
        }
    }

    @IsTest
    static void addUpdate_byCaseNumberAndStudentId() {
        useTestQueueMap();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{ newEscalation('S92000001') }
        );

        ITDeskTicketUpdate.UpdateRequest byNumber = new ITDeskTicketUpdate.UpdateRequest();
        byNumber.caseNumber = created[0].caseNumber;
        byNumber.studentId = 'S92000001';
        byNumber.updateDetails = 'The outage is in Residence Hall B, room 214.';

        ITDeskTicketUpdate.UpdateRequest byStudent = new ITDeskTicketUpdate.UpdateRequest();
        byStudent.studentId = 'S92000001';
        byStudent.updateDetails = 'Error text: DNS_PROBE_FINISHED_NXDOMAIN';

        Test.startTest();
        List<ITDeskTicketUpdate.UpdateResult> results = ITDeskTicketUpdate.addUpdate(
            new List<ITDeskTicketUpdate.UpdateRequest>{ byNumber, byStudent }
        );
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess);
        Assert.areEqual(created[0].caseId, results[0].caseId);
        Assert.isTrue(results[1].isSuccess);
        Assert.areEqual(
            3,
            [SELECT COUNT() FROM CaseComment WHERE ParentId = :created[0].caseId],
            'Escalate writes one comment; the two updates should add two more.'
        );
    }

    @IsTest
    static void addUpdate_rejectsMismatchAndMissingInputs() {
        useTestQueueMap();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{ newEscalation('S92000002') }
        );

        ITDeskTicketUpdate.UpdateRequest mismatch = new ITDeskTicketUpdate.UpdateRequest();
        mismatch.caseNumber = created[0].caseNumber;
        mismatch.studentId = 'S99999999';
        mismatch.updateDetails = 'Should not attach to another student.';

        ITDeskTicketUpdate.UpdateRequest missing = new ITDeskTicketUpdate.UpdateRequest();
        missing.updateDetails = 'No identifiers';

        ITDeskTicketUpdate.UpdateRequest unknown = new ITDeskTicketUpdate.UpdateRequest();
        unknown.studentId = 'S00000000';
        unknown.updateDetails = 'No ticket';

        Test.startTest();
        List<ITDeskTicketUpdate.UpdateResult> results = ITDeskTicketUpdate.addUpdate(
            new List<ITDeskTicketUpdate.UpdateRequest>{ mismatch, missing, unknown, null }
        );
        List<ITDeskTicketUpdate.UpdateResult> empty = ITDeskTicketUpdate.addUpdate(
            new List<ITDeskTicketUpdate.UpdateRequest>()
        );
        Test.stopTest();

        Assert.isFalse(results[0].isSuccess);
        Assert.isTrue(results[0].message.contains('does not match'));
        Assert.isFalse(results[1].isSuccess);
        Assert.isFalse(results[2].isSuccess);
        Assert.isFalse(results[3].isSuccess);
        Assert.areEqual(0, empty.size());
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM CaseComment WHERE ParentId = :created[0].caseId],
            'Failed updates must not add comments beyond the original escalation note.'
        );
    }

    @IsTest
    static void addUpdate_rejectsClosedTicket() {
        useTestQueueMap();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{ newEscalation('S92000003') }
        );
        List<CaseStatus> closedStatuses = [
            SELECT MasterLabel
            FROM CaseStatus
            WHERE IsClosed = TRUE
            LIMIT 1
        ];
        Assert.isFalse(closedStatuses.isEmpty(), 'Org must have at least one closed Case status.');
        update new Case(Id = created[0].caseId, Status = closedStatuses[0].MasterLabel);

        ITDeskTicketUpdate.UpdateRequest request = new ITDeskTicketUpdate.UpdateRequest();
        request.caseNumber = created[0].caseNumber;
        request.updateDetails = 'Still broken after close.';

        Test.startTest();
        List<ITDeskTicketUpdate.UpdateResult> results = ITDeskTicketUpdate.addUpdate(
            new List<ITDeskTicketUpdate.UpdateRequest>{ request }
        );
        Test.stopTest();

        Assert.isFalse(results[0].isSuccess);
        Assert.isTrue(results[0].nextSteps.contains('escalate a new'));
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM CaseComment WHERE ParentId = :created[0].caseId]
        );
    }

    private static ITDeskTicketEscalation.EscalationRequest newEscalation(String studentId) {
        ITDeskTicketEscalation.EscalationRequest request = new ITDeskTicketEscalation.EscalationRequest();
        request.studentId = studentId;
        request.issueDescription = 'Campus WiFi is unavailable in the library.';
        request.urgency = 'High';
        request.category = 'Network';
        return request;
    }

    private static void useTestQueueMap() {
        ITDeskRoutingService.useCustomMetadataRouting = false;
        ITDeskRoutingService.metadataOverrides = null;
        ITDeskRoutingService.defaultQueueDeveloperName = TEST_QUEUE_GENERAL;
        ITDeskRoutingService.categoryKeywordToQueueDevName = new Map<String, String>{
            'network' => TEST_QUEUE_NETWORK,
            'wifi' => TEST_QUEUE_NETWORK
        };
    }

    private static void ensureQueue(String developerName, String name) {
        List<Group> existing = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :developerName
            LIMIT 1
        ];
        Group queue = existing.isEmpty()
            ? new Group(Name = name, DeveloperName = developerName, Type = 'Queue')
            : existing[0];
        if (existing.isEmpty()) {
            insert queue;
        }
        if (
            [
                SELECT COUNT()
                FROM QueueSobject
                WHERE QueueId = :queue.Id AND SobjectType = 'Case'
            ] == 0
        ) {
            insert new QueueSobject(QueueId = queue.Id, SobjectType = 'Case');
        }
    }
}
