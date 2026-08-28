/**
 * Behaviour coverage for ITDeskTicketEscalation: what ends up on the Case, how urgency maps to
 * priority, how categories reach queues, and when an open ticket is reused instead of
 * duplicated.
 *
 * Routing is driven by the isolated CIT_Test_* rules from ITDeskTestFactory so these tests do
 * not depend on the packaged queues. ITDeskQueueRoutingTest covers the shipped configuration,
 * ITDeskNegativePathTest covers the failure modes, and ITDeskBulkTest covers 200-record batches.
 */
@IsTest
private class ITDeskTicketEscalationTest {
    @TestSetup
    static void setupQueues() {
        ITDeskTestFactory.createTestQueues();
    }

    @IsTest
    static void escalate_stampsEverythingATechnicianNeedsOnTheCase() {
        ITDeskTestFactory.useTestRouting();
        ITDeskTicketEscalation.EscalationRequest request = ITDeskTestFactory.escalation(
            'S12345678',
            'Residence hall WiFi drops every evening.',
            'High',
            'Network'
        );
        request.studentEmail = 'alex.rivera@campus.edu';
        request.selfServiceAttempted = true;
        request.selfServiceArticle = 'Reconnect to campus WiFi';

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{ request }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'One request should produce one result.');
        ITDeskTicketEscalation.EscalationResult result = results[0];
        Assert.isTrue(result.isSuccess, 'Valid input should create a Case.');
        Assert.isNotNull(result.caseId, 'Case Id should be returned.');
        Assert.isNotNull(result.caseNumber, 'Case Number is required so the caller can confirm the ticket.');
        Assert.isFalse(result.isExistingTicket, 'The first escalation should create a new Case.');
        Assert.isTrue(
            result.message.contains(result.caseNumber),
            'The student-facing message should include the ticket number.'
        );
        Assert.isTrue(result.nextSteps.contains(result.caseNumber), 'Next steps should include the Case Number.');
        Assert.isTrue(
            result.nextSteps.contains('CIT Test Network'),
            'Next steps should name the queue that will pick the ticket up.'
        );

