/**
 * Failure-mode coverage for the invocable actions: bad input, missing queues, queues that
 * cannot own a Case, and save failures partway through a batch.
 *
 * Every action returns a result per request rather than throwing, so the assertions here are
 * about the shape of the failure: the right request fails, the others still succeed, the
 * result list stays aligned, and the failure is written to the audit trail.
 */
@IsTest
private class ITDeskNegativePathTest {
    @TestSetup
    static void setupQueues() {
        ITDeskTestFactory.createTestQueues();
    }

    // ---------------------------------------------------------------- queue problems

    @IsTest
    static void escalate_rulePointingAtAMissingQueueStillOpensTheTicket() {
        ITDeskRoutingService.useCustomMetadataRouting = true;
        ITDeskRoutingService.defaultQueueDeveloperName = ITDeskTestFactory.QUEUE_MISSING;
        ITDeskRoutingService.metadataOverrides = new List<IT_Category_Queue_Map__mdt>{
            ITDeskTestFactory.newRoutingRule('network', 'wifi', ITDeskTestFactory.QUEUE_MISSING, false),
            ITDeskTestFactory.newRoutingRule(null, null, ITDeskTestFactory.QUEUE_MISSING, true)
        };

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation('S90000000', 'WiFi is down in the science building.', 'Urgent', 'Network')
            }
        );
        Test.stopTest();

        Assert.isTrue(
            results[0].isSuccess,
            'A routing rule that points at a deleted queue must not cost the student their ticket.'
        );
        Assert.isTrue(
            results[0].nextSteps.contains('could not be routed'),
            'The caller must be told the ticket was not routed, so it is not left silently unowned.'
        );

        Case created = [SELECT OwnerId, Priority FROM Case WHERE Id = :results[0].caseId];
        Assert.areEqual(
            UserInfo.getUserId(),
            created.OwnerId,
            'With no queue to assign, the Case falls to the running user rather than staying ownerless.'
        );
        Assert.areEqual('High', created.Priority, 'Urgency mapping must still apply on the fallback path.');
    }

    @IsTest
    static void escalate_queueThatCannotOwnCasesFailsOnlyThatRequest() {
        ITDeskRoutingService.useCustomMetadataRouting = true;
        ITDeskRoutingService.defaultQueueDeveloperName = ITDeskTestFactory.QUEUE_GENERAL;
        ITDeskRoutingService.metadataOverrides = new List<IT_Category_Queue_Map__mdt>{
            ITDeskTestFactory.newRoutingRule(
                'network',
                'wifi',
                ITDeskTestFactory.QUEUE_NOT_ENABLED_FOR_CASE,
                false
            ),
            ITDeskTestFactory.newRoutingRule(null, null, ITDeskTestFactory.QUEUE_GENERAL, true)
        };

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation('S90000000', 'WiFi keeps dropping.', 'High', 'Network'),
                ITDeskTestFactory.escalation('S90000001', 'Question about printing quotas.', 'Low', 'Parking')
            }
        );
        Test.stopTest();

        Assert.isFalse(
            results[0].isSuccess,
            'A queue that is not enabled for Case cannot own a ticket, so the save must fail.'
        );
        Assert.isNull(results[0].caseId, 'A failed save must not report a Case Id.');
        Assert.isTrue(
            results[1].isSuccess,
            'One misconfigured routing rule must not take down the rest of the batch.'
        );
        Assert.areEqual(1, [SELECT COUNT() FROM Case], 'Only the well-routed request may create a Case.');
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Outcome__c = :ITDeskAuditService.OUTCOME_FAILED
            ],
            'The failed escalation must be visible in the audit trail.'
        );
    }

    // ---------------------------------------------------------------- save failures

    @IsTest
    static void escalate_malformedEmailFailsThatTicketAndReportsIt() {
        ITDeskTestFactory.useTestRouting();
        ITDeskTicketEscalation.EscalationRequest bad = ITDeskTestFactory.escalation(
            'S90000000',
            'Cannot log in to the portal.',
            'High',
            'Password'
        );
        bad.studentEmail = 'not an email address';

        ITDeskTicketEscalation.EscalationRequest good = ITDeskTestFactory.escalation(
            'S90000001',
            'Cannot log in to the portal either.',
            'High',
            'Password'
        );
        good.studentEmail = 'jordan.chen@campus.edu';

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{ bad, good }
        );
        Test.stopTest();

        Assert.isFalse(results[0].isSuccess, 'A malformed email must fail the Case insert.');
        Assert.isTrue(
            results[0].message.contains('wasn\'t able to create a ticket'),
            'The caller must get a student-safe failure message, not a raw DML error.'
        );
        Assert.isTrue(results[1].isSuccess, 'The valid request in the same batch must still succeed.');
        Assert.areEqual(
            good.studentEmail,
            [SELECT SuppliedEmail FROM Case WHERE Id = :results[1].caseId].SuppliedEmail,
            'The valid email must be stored on the surviving Case.'
        );
    }

    // ---------------------------------------------------------------- missing and malformed input

    @IsTest
    static void escalate_rejectsMissingRequiredInputWithoutTouchingTheDatabase() {
        ITDeskTestFactory.useTestRouting();
        List<ITDeskTicketEscalation.EscalationRequest> requests =
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation(null, 'Printer jam in the lab.', 'Low', 'Printer'),
                ITDeskTestFactory.escalation('S90000000', null, 'Low', 'Printer'),
                ITDeskTestFactory.escalation('  ', 'Broken mouse.', 'Low', 'Hardware'),
                ITDeskTestFactory.escalation('S90000001', '   ', 'Low', 'Hardware'),
                null
            };

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(requests);
        Test.stopTest();

        Assert.areEqual(5, results.size(), 'Every request must get a result.');
        for (Integer i = 0; i < results.size(); i++) {
            Assert.isFalse(results[i].isSuccess, 'Request ' + i + ' is missing a required field.');
            Assert.isNull(results[i].caseId, 'Request ' + i + ' must not report a Case Id.');
            Assert.isTrue(
                results[i].nextSteps.contains('Student ID'),
                'Request ' + i + ' must tell the caller what to collect before retrying.'
            );
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Case], 'Invalid requests must not insert Cases.');
        Assert.areEqual(
            5,
            [SELECT COUNT() FROM Campus_IT_Interaction__c WHERE Success__c = FALSE],
            'Rejected requests must still be audited.'
        );
    }

    @IsTest
    static void escalate_nullAndEmptyBatchesReturnEmptyWithoutSideEffects() {
        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> nullBatch = ITDeskTicketEscalation.escalate(null);
        List<ITDeskTicketEscalation.EscalationResult> emptyBatch = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>()
        );
        List<ITDeskTicketStatus.StatusResult> nullStatus = ITDeskTicketStatus.checkStatus(null);
        List<ITDeskTicketUpdate.UpdateResult> nullUpdate = ITDeskTicketUpdate.addUpdate(null);
        List<ITDeskSelfService.SelfServiceResult> nullGuide = ITDeskSelfService.findGuide(null);
        Test.stopTest();

        Assert.areEqual(0, nullBatch.size());
        Assert.areEqual(0, emptyBatch.size());
        Assert.areEqual(0, nullStatus.size());
        Assert.areEqual(0, nullUpdate.size());
        Assert.areEqual(0, nullGuide.size());
        Assert.areEqual(0, [SELECT COUNT() FROM Case], 'An empty batch must not write anything.');
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Campus_IT_Interaction__c],
            'An empty batch must not write audit noise.'
        );
    }

    /**
     * Characterisation test, not a specification.
     *
     * A student ID made only of punctuation passes the not-blank check but normalizes to null,
     * so the Case is created with no Student ID and can never be found by a student-ID lookup.
     * This records today's behaviour; see "Known issues" in ARCHITECTURE.md for the proposed
     * validation change.
     */
    @IsTest
    static void escalate_studentIdWithNoAlphanumericsProducesAnUnfindableTicket() {
        ITDeskTestFactory.useTestRouting();

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation('---', 'My laptop will not start.', 'High', 'Laptop')
            }
        );
        List<ITDeskTicketStatus.StatusResult> lookup = ITDeskTicketStatus.checkStatus(
            new List<ITDeskTicketStatus.StatusRequest>{ ITDeskTestFactory.status(null, '---') }
        );
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess, 'The punctuation-only student ID is accepted today.');
        Assert.isNull(
            [SELECT Student_ID__c FROM Case WHERE Id = :results[0].caseId].Student_ID__c,
            'It normalizes away, leaving a Case with no Student ID.'
        );
        Assert.isFalse(
            lookup[0].isSuccess,
            'And the student can never find the ticket again by student ID.'
        );
    }

    // ---------------------------------------------------------------- status failures

    @IsTest
    static void checkStatus_reportsNotFoundDistinctlyForNumbersAndStudents() {
        Test.startTest();
        List<ITDeskTicketStatus.StatusResult> results = ITDeskTicketStatus.checkStatus(
            new List<ITDeskTicketStatus.StatusRequest>{
                ITDeskTestFactory.status(null, null),
                ITDeskTestFactory.status('99999999', null),
                ITDeskTestFactory.status(null, 'S00000000'),
                null
            }
        );
        Test.stopTest();

        Assert.areEqual(4, results.size());
        for (ITDeskTicketStatus.StatusResult result : results) {
            Assert.isFalse(result.isSuccess);
            Assert.areEqual(0, result.openTicketCount, 'A miss must report zero open tickets, not null.');
        }
        Assert.isTrue(
            results[0].nextSteps.contains('Student ID'),
            'With no identifiers at all, the caller must be told what to ask for.'
        );
        Assert.isTrue(
            results[1].message.contains('could not find a ticket'),
            'An unknown Case Number needs its own message so the caller can re-read the number.'
        );
        Assert.isTrue(
            results[2].message.contains('could not find an existing ticket'),
            'An unknown Student ID needs its own message so the caller can offer to escalate.'
        );
        Assert.areEqual(
            4,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Action_Type__c = :ITDeskAuditService.ACTION_STATUS
            ],
            'Failed lookups must be audited so repeated misses are visible.'
        );
    }

    // ---------------------------------------------------------------- update failures

    @IsTest
    static void addUpdate_wrongCaseNumberIsNotSilentlyRedirectedToTheStudentsOtherTicket() {
        ITDeskTestFactory.useTestRouting();
        ITDeskTestFactory.insertOpenCases(1, 'Network', ITDeskTestFactory.queueId(ITDeskTestFactory.QUEUE_NETWORK));

        Test.startTest();
        List<ITDeskTicketUpdate.UpdateResult> results = ITDeskTicketUpdate.addUpdate(
            new List<ITDeskTicketUpdate.UpdateRequest>{
                ITDeskTestFactory.ticketUpdate(
                    '99999999',
                    ITDeskTestFactory.bulkStudentId(0),
                    'This detail belongs to a ticket number that does not exist.'
                )
            }
        );
        Test.stopTest();

        Assert.isFalse(
            results[0].isSuccess,
            'A Case Number the caller supplied but that does not exist must fail, not silently ' +
            'fall through to whatever other ticket the student has open.'
        );
        Assert.areEqual(0, [SELECT COUNT() FROM CaseComment], 'Nothing may be written on a miss.');
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Outcome__c = :ITDeskAuditService.OUTCOME_NOT_FOUND
            ],
            'A miss must be audited as Not Found rather than Failed.'
        );
    }

    @IsTest
    static void addUpdate_requiresDetailsAndAnIdentifier() {
        Test.startTest();
        List<ITDeskTicketUpdate.UpdateResult> results = ITDeskTicketUpdate.addUpdate(
            new List<ITDeskTicketUpdate.UpdateRequest>{
                ITDeskTestFactory.ticketUpdate('00001234', 'S10000001', null),
                ITDeskTestFactory.ticketUpdate('00001234', 'S10000001', '   '),
                ITDeskTestFactory.ticketUpdate(null, null, 'Details with nothing to attach them to.'),
                null
            }
        );
        Test.stopTest();

        for (Integer i = 0; i < results.size(); i++) {
            Assert.isFalse(results[i].isSuccess, 'Request ' + i + ' is missing required input.');
            Assert.isTrue(
                results[i].nextSteps.contains('Case Number') || results[i].nextSteps.contains('retry'),
                'Request ' + i + ' must tell the caller how to recover.'
            );
        }
        Assert.areEqual(0, [SELECT COUNT() FROM CaseComment]);
    }

    // ---------------------------------------------------------------- self-service failures

    @IsTest
    static void findGuide_returnsNoMatchWhenTheCatalogIsEmptyOrEntirelyInactive() {
        ITDeskSelfService.knownIssueOverrides = new List<IT_Known_Issue__mdt>{
            ITDeskTestFactory.newKnownIssue('Retired guide', 'wifi', 'Network', false, false),
            new IT_Known_Issue__mdt(Title__c = 'No keywords', Keywords__c = null, Is_Active__c = true),
            null
        };

        Test.startTest();
        List<ITDeskSelfService.SelfServiceResult> results = ITDeskSelfService.findGuide(
            new List<ITDeskSelfService.SelfServiceRequest>{
                ITDeskTestFactory.selfService('Campus WiFi keeps dropping.', 'Network', 'S10000001')
            }
        );
        Test.stopTest();

        Assert.isFalse(results[0].isMatch, 'An inactive or keywordless catalog cannot match anything.');
        Assert.isTrue(
            results[0].requiresEscalation,
            'With no guide to offer, the caller must be pointed at escalation.'
        );
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Outcome__c = :ITDeskAuditService.OUTCOME_NO_MATCH
            ],
            'A miss must be audited so catalog gaps are measurable.'
        );
    }

    @IsTest
    static void findGuide_categoryBreaksTheTieBetweenTwoKeywordMatches() {
        ITDeskSelfService.knownIssueOverrides = new List<IT_Known_Issue__mdt>{
            ITDeskTestFactory.newKnownIssue('Network printer setup', 'printer', 'Network', false, true),
            ITDeskTestFactory.newKnownIssue('Printer hardware faults', 'printer', 'Hardware', false, true)
        };

        Test.startTest();
        List<ITDeskSelfService.SelfServiceResult> results = ITDeskSelfService.findGuide(
            new List<ITDeskSelfService.SelfServiceRequest>{
                ITDeskTestFactory.selfService('The printer is not working.', 'Hardware', 'S10000001')
            }
        );
        Test.stopTest();

        Assert.isTrue(results[0].isMatch);
        Assert.areEqual(
            'Printer hardware faults',
            results[0].title,
            'When two guides match the same keyword, the one whose category matches must win.'
        );
    }

    @IsTest
    static void findGuide_missingDescriptionIsRejectedBeforeMatching() {
        ITDeskSelfService.knownIssueOverrides = ITDeskTestFactory.knownIssueCatalog();

        Test.startTest();
        List<ITDeskSelfService.SelfServiceResult> results = ITDeskSelfService.findGuide(
            new List<ITDeskSelfService.SelfServiceRequest>{
                ITDeskTestFactory.selfService(null, 'Network', 'S10000001'),
                ITDeskTestFactory.selfService('   ', 'Network', 'S10000001'),
                null
            }
        );
        Test.stopTest();

        for (Integer i = 0; i < results.size(); i++) {
            Assert.isFalse(results[i].isMatch, 'Request ' + i + ' has nothing to match on.');
            Assert.isFalse(
                results[i].requiresEscalation,
                'Request ' + i + ' must ask for a description rather than escalating on no information.'
            );
        }
        Assert.areEqual(
            3,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Outcome__c = :ITDeskAuditService.OUTCOME_FAILED
            ],
            'A rejected lookup is audited as Failed, distinct from a genuine No Match.'
        );
    }

    // ---------------------------------------------------------------- operations snapshot edges

    @IsTest
    static void getSnapshot_onAQuietDeskReportsZeroRatherThanNothing() {
        Test.startTest();
        List<ITDeskOperationsSnapshot.SnapshotResult> results = ITDeskOperationsSnapshot.getSnapshot(null);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'A null request list must still produce one whole-desk snapshot.');
        Assert.areEqual(0, results[0].openTicketCount);
        Assert.areEqual(0, results[0].highPriorityOpen);
        Assert.isNull(results[0].oldestCaseNumber, 'With no tickets there is no oldest ticket.');
        Assert.isNull(
            results[0].deflectionRate,
            'Deflection must be null with no volume, not a misleading zero percent.'
        );
        Assert.areEqual('None', results[0].queueBreakdown);
        Assert.isTrue(results[0].message.contains('No agent-sourced tickets are waiting'));
    }

    @IsTest
    static void getSnapshot_ignoresTicketsTheDeskDidNotSource() {
        insert new Case(
            Subject = 'Walk-up ticket logged by a technician',
            Origin = 'Phone',
            Status = 'New',
            Priority = 'High',
            Agent_Sourced__c = false
        );

        Test.startTest();
        List<ITDeskOperationsSnapshot.SnapshotResult> results = ITDeskOperationsSnapshot.getSnapshot(
            new List<ITDeskOperationsSnapshot.SnapshotRequest>{ ITDeskTestFactory.snapshot(null) }
        );
        Test.stopTest();

        Assert.areEqual(
            0,
            results[0].openTicketCount,
            'The snapshot measures triage load, so tickets the desk did not source must be excluded.'
        );
    }
}
