/**
 * Behaviour coverage for ITDeskTicketStatus: lookup by Case Number or Student ID, the
 * tolerance for spoken numbers, and what the caller is told about a closed ticket.
 *
 * Failure modes live in ITDeskNegativePathTest; 200-record batches live in ITDeskBulkTest.
 */
@IsTest
private class ITDeskTicketStatusTest {
    @TestSetup
    static void setupQueues() {
        ITDeskTestFactory.createTestQueues();
    }

    @IsTest
    static void checkStatus_findsTheTicketByCaseNumberOrByStudentId() {
        ITDeskTestFactory.useTestRouting();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation(
                    'S91000001',
                    'Campus WiFi is unavailable in the library.',
                    'High',
                    'Network'
                )
            }
        );

        Test.startTest();
        List<ITDeskTicketStatus.StatusResult> results = ITDeskTicketStatus.checkStatus(
            new List<ITDeskTicketStatus.StatusRequest>{
                ITDeskTestFactory.status(created[0].caseNumber, 'ignored-when-number-present'),
                ITDeskTestFactory.status(null, 'S91000001')
            }
        );
        Test.stopTest();

        Assert.areEqual(2, results.size());
        Assert.isTrue(results[0].isSuccess);
        Assert.areEqual(created[0].caseId, results[0].caseId, 'Case Number must win when both are supplied.');
        Assert.areEqual('New', results[0].status);
        Assert.areEqual('High', results[0].priority);
        Assert.areEqual('S91000001', results[0].studentId);
        Assert.areEqual('Network', results[0].category);
        Assert.isFalse(results[0].isClosed);
        Assert.areEqual(1, results[0].openTicketCount);
        Assert.areEqual(
            'CIT Test Network',
            results[0].queueName,
            'The caller must be able to tell the student who owns the work.'
        );
        Assert.isTrue(results[0].message.contains(created[0].caseNumber));

        Assert.isTrue(results[1].isSuccess, 'A student with one open ticket must be findable by Student ID.');
        Assert.areEqual(created[0].caseId, results[1].caseId);
        Assert.areEqual(1, results[1].openTicketCount);
    }

    @IsTest
    static void checkStatus_acceptsAShortCaseNumberAndFallsBackToStudentId() {
        ITDeskTestFactory.useTestRouting();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation(
                    'S91000003',
                    'Campus WiFi is unavailable in the library.',
                    'High',
                    'Network'
                )
            }
        );
        String spokenNumber = created[0].caseNumber.replaceFirst('^0+', '');

        Test.startTest();
        List<ITDeskTicketStatus.StatusResult> results = ITDeskTicketStatus.checkStatus(
            new List<ITDeskTicketStatus.StatusRequest>{
                ITDeskTestFactory.status(spokenNumber, null),
                ITDeskTestFactory.status('99999999', 's 9100-0003')
            }
        );
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess, 'A number spoken without leading zeros must resolve.');
        Assert.areEqual(created[0].caseId, results[0].caseId);
        Assert.isTrue(
            results[1].isSuccess,
            'A wrong Case Number with a valid Student ID must fall back rather than dead-end.'
        );
        Assert.areEqual(created[0].caseId, results[1].caseId);
    }

    @IsTest
    static void checkStatus_countsOpenTicketsAcrossAStudentsQueues() {
        ITDeskTestFactory.useTestRouting();
        ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation('S91000004', 'WiFi keeps dropping.', 'High', 'Network'),
                ITDeskTestFactory.escalation('S91000004', 'Laptop will not charge.', 'High', 'Hardware')
            }
        );

        Test.startTest();
        List<ITDeskTicketStatus.StatusResult> results = ITDeskTicketStatus.checkStatus(
            new List<ITDeskTicketStatus.StatusRequest>{ ITDeskTestFactory.status(null, 'S91000004') }
        );
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess);
        Assert.areEqual(
            2,
            results[0].openTicketCount,
            'A Student ID lookup must report how many tickets the student has open, not just the newest.'
        );
    }

    @IsTest
    static void checkStatus_namesTheTechnicianWhenATicketIsNoLongerOnAQueue() {
        ITDeskTestFactory.useTestRouting();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation('S91000005', 'WiFi keeps dropping.', 'High', 'Network')
            }
        );
        // A technician accepting the ticket takes it off the queue and onto themselves.
        update new Case(Id = created[0].caseId, OwnerId = UserInfo.getUserId());

        Test.startTest();
        List<ITDeskTicketStatus.StatusResult> results = ITDeskTicketStatus.checkStatus(
            new List<ITDeskTicketStatus.StatusRequest>{
                ITDeskTestFactory.status(created[0].caseNumber, null)
            }
        );
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess);
        Assert.areEqual(
            UserInfo.getName(),
            results[0].queueName,
            'Once a technician owns the ticket the caller must be given their name, not a stale queue.'
        );
        Assert.isTrue(
            results[0].nextSteps.contains(UserInfo.getName()),
            'The guidance must name whoever actually owns the work.'
        );
    }

    @IsTest
    static void checkStatus_onAClosedTicketPointsTheCallerAtANewEscalation() {
        ITDeskTestFactory.useTestRouting();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation(
                    'S91000002',
                    'Campus WiFi is unavailable in the library.',
                    'High',
                    'Network'
                )
            }
        );
        update new Case(Id = created[0].caseId, Status = ITDeskTestFactory.closedCaseStatus());

        Test.startTest();
        List<ITDeskTicketStatus.StatusResult> results = ITDeskTicketStatus.checkStatus(
            new List<ITDeskTicketStatus.StatusRequest>{
                ITDeskTestFactory.status(created[0].caseNumber, null)
            }
        );
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess, 'Finding a closed ticket is still a successful lookup.');
        Assert.isTrue(results[0].isClosed);
        Assert.areEqual(0, results[0].openTicketCount, 'A closed ticket must not be counted as open.');
        Assert.isTrue(
            results[0].nextSteps.contains('escalate a new Case'),
            'The caller must be told to open a new ticket rather than chase a closed one.'
        );
    }
}
