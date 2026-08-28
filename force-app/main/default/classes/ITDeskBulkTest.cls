/**
 * Governor-limit coverage: every invocable action must survive a full 200-record batch in a
 * single transaction.
 *
 * Each test measures SOQL and DML consumed by the action itself, between Test.startTest() and
 * Test.stopTest(), and asserts the count stays flat rather than scaling with the batch. A
 * query or DML statement inside a per-request loop fails these assertions long before it
 * fails in production, which is the point.
 */
@IsTest
private class ITDeskBulkTest {
    private static final Integer BATCH = 200;

    /** Headroom allowed for one action call. The actions each use fewer than this today. */
    private static final Integer MAX_SOQL = 6;
    private static final Integer MAX_DML = 6;

    private static Integer soqlAtStart;
    private static Integer dmlAtStart;

    @TestSetup
    static void setupQueues() {
        ITDeskTestFactory.createTestQueues();
    }

    // ---------------------------------------------------------------- escalate

    @IsTest
    static void escalate_creates200CasesInOneTransaction() {
        ITDeskTestFactory.useTestRouting();
        List<String> categories = new List<String>{ 'WiFi', 'Laptop', 'Outlook', 'Password', 'Parking' };
        List<ITDeskTicketEscalation.EscalationRequest> requests =
            new List<ITDeskTicketEscalation.EscalationRequest>();
        for (Integer i = 0; i < BATCH; i++) {
            requests.add(
                ITDeskTestFactory.escalation(
                    ITDeskTestFactory.bulkStudentId(i),
                    'Bulk escalation ' + i + ': the campus service is not working.',
                    Math.mod(i, 3) == 0 ? 'High' : 'Medium',
                    categories[Math.mod(i, categories.size())]
                )
            );
        }

        Test.startTest();
        beginMeasuring();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(requests);
        assertLimitsAreFlat('escalate');
        Test.stopTest();

        Assert.areEqual(BATCH, results.size(), 'Results must stay aligned one-to-one with requests.');
        for (Integer i = 0; i < BATCH; i++) {
            Assert.isTrue(results[i].isSuccess, 'Request ' + i + ' should have produced a Case.');
            Assert.isNotNull(results[i].caseNumber, 'Request ' + i + ' must return a Case Number.');
        }

        Assert.areEqual(BATCH, [SELECT COUNT() FROM Case], 'Every request must produce exactly one Case.');
        Assert.areEqual(
            BATCH,
            [SELECT COUNT() FROM CaseComment WHERE IsPublished = TRUE],
            'Every new Case must carry its published triage comment.'
        );
        Assert.areEqual(
            BATCH,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Action_Type__c = :ITDeskAuditService.ACTION_ESCALATE
                AND Outcome__c = :ITDeskAuditService.OUTCOME_CREATED
            ],
            'The audit trail must record one Created row per escalation, not a sample of them.'
        );
        Set<Id> ownersUsed = new Set<Id>();
        for (Case ticket : [SELECT OwnerId FROM Case]) {
            ownersUsed.add(ticket.OwnerId);
        }
        Assert.areEqual(5, ownersUsed.size(), 'A mixed batch must fan out across all five test queues.');
    }

    @IsTest
    static void escalate_reuses200OpenTicketsInOneTransaction() {
        ITDeskTestFactory.useTestRouting();
        ITDeskTestFactory.insertOpenCases(BATCH, 'Network', ITDeskTestFactory.queueId(ITDeskTestFactory.QUEUE_NETWORK));

        List<ITDeskTicketEscalation.EscalationRequest> requests =
            new List<ITDeskTicketEscalation.EscalationRequest>();
        for (Integer i = 0; i < BATCH; i++) {
            requests.add(
                ITDeskTestFactory.escalation(
                    ITDeskTestFactory.bulkStudentId(i),
                    'Still broken, following up on the same problem.',
                    'Medium',
                    'Network'
                )
            );
        }

        Test.startTest();
        beginMeasuring();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(requests);
        assertLimitsAreFlat('escalate (reuse path)');
        Test.stopTest();

        for (Integer i = 0; i < BATCH; i++) {
            Assert.isTrue(results[i].isExistingTicket, 'Request ' + i + ' should have reused the open ticket.');
        }
        Assert.areEqual(
            BATCH,
            [SELECT COUNT() FROM Case],
            'Reuse must not create duplicate Cases for students who already have an open ticket.'
        );
        Assert.areEqual(
            BATCH,
            [SELECT COUNT() FROM Case WHERE Reused_Existing_Ticket__c = TRUE],
            'Every reused Case must be stamped so the desk can measure duplicate suppression.'
        );
        Assert.areEqual(
            BATCH,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Outcome__c = :ITDeskAuditService.OUTCOME_REUSED
            ],
            'Reuse must be auditable, not silent.'
        );
    }

    @IsTest
    static void escalate_mixedValidAndInvalidBatchKeepsResultsAligned() {
        ITDeskTestFactory.useTestRouting();
        List<ITDeskTicketEscalation.EscalationRequest> requests =
            new List<ITDeskTicketEscalation.EscalationRequest>();
        Integer expectedValid = 0;
        for (Integer i = 0; i < BATCH; i++) {
            if (Math.mod(i, 4) == 0) {
                requests.add(ITDeskTestFactory.escalation(null, 'No student ID supplied.', 'High', 'Network'));
            } else if (Math.mod(i, 4) == 1) {
                requests.add(ITDeskTestFactory.escalation(ITDeskTestFactory.bulkStudentId(i), '  ', 'High', 'Network'));
            } else if (Math.mod(i, 4) == 2) {
                requests.add(null);
            } else {
                requests.add(
                    ITDeskTestFactory.escalation(
                        ITDeskTestFactory.bulkStudentId(i),
                        'A genuine issue that needs a technician.',
                        'High',
                        'Network'
                    )
                );
                expectedValid++;
            }
        }

        Test.startTest();
        beginMeasuring();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(requests);
        assertLimitsAreFlat('escalate (mixed batch)');
        Test.stopTest();

        Assert.areEqual(BATCH, results.size(), 'Every request must get a result, valid or not.');
        for (Integer i = 0; i < BATCH; i++) {
            Boolean shouldSucceed = Math.mod(i, 4) == 3;
            Assert.areEqual(
                shouldSucceed,
                results[i].isSuccess,
                'Result ' + i + ' is out of position: one bad request must not shift the others.'
            );
        }
        Assert.areEqual(
            expectedValid,
            [SELECT COUNT() FROM Case],
            'Only the valid requests may create Cases.'
        );
        Assert.areEqual(
            BATCH,
            [SELECT COUNT() FROM Campus_IT_Interaction__c WHERE Action_Type__c = :ITDeskAuditService.ACTION_ESCALATE],
            'Rejected requests must be audited too, otherwise failures are invisible.'
        );
    }

    // ---------------------------------------------------------------- self-service

    @IsTest
    static void findGuide_matches200RequestsInOneTransaction() {
        ITDeskSelfService.knownIssueOverrides = ITDeskTestFactory.knownIssueCatalog();
        List<String> descriptions = new List<String>{
            'Campus Wi-Fi keeps dropping in the residence hall.',
            'I forgot my password and need a reset.',
            'The VPN client will not install on my machine.',
            'Outlook is stuck offline and will not send.',
            'My laptop has no power at all.',
            'The dining hall app crashed again.'
        };

        List<ITDeskSelfService.SelfServiceRequest> requests = new List<ITDeskSelfService.SelfServiceRequest>();
        for (Integer i = 0; i < BATCH; i++) {
            requests.add(
                ITDeskTestFactory.selfService(
                    descriptions[Math.mod(i, descriptions.size())],
                    null,
                    ITDeskTestFactory.bulkStudentId(i)
                )
            );
        }

        Test.startTest();
        beginMeasuring();
        List<ITDeskSelfService.SelfServiceResult> results = ITDeskSelfService.findGuide(requests);
        assertLimitsAreFlat('findGuide');
        Test.stopTest();

        Assert.areEqual(BATCH, results.size(), 'Results must stay aligned one-to-one with requests.');
        Integer matched = 0;
        for (Integer i = 0; i < BATCH; i++) {
            Boolean expectMatch = Math.mod(i, descriptions.size()) != 5;
            Assert.areEqual(
                expectMatch,
                results[i].isMatch,
                'Result ' + i + ' does not correspond to request ' + i + '.'
            );
            if (results[i].isMatch) {
                matched++;
            }
        }

        Assert.areEqual(
            matched,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Outcome__c = :ITDeskAuditService.OUTCOME_MATCHED
            ],
            'Deflection metrics depend on one Matched audit row per matched lookup.'
        );
        Assert.areEqual(
            BATCH,
            [SELECT COUNT() FROM Campus_IT_Interaction__c],
            'Every lookup must be audited, matched or not.'
        );
    }

    // ---------------------------------------------------------------- status

    @IsTest
    static void checkStatus_looksUp200TicketsInOneTransaction() {
        ITDeskTestFactory.useTestRouting();
        List<Case> tickets = ITDeskTestFactory.insertOpenCases(
            BATCH,
            'Network',
            ITDeskTestFactory.queueId(ITDeskTestFactory.QUEUE_NETWORK)
        );

        List<ITDeskTicketStatus.StatusRequest> requests = new List<ITDeskTicketStatus.StatusRequest>();
        for (Integer i = 0; i < BATCH; i++) {
            requests.add(
                Math.mod(i, 2) == 0
                    ? ITDeskTestFactory.status(tickets[i].CaseNumber, null)
                    : ITDeskTestFactory.status(null, ITDeskTestFactory.bulkStudentId(i))
            );
        }

        Test.startTest();
        beginMeasuring();
        List<ITDeskTicketStatus.StatusResult> results = ITDeskTicketStatus.checkStatus(requests);
        assertLimitsAreFlat('checkStatus');
        Test.stopTest();

        Assert.areEqual(BATCH, results.size(), 'Results must stay aligned one-to-one with requests.');
        for (Integer i = 0; i < BATCH; i++) {
            Assert.isTrue(results[i].isSuccess, 'Lookup ' + i + ' should have found the seeded ticket.');
            Assert.areEqual(
                ITDeskTestFactory.bulkStudentId(i),
                results[i].studentId,
                'Lookup ' + i + ' returned another student\'s ticket.'
            );
            Assert.areEqual('CIT Test Network', results[i].queueName, 'Lookup ' + i + ' lost the queue name.');
        }
        Assert.areEqual(
            BATCH,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Action_Type__c = :ITDeskAuditService.ACTION_STATUS
            ],
            'Every status check must be audited.'
        );
    }

    // ---------------------------------------------------------------- update

    @IsTest
    static void addUpdate_comments200TicketsInOneTransaction() {
        ITDeskTestFactory.useTestRouting();
        List<Case> tickets = ITDeskTestFactory.insertOpenCases(
            BATCH,
            'Network',
            ITDeskTestFactory.queueId(ITDeskTestFactory.QUEUE_NETWORK)
        );

        List<ITDeskTicketUpdate.UpdateRequest> requests = new List<ITDeskTicketUpdate.UpdateRequest>();
        for (Integer i = 0; i < BATCH; i++) {
            requests.add(
                Math.mod(i, 2) == 0
                    ? ITDeskTestFactory.ticketUpdate(
                          tickets[i].CaseNumber,
                          ITDeskTestFactory.bulkStudentId(i),
                          'Bulk update ' + i + ': the error message is DNS_PROBE_FINISHED_NXDOMAIN.'
                      )
                    : ITDeskTestFactory.ticketUpdate(
                          null,
                          ITDeskTestFactory.bulkStudentId(i),
                          'Bulk update ' + i + ': this also happens in the library.'
                      )
            );
        }

        Test.startTest();
        beginMeasuring();
        List<ITDeskTicketUpdate.UpdateResult> results = ITDeskTicketUpdate.addUpdate(requests);
        assertLimitsAreFlat('addUpdate');
        Test.stopTest();

        Assert.areEqual(BATCH, results.size(), 'Results must stay aligned one-to-one with requests.');
        for (Integer i = 0; i < BATCH; i++) {
            Assert.isTrue(results[i].isSuccess, 'Update ' + i + ' should have been appended.');
            Assert.areEqual(
                tickets[i].Id,
                results[i].caseId,
                'Update ' + i + ' landed on the wrong Case.'
            );
        }
        Assert.areEqual(
            BATCH,
            [SELECT COUNT() FROM CaseComment],
            'Every accepted update must append exactly one Case Comment.'
        );
        Assert.areEqual(
            BATCH,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Outcome__c = :ITDeskAuditService.OUTCOME_UPDATED
            ],
            'Every accepted update must be audited.'
        );
    }

    @IsTest
    static void addUpdate_mixedFailuresKeepCommentsAlignedWithSaveResults() {
        ITDeskTestFactory.useTestRouting();
        List<Case> tickets = ITDeskTestFactory.insertOpenCases(
            BATCH,
            'Network',
            ITDeskTestFactory.queueId(ITDeskTestFactory.QUEUE_NETWORK)
        );

        List<ITDeskTicketUpdate.UpdateRequest> requests = new List<ITDeskTicketUpdate.UpdateRequest>();
        Integer expectedSuccess = 0;
        for (Integer i = 0; i < BATCH; i++) {
            if (Math.mod(i, 3) == 0) {
                // Case Number belongs to another student: must be rejected, not commented on.
                requests.add(
                    ITDeskTestFactory.ticketUpdate(
                        tickets[i].CaseNumber,
                        ITDeskTestFactory.bulkStudentId(i + 1000),
                        'Should never attach.'
                    )
                );
            } else if (Math.mod(i, 3) == 1) {
                requests.add(ITDeskTestFactory.ticketUpdate(null, null, 'No identifiers at all.'));
            } else {
                requests.add(
                    ITDeskTestFactory.ticketUpdate(
                        tickets[i].CaseNumber,
                        ITDeskTestFactory.bulkStudentId(i),
                        'A legitimate update.'
                    )
                );
                expectedSuccess++;
            }
        }

        Test.startTest();
        beginMeasuring();
        List<ITDeskTicketUpdate.UpdateResult> results = ITDeskTicketUpdate.addUpdate(requests);
        assertLimitsAreFlat('addUpdate (mixed batch)');
        Test.stopTest();

        for (Integer i = 0; i < BATCH; i++) {
            Assert.areEqual(
                Math.mod(i, 3) == 2,
                results[i].isSuccess,
                'Result ' + i + ' is out of position: save results must map back to the right request.'
            );
        }
        Assert.areEqual(
            expectedSuccess,
            [SELECT COUNT() FROM CaseComment],
            'Rejected updates must not leave comments on a student\'s ticket.'
        );
    }

    // ---------------------------------------------------------------- operations snapshot

    @IsTest
    static void getSnapshot_answers200RequestsWithAFixedQueryCount() {
        // The snapshot only names queues whose DeveloperName starts with Campus_IT_, so this
        // fixture uses the deployed network queue rather than the isolated CIT_Test_* one.
        Group networkQueue = [
            SELECT Id, Name
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = 'Campus_IT_Network'
            LIMIT 1
        ];
        ITDeskTestFactory.insertOpenCases(BATCH, 'Network', networkQueue.Id);

        List<ITDeskOperationsSnapshot.SnapshotRequest> requests =
            new List<ITDeskOperationsSnapshot.SnapshotRequest>();
        for (Integer i = 0; i < BATCH; i++) {
            requests.add(ITDeskTestFactory.snapshot(Math.mod(i, 2) == 0 ? null : networkQueue.Name));
        }

        Test.startTest();
        beginMeasuring();
        List<ITDeskOperationsSnapshot.SnapshotResult> results = ITDeskOperationsSnapshot.getSnapshot(requests);
        assertLimitsAreFlat('getSnapshot');
        Test.stopTest();

        Assert.areEqual(BATCH, results.size(), 'Results must stay aligned one-to-one with requests.');
        for (Integer i = 0; i < BATCH; i++) {
            Assert.areEqual(
                BATCH,
                results[i].openTicketCount,
                'Snapshot ' + i + ' must count every open triage-sourced ticket, filtered or not.'
            );
        }
        Assert.areEqual(
            BATCH,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Action_Type__c = :ITDeskAuditService.ACTION_OPERATIONS
            ],
            'Every snapshot must be audited.'
        );
    }

    // ---------------------------------------------------------------- audit trail

    @IsTest
    static void auditTrail_writes200RowsAndStillRefusesEveryEdit() {
        List<Campus_IT_Interaction__c> rows = ITDeskTestFactory.interactions(BATCH);

        Test.startTest();
        beginMeasuring();
        ITDeskAuditService.log(rows);
        assertLimitsAreFlat('ITDeskAuditService.log');
        Test.stopTest();

        List<Campus_IT_Interaction__c> stored = [SELECT Id, Outcome__c FROM Campus_IT_Interaction__c];
        Assert.areEqual(BATCH, stored.size(), 'A 200-row audit batch must be written in one DML statement.');

        for (Campus_IT_Interaction__c row : stored) {
            row.Outcome__c = ITDeskAuditService.OUTCOME_FAILED;
        }
        List<Database.SaveResult> updates = Database.update(stored, false);
        for (Database.SaveResult result : updates) {
            Assert.isFalse(result.isSuccess(), 'No audit row may be edited, even in a bulk update.');
        }

        List<Database.DeleteResult> deletes = Database.delete(stored, false);
        for (Database.DeleteResult result : deletes) {
            Assert.isFalse(result.isSuccess(), 'No audit row may be deleted, even in a bulk delete.');
        }

        Assert.areEqual(
            BATCH,
            [SELECT COUNT() FROM Campus_IT_Interaction__c],
            'The audit trail must be intact after a rejected bulk edit and delete.'
        );
    }

    // ---------------------------------------------------------------- helpers

    private static void beginMeasuring() {
        soqlAtStart = Limits.getQueries();
        dmlAtStart = Limits.getDmlStatements();
    }

    /**
     * Asserts the action consumed a small, fixed number of queries and DML statements. The
     * numbers are deliberately generous: the test is guarding against per-record SOQL or DML,
     * not pinning the current implementation to an exact count.
     */
    private static void assertLimitsAreFlat(String action) {
        Integer soqlUsed = Limits.getQueries() - soqlAtStart;
        Integer dmlUsed = Limits.getDmlStatements() - dmlAtStart;

        Assert.isTrue(
            soqlUsed <= MAX_SOQL,
            action + ' used ' + soqlUsed + ' SOQL queries for ' + BATCH +
            ' records. Anything above ' + MAX_SOQL + ' means a query moved inside a per-record loop.'
        );
        Assert.isTrue(
            dmlUsed <= MAX_DML,
            action + ' used ' + dmlUsed + ' DML statements for ' + BATCH +
            ' records. Anything above ' + MAX_DML + ' means DML moved inside a per-record loop.'
        );
    }
}
