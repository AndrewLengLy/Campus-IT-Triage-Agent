/**
 * Coverage for ITDeskTicketStatus. Relies on the same CIT_Test_* queues as escalation tests.
 */
@IsTest
private class ITDeskTicketStatusTest {
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
    static void checkStatus_byCaseNumberAndStudentId() {
        useTestQueueMap();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{ newEscalation('S91000001', 'Network') }
        );

        ITDeskTicketStatus.StatusRequest byNumber = new ITDeskTicketStatus.StatusRequest();
        byNumber.caseNumber = created[0].caseNumber;
        byNumber.studentId = 'ignored-when-number-present';

        ITDeskTicketStatus.StatusRequest byStudent = new ITDeskTicketStatus.StatusRequest();
        byStudent.studentId = 'S91000001';

        Test.startTest();
        List<ITDeskTicketStatus.StatusResult> results = ITDeskTicketStatus.checkStatus(
            new List<ITDeskTicketStatus.StatusRequest>{ byNumber, byStudent }
        );
        Test.stopTest();

        Assert.areEqual(2, results.size());
        Assert.isTrue(results[0].isSuccess);
        Assert.areEqual(created[0].caseId, results[0].caseId);
        Assert.areEqual('New', results[0].status);
        Assert.areEqual('High', results[0].priority);
        Assert.areEqual('S91000001', results[0].studentId);
        Assert.isFalse(results[0].isClosed);
        Assert.areEqual(1, results[0].openTicketCount);
        Assert.areEqual('CIT Test Network', results[0].queueName);
        Assert.isTrue(results[0].message.contains(created[0].caseNumber));

        Assert.isTrue(results[1].isSuccess);
        Assert.areEqual(created[0].caseId, results[1].caseId);
        Assert.areEqual(1, results[1].openTicketCount);
        Assert.areEqual('Network', results[0].category);
    }

    @IsTest
    static void checkStatus_acceptsShortCaseNumberAndFallsBackToStudentId() {
        useTestQueueMap();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{ newEscalation('S91000003', 'Network') }
        );
        String shortNumber = created[0].caseNumber.replaceFirst('^0+', '');

        ITDeskTicketStatus.StatusRequest byShort = new ITDeskTicketStatus.StatusRequest();
        byShort.caseNumber = shortNumber;

        ITDeskTicketStatus.StatusRequest fallback = new ITDeskTicketStatus.StatusRequest();
        fallback.caseNumber = '99999999';
        fallback.studentId = 's 9100-0003';

        Test.startTest();
        List<ITDeskTicketStatus.StatusResult> results = ITDeskTicketStatus.checkStatus(
            new List<ITDeskTicketStatus.StatusRequest>{ byShort, fallback }
        );
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess);
        Assert.areEqual(created[0].caseId, results[0].caseId);
        Assert.isTrue(results[1].isSuccess, 'A bad Case Number should fall back to Student ID.');
        Assert.areEqual(created[0].caseId, results[1].caseId);
    }

    @IsTest
    static void checkStatus_missingInputsAndUnknownTicket() {
        ITDeskTicketStatus.StatusRequest missing = new ITDeskTicketStatus.StatusRequest();
        ITDeskTicketStatus.StatusRequest unknownNumber = new ITDeskTicketStatus.StatusRequest();
        unknownNumber.caseNumber = '99999999';
        ITDeskTicketStatus.StatusRequest unknownStudent = new ITDeskTicketStatus.StatusRequest();
        unknownStudent.studentId = 'S00000000';

        Test.startTest();
        List<ITDeskTicketStatus.StatusResult> results = ITDeskTicketStatus.checkStatus(
            new List<ITDeskTicketStatus.StatusRequest>{ missing, unknownNumber, unknownStudent, null }
        );
        List<ITDeskTicketStatus.StatusResult> emptyResults = ITDeskTicketStatus.checkStatus(
            new List<ITDeskTicketStatus.StatusRequest>()
        );
        List<ITDeskTicketStatus.StatusResult> nullResults = ITDeskTicketStatus.checkStatus(null);
        Test.stopTest();

        Assert.areEqual(4, results.size());
        for (ITDeskTicketStatus.StatusResult result : results) {
            Assert.isFalse(result.isSuccess);
            Assert.areEqual(0, result.openTicketCount);
        }
        Assert.isTrue(results[0].nextSteps.contains('Student ID'));
        Assert.isTrue(results[1].message.contains('could not find a ticket'));
        Assert.isTrue(results[2].message.contains('could not find an existing ticket'));
        Assert.areEqual(0, emptyResults.size());
        Assert.areEqual(0, nullResults.size());
    }

    @IsTest
    static void checkStatus_closedTicketGuidesStudentToEscalate() {
        useTestQueueMap();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{ newEscalation('S91000002', 'Network') }
        );
        List<CaseStatus> closedStatuses = [
            SELECT MasterLabel
            FROM CaseStatus
            WHERE IsClosed = TRUE
            LIMIT 1
        ];
        Assert.isFalse(closedStatuses.isEmpty(), 'Org must have at least one closed Case status.');
        update new Case(Id = created[0].caseId, Status = closedStatuses[0].MasterLabel);

        ITDeskTicketStatus.StatusRequest request = new ITDeskTicketStatus.StatusRequest();
        request.caseNumber = created[0].caseNumber;

        Test.startTest();
        List<ITDeskTicketStatus.StatusResult> results = ITDeskTicketStatus.checkStatus(
            new List<ITDeskTicketStatus.StatusRequest>{ request }
        );
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess);
        Assert.isTrue(results[0].isClosed);
        Assert.areEqual(0, results[0].openTicketCount);
        Assert.isTrue(results[0].nextSteps.contains('escalate a new Case'));
    }

    private static ITDeskTicketEscalation.EscalationRequest newEscalation(String studentId, String category) {
        ITDeskTicketEscalation.EscalationRequest request = new ITDeskTicketEscalation.EscalationRequest();
        request.studentId = studentId;
        request.issueDescription = 'Campus WiFi is unavailable in the library.';
        request.urgency = 'High';
        request.category = category;
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
        Group queue;
        if (existing.isEmpty()) {
            queue = new Group(Name = name, DeveloperName = developerName, Type = 'Queue');
            insert queue;
        } else {
            queue = existing[0];
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