        Case created = [
            SELECT
                Subject,
                Description,
                Origin,
                Status,
                Priority,
                Student_ID__c,
                IT_Category__c,
                OwnerId,
                SuppliedEmail,
                Agent_Sourced__c,
                Reused_Existing_Ticket__c,
                Self_Service_Attempted__c,
                Self_Service_Article__c,
                First_Response_Due__c
            FROM Case
            WHERE Id = :result.caseId
        ];
        Assert.areEqual('S12345678', created.Student_ID__c, 'Student ID must be stored normalized.');
        Assert.areEqual('Network', created.IT_Category__c, 'The canonical category must be stamped.');
        Assert.areEqual('Web', created.Origin);
        Assert.areEqual('New', created.Status);
        Assert.areEqual('High', created.Priority);
        Assert.isTrue(created.Subject.startsWith('Campus IT: Network'), 'Subject must be scannable in a list view.');
        Assert.isTrue(created.Description.contains('S12345678'), 'Description must carry the student ID.');
        Assert.areEqual(
            ITDeskTestFactory.queueId(ITDeskTestFactory.QUEUE_NETWORK),
            created.OwnerId,
            'A Network category must land on the network queue.'
        );
        Assert.areEqual('alex.rivera@campus.edu', created.SuppliedEmail);
        Assert.isTrue(created.Agent_Sourced__c, 'Triage-created Cases must be distinguishable from walk-ups.');
        Assert.isFalse(created.Reused_Existing_Ticket__c);
        Assert.isTrue(created.Self_Service_Attempted__c);
        Assert.areEqual('Reconnect to campus WiFi', created.Self_Service_Article__c);
        Assert.isNotNull(created.First_Response_Due__c, 'The SLA clock must start when the ticket opens.');
        Assert.isTrue(created.First_Response_Due__c > Datetime.now());

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM CaseComment WHERE ParentId = :created.Id AND IsPublished = TRUE],
            'The student-visible summary must be published on the Case.'
        );
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Action_Type__c = :ITDeskAuditService.ACTION_ESCALATE
                AND Outcome__c = :ITDeskAuditService.OUTCOME_CREATED
                AND Case__c = :created.Id
            ],
            'Creating a ticket must leave exactly one audit row.'
        );
    }

    @IsTest
    static void escalate_mapsSpokenUrgencyOntoCasePriority() {
        ITDeskTestFactory.useTestRouting();
        List<ITDeskTicketEscalation.EscalationRequest> requests =
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation('S90000000', 'Cannot print in the library.', 'Critical', 'Printer'),
                ITDeskTestFactory.escalation('S90000001', 'Need a software license.', 'p3', 'License'),
                ITDeskTestFactory.escalation('S90000002', 'Keyboard key is stuck.', 'low', 'Hardware'),
                ITDeskTestFactory.escalation('S90000003', 'General how-to question.', null, 'Other')
            };

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(requests);
        Test.stopTest();

        Map<Id, Case> created = new Map<Id, Case>(
            [SELECT Priority, First_Response_Due__c FROM Case]
        );
        Assert.areEqual('High', created.get(results[0].caseId).Priority, '"Critical" must escalate to High.');
        Assert.areEqual('Medium', created.get(results[1].caseId).Priority, '"p3" is not urgent, so Medium.');
        Assert.areEqual('Low', created.get(results[2].caseId).Priority, '"low" must map to Low.');
        Assert.areEqual('Medium', created.get(results[3].caseId).Priority, 'No urgency given defaults to Medium.');

        Assert.isTrue(
            created.get(results[0].caseId).First_Response_Due__c <
                created.get(results[2].caseId).First_Response_Due__c,
            'A High priority ticket must be due for first response before a Low priority one.'
        );
    }

    @IsTest
    static void escalate_sendsEachCategoryToItsQueue() {
        ITDeskTestFactory.useTestRouting();
        List<ITDeskTicketEscalation.EscalationRequest> requests =
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation('S90000000', 'VPN will not connect.', 'High', 'VPN'),
                ITDeskTestFactory.escalation('S90000001', 'Laptop will not boot.', 'High', 'Laptop'),
                ITDeskTestFactory.escalation('S90000002', 'Outlook will not send mail.', 'Medium', 'Email'),
                ITDeskTestFactory.escalation('S90000003', 'Forgot password, MFA locked.', 'High', 'Account Access'),
                ITDeskTestFactory.escalation('S90000004', 'Need help with something else.', 'Medium', 'Dining Services')
            };

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(requests);
        Test.stopTest();

        Map<Id, Case> created = new Map<Id, Case>([SELECT OwnerId, IT_Category__c FROM Case]);
        Assert.areEqual(
            ITDeskTestFactory.queueId(ITDeskTestFactory.QUEUE_NETWORK),
            created.get(results[0].caseId).OwnerId,
            'VPN is a network alias.'
        );
        Assert.areEqual(
            ITDeskTestFactory.queueId(ITDeskTestFactory.QUEUE_HARDWARE),
            created.get(results[1].caseId).OwnerId,
            'Laptop is a hardware alias.'
        );
        Assert.areEqual(
            ITDeskTestFactory.queueId(ITDeskTestFactory.QUEUE_SOFTWARE),
            created.get(results[2].caseId).OwnerId,
            'Email is a software alias.'
        );
        Assert.areEqual(
            ITDeskTestFactory.queueId(ITDeskTestFactory.QUEUE_IDENTITY),
            created.get(results[3].caseId).OwnerId,
            'A category containing "account" belongs to identity.'
        );
        Assert.areEqual(
            ITDeskTestFactory.queueId(ITDeskTestFactory.QUEUE_GENERAL),
            created.get(results[4].caseId).OwnerId,
            'An unmapped category must fall through to the default queue rather than stalling.'
        );
        Assert.areEqual('General', created.get(results[4].caseId).IT_Category__c);
    }

    @IsTest
    static void escalate_normalizesAMessyStudentIdAndLinksTheContact() {
        ITDeskTestFactory.useTestRouting();
        Contact student = new Contact(LastName = 'Kim', Student_ID__c = 'S12345679');
        insert student;

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation('s 1234-5679', 'VPN will not connect off campus.', 'High', 'VPN')
            }
        );
        Test.stopTest();

        Case created = [SELECT Student_ID__c, IT_Category__c, ContactId FROM Case WHERE Id = :results[0].caseId];
        Assert.areEqual('S12345679', created.Student_ID__c, 'A spoken student ID must be stored normalized.');
        Assert.areEqual('Network', created.IT_Category__c);
        Assert.areEqual(
            student.Id,
            created.ContactId,
            'The Case must link to the student Contact so technicians can see their history.'
        );
    }

    @IsTest
    static void escalate_truncatesLongSubjectsToFitTheField() {
        ITDeskTestFactory.useTestRouting();
        String longDescription = 'Unable to connect to campus WiFi. '.repeat(20);

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation('S90000000', longDescription, 'Medium', 'WiFi'),
                ITDeskTestFactory.escalation('S90000001', longDescription, 'Medium', 'WiFi '.repeat(40))
            }
        );
        Test.stopTest();

        Case truncatedDescription = [SELECT Subject, Description FROM Case WHERE Id = :results[0].caseId];
        Assert.isTrue(truncatedDescription.Subject.contains('...'), 'A clipped subject must show it was clipped.');
        Assert.isTrue(
            truncatedDescription.Description.contains('Reported urgency: Medium'),
            'The full context belongs in the Description, not the Subject.'
        );
        Assert.isTrue(truncatedDescription.Description.contains('Source: Campus IT triage'));

        Case truncatedSubject = [SELECT Subject FROM Case WHERE Id = :results[1].caseId];
        Assert.areEqual(
            255,
            truncatedSubject.Subject.length(),
            'An oversized category must not push the Subject past the field limit.'
        );
    }

    @IsTest
    static void escalate_blankCategoryOpensAGeneralTicket() {
        ITDeskTestFactory.useTestRouting();

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation('S90000000', 'Need a technician on site.', 'Medium', null)
            }
        );
        Test.stopTest();

        Case created = [SELECT Subject, Description, OwnerId FROM Case WHERE Id = :results[0].caseId];
        Assert.isTrue(created.Subject.startsWith('Campus IT: General'));
        Assert.isFalse(
            created.Description.contains('Category:'),
            'A category the caller never supplied must not be invented in the Description.'
        );
        Assert.areEqual(ITDeskTestFactory.queueId(ITDeskTestFactory.QUEUE_GENERAL), created.OwnerId);
    }

    @IsTest
    static void escalate_reusesTheOpenTicketPerCategoryUnlessForcedToOpenANewOne() {
        ITDeskTestFactory.useTestRouting();
        Contact student = new Contact(FirstName = 'Alex', LastName = 'Rivera', Student_ID__c = 'S90000001');
        insert student;

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation('S90000001', 'Residence hall WiFi drops every evening.', 'High', 'Network')
            }
        );
        List<ITDeskTicketEscalation.EscalationResult> reused = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation('S90000001', 'Still cannot stay on WiFi.', 'High', 'WiFi')
            }
        );
        List<ITDeskTicketEscalation.EscalationResult> hardware = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation('S90000001', 'Laptop will not charge.', 'High', 'Hardware')
            }
        );
        List<ITDeskTicketEscalation.EscalationResult> reusedHardware = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                ITDeskTestFactory.escalation('S90000001', 'Laptop still will not charge.', 'High', 'Hardware')
            }
        );
        ITDeskTicketEscalation.EscalationRequest forced = ITDeskTestFactory.escalation(
            'S90000001',
            'Different hardware issue: cracked screen.',
            'High',
            'Hardware'
        );
        forced.forceNewTicket = true;
        List<ITDeskTicketEscalation.EscalationResult> forcedNew = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{ forced }
        );
        Test.stopTest();

        Assert.isFalse(created[0].isExistingTicket, 'The first report opens a ticket.');
        Assert.isTrue(reused[0].isExistingTicket, 'A second report in the same category reuses it.');
        Assert.areEqual(created[0].caseId, reused[0].caseId);
        Assert.isTrue(reused[0].message.contains(created[0].caseNumber), 'The caller must be given the same number.');
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM CaseComment WHERE ParentId = :created[0].caseId],
            'Reusing an open ticket must append the new detail as a published comment.'
        );

        Case networkCase = [SELECT ContactId, Reused_Existing_Ticket__c FROM Case WHERE Id = :created[0].caseId];
        Assert.areEqual(student.Id, networkCase.ContactId);
        Assert.isTrue(
            networkCase.Reused_Existing_Ticket__c,
            'Reuse must be stamped on the Case so duplicate suppression is measurable.'
        );

        Assert.isFalse(hardware[0].isExistingTicket, 'A different category is a different queue and a new ticket.');
        Assert.isTrue(reusedHardware[0].isExistingTicket, 'A second hardware report reuses the open hardware ticket.');
        Assert.areEqual(hardware[0].caseId, reusedHardware[0].caseId);
        Assert.isFalse(forcedNew[0].isExistingTicket, 'Force New Ticket must open a second ticket in the same queue.');
        Assert.areNotEqual(hardware[0].caseId, forcedNew[0].caseId);
        Assert.areEqual(
            3,
            [SELECT COUNT() FROM Case WHERE Student_ID__c = 'S90000001'],
            'One network ticket, one hardware ticket, one forced ticket.'
        );
    }
}
