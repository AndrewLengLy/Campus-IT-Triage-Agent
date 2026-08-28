/**
 * Behaviour coverage for ITDeskTicketUpdate: appending student detail to an open ticket,
 * refusing another student's ticket, and refusing a closed one.
 *
 * Failure modes live in ITDeskNegativePathTest; 200-record batches live in ITDeskBulkTest.
 */
@IsTest
private class ITDeskTicketUpdateTest {
    @TestSetup
    static void setupQueues() {
        ITDeskTestFactory.createTestQueues();
    }

    @IsTest
    static void addUpdate_appendsDetailByCaseNumberOrByStudentId() {
        ITDeskTestFactory.useTestRouting();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{ newEscalation('S92000001') }
        );

        Test.startTest();
        List<ITDeskTicketUpdate.UpdateResult> results = ITDeskTicketUpdate.addUpdate(
            new List<ITDeskTicketUpdate.UpdateRequest>{
                ITDeskTestFactory.ticketUpdate(
                    created[0].caseNumber,
                    'S92000001',
                    'The outage is in Residence Hall B, room 214.'
                ),
                ITDeskTestFactory.ticketUpdate(
                    null,
                    'S92000001',
                    'Error text: DNS_PROBE_FINISHED_NXDOMAIN'
                )
            }
        );
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess, 'A Case Number plus a matching Student ID must be accepted.');
        Assert.areEqual(created[0].caseId, results[0].caseId);
        Assert.isTrue(results[0].message.contains(created[0].caseNumber), 'The caller must confirm the number.');
        Assert.isTrue(results[1].isSuccess, 'A Student ID alone must reach their only open ticket.');
        Assert.areEqual(created[0].caseId, results[1].caseId);

        List<CaseComment> comments = [
            SELECT CommentBody, IsPublished
            FROM CaseComment
            WHERE ParentId = :created[0].caseId
        ];
        Assert.areEqual(
            3,
            comments.size(),
            'Escalation writes one comment; the two updates should add two more.'
        );
        for (CaseComment comment : comments) {
            Assert.isTrue(comment.IsPublished, 'Updates must be visible to the student, not internal-only.');
        }
        Assert.areEqual(
            2,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Outcome__c = :ITDeskAuditService.OUTCOME_UPDATED
            ],
            'Each accepted update must leave one audit row.'
        );
    }

    @IsTest
    static void addUpdate_refusesToCommentOnAnotherStudentsTicket() {
        ITDeskTestFactory.useTestRouting();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{ newEscalation('S92000002') }
        );

        Test.startTest();
        List<ITDeskTicketUpdate.UpdateResult> results = ITDeskTicketUpdate.addUpdate(
            new List<ITDeskTicketUpdate.UpdateRequest>{
                ITDeskTestFactory.ticketUpdate(
                    created[0].caseNumber,
                    'S99999999',
                    'Should not attach to another student.'
                )
            }
        );
        Test.stopTest();

        Assert.isFalse(results[0].isSuccess);
        Assert.isTrue(
            results[0].message.contains('does not match'),
            'The caller must be told the identifiers disagree, not that the ticket is missing.'
        );
        Assert.isTrue(
            results[0].nextSteps.contains('another student'),
            'The guidance must be explicit about not writing to someone else\'s ticket.'
        );
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM CaseComment WHERE ParentId = :created[0].caseId],
            'Only the original escalation comment may exist.'
        );
    }

    @IsTest
    static void addUpdate_refusesAClosedTicketAndAsksForANewOne() {
        ITDeskTestFactory.useTestRouting();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{ newEscalation('S92000003') }
        );
        update new Case(Id = created[0].caseId, Status = ITDeskTestFactory.closedCaseStatus());

        Test.startTest();
        List<ITDeskTicketUpdate.UpdateResult> results = ITDeskTicketUpdate.addUpdate(
            new List<ITDeskTicketUpdate.UpdateRequest>{
                ITDeskTestFactory.ticketUpdate(created[0].caseNumber, null, 'Still broken after close.')
            }
        );
        Test.stopTest();

        Assert.isFalse(results[0].isSuccess);
        Assert.areEqual(created[0].caseId, results[0].caseId, 'The caller still needs to know which ticket.');
        Assert.isTrue(
            results[0].nextSteps.contains('escalate a new'),
            'A closed ticket must send the caller to a new escalation, not a silent no-op.'
        );
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM CaseComment WHERE ParentId = :created[0].caseId],
            'A closed ticket must not receive new comments.'
        );
    }

    @IsTest
    static void addUpdate_recordsTheStudentIdInTheCommentBody() {
        ITDeskTestFactory.useTestRouting();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{ newEscalation('S92000004') }
        );

        Test.startTest();
        ITDeskTicketUpdate.addUpdate(
            new List<ITDeskTicketUpdate.UpdateRequest>{
                ITDeskTestFactory.ticketUpdate(created[0].caseNumber, 'S92000004', 'It also fails on ethernet.')
            }
        );
        Test.stopTest();

        List<CaseComment> comments = [
            SELECT CommentBody
            FROM CaseComment
            WHERE ParentId = :created[0].caseId AND CommentBody LIKE '%ethernet%'
        ];
        Assert.areEqual(1, comments.size(), 'The update text must reach the Case.');
        Assert.isTrue(
            comments[0].CommentBody.contains('Student update via Campus IT triage'),
            'A technician must be able to tell a triage-sourced comment from a colleague\'s note.'
        );
        Assert.isTrue(
            comments[0].CommentBody.contains('S92000004'),
            'The comment must record which student supplied the detail.'
        );
    }

    private static ITDeskTicketEscalation.EscalationRequest newEscalation(String studentId) {
        return ITDeskTestFactory.escalation(
            studentId,
            'Campus WiFi is unavailable in the library.',
            'High',
            'Network'
        );
    }
}
