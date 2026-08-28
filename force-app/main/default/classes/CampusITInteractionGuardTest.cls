/**
 * Coverage for the append-only guarantee on Campus_IT_Interaction__c.
 *
 * The guarantee is enforced in code, not by convention, at two layers:
 *
 *   1. CampusITInteractionGuard rejects every before-update and before-delete, so the block
 *      applies to Apex, Flow, the Lightning UI, Data Loader, and the APIs alike.
 *   2. The Campus_IT_Triage_Agent permission set grants Create and Read on the object but
 *      withholds Edit and Delete, so the running user cannot reach the trigger in the first
 *      place.
 *
 * Two holes remain and are deliberately not asserted here, because closing them is a design
 * decision rather than a bug fix. See "Append-only: what is and is not guaranteed" in
 * ARCHITECTURE.md:
 *
 *   - Case__c uses deleteConstraint SetNull, so deleting the parent Case clears the lookup on
 *     the audit row without routing through the before-update trigger.
 *   - A user with Author Apex can deactivate the trigger, and Modify All Data plus a metadata
 *     deployment can remove it entirely.
 */
@IsTest
private class CampusITInteractionGuardTest {
    @IsTest
    static void insert_isTheOnlyOperationTheTrailAccepts() {
        Test.startTest();
        insert auditRow('Ticket found.');
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Campus_IT_Interaction__c],
            'Appending to the audit trail must work; only edits and deletes are blocked.'
        );
    }

    @IsTest
    static void update_isRejectedWithAnExplanatoryMessage() {
        insert auditRow('Ticket found.');
        Campus_IT_Interaction__c stored = [SELECT Id, Outcome__c FROM Campus_IT_Interaction__c LIMIT 1];
        stored.Outcome__c = ITDeskAuditService.OUTCOME_FAILED;

        Test.startTest();
        String message = '';
        try {
            update stored;
            Assert.fail('Updating an audit row must throw.');
        } catch (DmlException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(
            message.contains('append-only'),
            'The rejection must say why, so an admin does not assume a permissions problem. Got: ' + message
        );
        Assert.areEqual(
            ITDeskAuditService.OUTCOME_FOUND,
            [SELECT Outcome__c FROM Campus_IT_Interaction__c LIMIT 1].Outcome__c,
            'The stored outcome must be unchanged after a rejected update.'
        );
    }

    @IsTest
    static void delete_isRejectedWithAnExplanatoryMessage() {
        insert auditRow('Ticket found.');
        Campus_IT_Interaction__c stored = [SELECT Id FROM Campus_IT_Interaction__c LIMIT 1];

        Test.startTest();
        String message = '';
        try {
            delete stored;
            Assert.fail('Deleting an audit row must throw.');
        } catch (DmlException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(
            message.contains('append-only'),
            'The rejection must say why. Got: ' + message
        );
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Campus_IT_Interaction__c],
            'The row must survive a rejected delete.'
        );
    }

    @IsTest
    static void partialSaveDoesNotLetAnyRowThrough() {
        List<Campus_IT_Interaction__c> rows = ITDeskTestFactory.interactions(50);
        insert rows;

        List<Campus_IT_Interaction__c> stored = [SELECT Id, Summary__c FROM Campus_IT_Interaction__c];
        for (Campus_IT_Interaction__c row : stored) {
            row.Summary__c = 'Rewritten history.';
        }

        Test.startTest();
        List<Database.SaveResult> saveResults = Database.update(stored, false);
        List<Database.DeleteResult> deleteResults = Database.delete(stored, false);
        Test.stopTest();

        for (Database.SaveResult result : saveResults) {
            Assert.isFalse(
                result.isSuccess(),
                'allOrNone = false must not let individual audit rows be edited.'
            );
        }
        for (Database.DeleteResult result : deleteResults) {
            Assert.isFalse(
                result.isSuccess(),
                'allOrNone = false must not let individual audit rows be deleted.'
            );
        }
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Campus_IT_Interaction__c WHERE Summary__c = 'Rewritten history.'],
            'No row may carry the rewritten summary.'
        );
        Assert.areEqual(50, [SELECT COUNT() FROM Campus_IT_Interaction__c], 'Every row must survive.');
    }

    @IsTest
    static void everyStateChangeInAnEscalationLeavesAnAuditRow() {
        ITDeskTestFactory.useTestRouting();
        ITDeskTestFactory.insertStudents(1);
        String studentId = ITDeskTestFactory.bulkStudentId(0);

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation(studentId, 'Residence hall WiFi keeps dropping.', 'High', 'Network')
            }
        );
        ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation(studentId, 'Still dropping this evening.', 'High', 'Network')
            }
        );
        ITDeskTicketUpdate.addUpdate(
            new List<ITDeskTicketUpdate.UpdateRequest>{
                ITDeskTestFactory.ticketUpdate(created[0].caseNumber, studentId, 'It also drops in the library.')
            }
        );
        ITDeskTicketStatus.checkStatus(
            new List<ITDeskTicketStatus.StatusRequest>{
                ITDeskTestFactory.status(created[0].caseNumber, null)
            }
        );
        Test.stopTest();

        Map<String, Integer> countsByOutcome = new Map<String, Integer>();
        for (Campus_IT_Interaction__c row : [
            SELECT Action_Type__c, Outcome__c, Case__c, Case_Number__c
            FROM Campus_IT_Interaction__c
        ]) {
            String key = row.Action_Type__c + '/' + row.Outcome__c;
            countsByOutcome.put(key, (countsByOutcome.containsKey(key) ? countsByOutcome.get(key) : 0) + 1);
            Assert.isNotNull(row.Case__c, 'Every row in this flow relates to a Case and must record it.');
        }

        Assert.areEqual(
            1,
            countsByOutcome.get(ITDeskAuditService.ACTION_ESCALATE + '/' + ITDeskAuditService.OUTCOME_CREATED),
            'Creating the ticket must leave one Created row.'
        );
        Assert.areEqual(
            1,
            countsByOutcome.get(ITDeskAuditService.ACTION_ESCALATE + '/' + ITDeskAuditService.OUTCOME_REUSED),
            'Reusing the ticket must leave one Reused row.'
        );
        Assert.areEqual(
            1,
            countsByOutcome.get(ITDeskAuditService.ACTION_UPDATE + '/' + ITDeskAuditService.OUTCOME_UPDATED),
            'Commenting on the ticket must leave one Updated row.'
        );
        Assert.areEqual(
            1,
            countsByOutcome.get(ITDeskAuditService.ACTION_STATUS + '/' + ITDeskAuditService.OUTCOME_FOUND),
            'Reading the ticket status must leave one Found row.'
        );
    }

    /**
     * The invariant that matters: audit history outlives the Case it describes. Case_Number__c
     * is stored as text next to the Case__c lookup precisely so the trail keeps its subject.
     *
     * Whether the Case delete itself succeeds depends on the Case__c delete constraint. It is
     * SetNull today, so the platform clears the lookup on the audit row; the delete is wrapped
     * because that cascade may or may not route through the before-update guard. Either
     * outcome is acceptable here and neither is asserted. Switching the constraint to Restrict
     * would make the behaviour explicit, which ARCHITECTURE.md proposes.
     */
    @IsTest
    static void auditHistoryOutlivesTheCaseItDescribes() {
        ITDeskTestFactory.useTestRouting();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation('S90000000', 'Laptop will not power on.', 'High', 'Laptop')
            }
        );
        String caseNumber = created[0].caseNumber;
        Assert.areEqual(1, [SELECT COUNT() FROM Campus_IT_Interaction__c], 'Escalation must be audited.');

        Test.startTest();
        Database.delete(new List<Case>{ new Case(Id = created[0].caseId) }, false);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Campus_IT_Interaction__c],
            'Deleting a Case must never delete its audit history.'
        );
        Assert.areEqual(
            caseNumber,
            [SELECT Case_Number__c FROM Campus_IT_Interaction__c LIMIT 1].Case_Number__c,
            'The Case Number text must outlive the Case record, otherwise the trail loses its subject.'
        );
    }

    private static Campus_IT_Interaction__c auditRow(String summary) {
        return ITDeskAuditService.newInteraction(
            ITDeskAuditService.ACTION_STATUS,
            ITDeskAuditService.OUTCOME_FOUND,
            true,
            'S10000001',
            null,
            '00001234',
            'Network',
            null,
            summary
        );
    }
}
