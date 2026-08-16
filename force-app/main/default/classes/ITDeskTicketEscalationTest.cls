/**
 * Isolated coverage for ITDeskTicketEscalation. Test queues use CIT_Test_* DeveloperNames
 * so they never collide with packaged Campus_IT_* queue metadata.
 */
@IsTest
private class ITDeskTicketEscalationTest {
    private static final String TEST_QUEUE_NETWORK = 'CIT_Test_Network';
    private static final String TEST_QUEUE_HARDWARE = 'CIT_Test_Hardware';
    private static final String TEST_QUEUE_SOFTWARE = 'CIT_Test_Software';
    private static final String TEST_QUEUE_IDENTITY = 'CIT_Test_Identity';
    private static final String TEST_QUEUE_GENERAL = 'CIT_Test_General';
    private static final String MISSING_QUEUE = 'CIT_Does_Not_Exist';

    @TestSetup
    static void setupTestQueues() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            ensureQueue(TEST_QUEUE_NETWORK, 'CIT Test Network');
            ensureQueue(TEST_QUEUE_HARDWARE, 'CIT Test Hardware');
            ensureQueue(TEST_QUEUE_SOFTWARE, 'CIT Test Software');
            ensureQueue(TEST_QUEUE_IDENTITY, 'CIT Test Identity');
            ensureQueue(TEST_QUEUE_GENERAL, 'CIT Test General');
        }
    }

    @IsTest
    static void escalate_createsCaseAndReturnsCaseNumber() {
        useTestQueueMap();
        ITDeskTicketEscalation.EscalationRequest request = newRequest(
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
        Assert.isNotNull(result.caseNumber, 'Case Number is required for the agent to read back.');
        Assert.isTrue(
            result.message.contains(result.caseNumber),
            'Student-facing message should include the ticket number.'
        );
        Assert.isFalse(result.isExistingTicket, 'First escalation should create a new Case.');
        Assert.isTrue(
            result.nextSteps.contains(result.caseNumber),
            'Next steps should include the Case Number.'
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
        Assert.areEqual('S12345678', created.Student_ID__c);
        Assert.areEqual('Network', created.IT_Category__c);
        Assert.areEqual('Web', created.Origin);
        Assert.areEqual('New', created.Status);
        Assert.areEqual('High', created.Priority);
        Assert.isTrue(created.Subject.startsWith('Campus IT: Network'));
        Assert.isTrue(created.Description.contains('S12345678'));
        Assert.areEqual(queueId(TEST_QUEUE_NETWORK), created.OwnerId);
        Assert.areEqual('alex.rivera@campus.edu', created.SuppliedEmail);
        Assert.isTrue(created.Agent_Sourced__c);
        Assert.isFalse(created.Reused_Existing_Ticket__c);
        Assert.isTrue(created.Self_Service_Attempted__c);
        Assert.areEqual('Reconnect to campus WiFi', created.Self_Service_Article__c);
        Assert.isNotNull(created.First_Response_Due__c);
        Assert.isTrue(created.First_Response_Due__c > Datetime.now());
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM CaseComment WHERE ParentId = :created.Id AND IsPublished = TRUE]
        );
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Action_Type__c = :ITDeskAuditService.ACTION_ESCALATE
                AND Outcome__c = :ITDeskAuditService.OUTCOME_CREATED
                AND Case__c = :created.Id
            ]
        );
    }

    @IsTest
    static void escalate_mapsPriorityFromUrgency() {
        useTestQueueMap();
        List<ITDeskTicketEscalation.EscalationRequest> requests = new List<ITDeskTicketEscalation.EscalationRequest>{
            newRequest('S100', 'Cannot print in the library.', 'Critical', 'Printer'),
            newRequest('S101', 'Need a software license.', 'p3', 'License'),
            newRequest('S102', 'Keyboard key is stuck.', 'low', 'Hardware'),
            newRequest('S103', 'General how-to question.', null, 'Other')
        };

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(requests);
        Test.stopTest();

        Assert.areEqual(4, results.size());
        Map<Id, Case> created = new Map<Id, Case>([
            SELECT Priority, Student_ID__c
            FROM Case
            WHERE Id IN :new Set<Id>{
                results[0].caseId,
                results[1].caseId,
                results[2].caseId,
                results[3].caseId
            }
        ]);
        Assert.areEqual('High', created.get(results[0].caseId).Priority);
        Assert.areEqual('Medium', created.get(results[1].caseId).Priority);
        Assert.areEqual('Low', created.get(results[2].caseId).Priority);
        Assert.areEqual('Medium', created.get(results[3].caseId).Priority);
    }

    @IsTest
    static void escalate_assignsQueueByCategory() {
        useTestQueueMap();
        List<ITDeskTicketEscalation.EscalationRequest> requests = new List<ITDeskTicketEscalation.EscalationRequest>{
            newRequest('S200', 'VPN will not connect.', 'High', 'VPN'),
            newRequest('S201', 'Laptop will not boot.', 'High', 'Laptop'),
            newRequest('S202', 'Outlook will not send mail.', 'Medium', 'Email'),
            newRequest('S203', 'Forgot password and MFA is locked.', 'High', 'Account Access')
        };

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(requests);
        Test.stopTest();

        Map<Id, Case> created = new Map<Id, Case>([
            SELECT OwnerId
            FROM Case
            WHERE Id IN :new Set<Id>{
                results[0].caseId,
                results[1].caseId,
                results[2].caseId,
                results[3].caseId
            }
        ]);
        Assert.areEqual(queueId(TEST_QUEUE_NETWORK), created.get(results[0].caseId).OwnerId);
        Assert.areEqual(queueId(TEST_QUEUE_HARDWARE), created.get(results[1].caseId).OwnerId);
        Assert.areEqual(queueId(TEST_QUEUE_SOFTWARE), created.get(results[2].caseId).OwnerId);
        Assert.areEqual(queueId(TEST_QUEUE_IDENTITY), created.get(results[3].caseId).OwnerId);
        Assert.isTrue(results[0].nextSteps.contains('CIT Test Network'));
    }

    @IsTest
    static void escalate_unknownCategoryUsesGeneralQueue() {
        useTestQueueMap();
        ITDeskTicketEscalation.EscalationRequest request = newRequest(
            'S300',
            'Need help with something unclassified.',
            'Medium',
            'Dining Services'
        );

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{ request }
        );
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess);
        Case created = [SELECT OwnerId FROM Case WHERE Id = :results[0].caseId];
        Assert.areEqual(queueId(TEST_QUEUE_GENERAL), created.OwnerId);
    }

    @IsTest
    static void escalate_missingQueueStillCreatesCase() {
        ITDeskRoutingService.useCustomMetadataRouting = false;
        ITDeskRoutingService.metadataOverrides = null;
        ITDeskRoutingService.defaultQueueDeveloperName = MISSING_QUEUE;
        ITDeskRoutingService.categoryKeywordToQueueDevName = new Map<String, String>{
            'network' => MISSING_QUEUE
        };

        ITDeskTicketEscalation.EscalationRequest request = newRequest(
            'S400',
            'WiFi is down in the science building.',
            'Urgent',
            'Network'
        );

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{ request }
        );
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess, 'Case must still be created when the queue is absent.');
        Assert.isTrue(
            results[0].nextSteps.contains('could not be routed'),
            'Agent should explain that queue routing was skipped.'
        );
        Case created = [SELECT OwnerId, Priority FROM Case WHERE Id = :results[0].caseId];
        Assert.areEqual(UserInfo.getUserId(), created.OwnerId);
        Assert.areEqual('High', created.Priority);
    }

    @IsTest
    static void escalate_missingRequiredFieldsReturnsFailure() {
        useTestQueueMap();
        List<ITDeskTicketEscalation.EscalationRequest> requests = new List<ITDeskTicketEscalation.EscalationRequest>{
            newRequest(null, 'Printer jam', 'Low', 'Hardware'),
            newRequest('S500', '   ', 'Low', 'Hardware'),
            newRequest('S501', 'Broken mouse', 'Low', 'Hardware'),
            null
        };
        // Blank student ID on the third request after construction
        requests[2].studentId = '';

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(requests);
        Test.stopTest();

        Assert.areEqual(4, results.size());
        for (ITDeskTicketEscalation.EscalationResult result : results) {
            Assert.isFalse(result.isSuccess);
            Assert.isFalse(result.isExistingTicket);
            Assert.isNull(result.caseId);
            Assert.isTrue(result.nextSteps.contains('Student ID'));
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Case], 'Invalid requests must not insert Cases.');
    }

    @IsTest
    static void escalate_bulkMixedSuccessAndValidationFailure() {
        useTestQueueMap();
        List<ITDeskTicketEscalation.EscalationRequest> requests = new List<ITDeskTicketEscalation.EscalationRequest>{
            newRequest('S600', 'Cannot sign in to the portal.', 'High', 'Login'),
            newRequest('', 'Missing student id', 'High', 'Account')
        };

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(requests);
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'Result list must stay aligned with the request list.');
        Assert.isTrue(results[0].isSuccess);
        Assert.isFalse(results[1].isSuccess);
        Assert.areEqual(1, [SELECT COUNT() FROM Case]);
        Assert.areEqual(queueId(TEST_QUEUE_IDENTITY), [SELECT OwnerId FROM Case LIMIT 1].OwnerId);
    }

    @IsTest
    static void escalate_emptyOrNullRequestListReturnsEmpty() {
        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> emptyResults = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>()
        );
        List<ITDeskTicketEscalation.EscalationResult> nullResults = ITDeskTicketEscalation.escalate(null);
        Test.stopTest();

        Assert.areEqual(0, emptyResults.size());
        Assert.areEqual(0, nullResults.size());
    }

    @IsTest
    static void escalate_truncatesLongSubject() {
        useTestQueueMap();
        String longDescription = 'Unable to connect to campus WiFi. '.repeat(20);

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                newRequest('S700', longDescription, 'Medium', 'WiFi'),
                newRequest('S701', longDescription, 'Medium', 'WiFi '.repeat(40))
            }
        );
        Test.stopTest();

        Case truncatedDescription = [SELECT Subject, Description FROM Case WHERE Id = :results[0].caseId];
        Assert.isTrue(truncatedDescription.Subject.contains('...'));
        Assert.isTrue(truncatedDescription.Description.contains('Reported urgency: Medium'));
        Assert.isTrue(truncatedDescription.Description.contains('Source: Agentforce Campus IT Triage Agent'));

        Case truncatedSubject = [SELECT Subject FROM Case WHERE Id = :results[1].caseId];
        Assert.areEqual(255, truncatedSubject.Subject.length());
    }

    @IsTest
    static void escalate_normalizesMessyStudentId() {
        useTestQueueMap();
        Contact student = new Contact(LastName = 'Kim', Student_ID__c = 'S12345679');
        insert student;

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                newRequest('s 1234-5679', 'VPN will not connect off campus.', 'High', 'VPN')
            }
        );
        Test.stopTest();

        Case created = [SELECT Student_ID__c, IT_Category__c, ContactId FROM Case WHERE Id = :results[0].caseId];
        Assert.areEqual('S12345679', created.Student_ID__c);
        Assert.areEqual('Network', created.IT_Category__c);
        Assert.areEqual(student.Id, created.ContactId);
    }

    @IsTest
    static void escalate_blankCategoryDefaultsToGeneral() {
        useTestQueueMap();

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                newRequest('S800', 'Need a technician on site.', 'Medium', null)
            }
        );
        Test.stopTest();

        Case created = [SELECT Subject, Description, OwnerId FROM Case WHERE Id = :results[0].caseId];
        Assert.isTrue(created.Subject.startsWith('Campus IT: General'));
        Assert.isFalse(created.Description.contains('Category:'));
        Assert.areEqual(queueId(TEST_QUEUE_GENERAL), created.OwnerId);
    }

    @IsTest
    static void resolvePriority_coversUrgencyTokens() {
        Assert.areEqual('Medium', ITDeskRoutingService.resolvePriority(null));
        Assert.areEqual('Medium', ITDeskRoutingService.resolvePriority('  '));
        Assert.areEqual('High', ITDeskRoutingService.resolvePriority('P1'));
        Assert.areEqual('High', ITDeskRoutingService.resolvePriority('sev1 emergency'));
        Assert.areEqual('High', ITDeskRoutingService.resolvePriority('p2'));
        Assert.areEqual('Low', ITDeskRoutingService.resolvePriority('P4'));
        Assert.areEqual('Low', ITDeskRoutingService.resolvePriority('sev4'));
        Assert.areEqual('Medium', ITDeskRoutingService.resolvePriority('normal'));
        Assert.areEqual('Medium', ITDeskRoutingService.resolvePriority('standard'));
    }

    @IsTest
    static void resolveQueueDeveloperName_coversKeywordsAndFallbacks() {
        useTestQueueMap();

        Assert.areEqual(TEST_QUEUE_NETWORK, ITDeskRoutingService.resolveQueueDeveloperName('wifi outage'));
        Assert.areEqual(TEST_QUEUE_HARDWARE, ITDeskRoutingService.resolveQueueDeveloperName('Printer'));
        Assert.areEqual(TEST_QUEUE_SOFTWARE, ITDeskRoutingService.resolveQueueDeveloperName('application crash'));
        Assert.areEqual(TEST_QUEUE_IDENTITY, ITDeskRoutingService.resolveQueueDeveloperName('MFA reset'));
        Assert.areEqual(TEST_QUEUE_GENERAL, ITDeskRoutingService.resolveQueueDeveloperName(null));
        Assert.areEqual(TEST_QUEUE_GENERAL, ITDeskRoutingService.resolveQueueDeveloperName('Facilities'));

        ITDeskRoutingService.categoryKeywordToQueueDevName = new Map<String, String>();
        Assert.areEqual(TEST_QUEUE_GENERAL, ITDeskRoutingService.resolveQueueDeveloperName('Network'));

        ITDeskRoutingService.categoryKeywordToQueueDevName = null;
        Assert.areEqual(TEST_QUEUE_GENERAL, ITDeskRoutingService.resolveQueueDeveloperName('Network'));

        useTestQueueMap();
        Assert.areEqual('S10000001', ITDeskRoutingService.normalizeStudentId('s 1000-0001'));
        Assert.isTrue(ITDeskRoutingService.studentIdsMatch('s10000001', 'S-10000001'));
        Assert.isFalse(ITDeskRoutingService.studentIdsMatch('S1', 'S2'));
        Assert.areEqual('wifi is down', ITDeskRoutingService.normalizeIssueText('Wi-Fi is down'));
        Assert.isTrue(ITDeskRoutingService.caseNumberLookupKeys('1234').contains('00001234'));
        Assert.areEqual('Network', ITDeskRoutingService.resolveCategoryLabel('wifi outage'));
        Assert.areEqual('Account', ITDeskRoutingService.resolveCategoryLabel('MFA reset'));
    }

    @IsTest
    static void escalate_linksContactAndReusesOpenTicket() {
        useTestQueueMap();
        Contact student = new Contact(
            FirstName = 'Alex',
            LastName = 'Rivera',
            Student_ID__c = 'S90000001'
        );
        insert student;

        ITDeskTicketEscalation.EscalationRequest first = newRequest(
            'S90000001',
            'Residence hall WiFi drops every evening.',
            'High',
            'Network'
        );

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{ first }
        );
        List<ITDeskTicketEscalation.EscalationResult> reused = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                newRequest('S90000001', 'Still cannot stay on WiFi.', 'High', 'WiFi')
            }
        );
        List<ITDeskTicketEscalation.EscalationResult> hardware = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                newRequest('S90000001', 'Laptop will not charge.', 'High', 'Hardware')
            }
        );
        List<ITDeskTicketEscalation.EscalationResult> reusedHardware = ITDeskTicketEscalation.escalate(
            new List<ITDeskTicketEscalation.EscalationRequest>{
                newRequest('S90000001', 'Laptop still will not charge.', 'High', 'Hardware')
            }
        );
        ITDeskTicketEscalation.EscalationRequest forced = newRequest(
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

        Assert.isFalse(created[0].isExistingTicket);
        Assert.isTrue(reused[0].isExistingTicket);
        Assert.areEqual(created[0].caseId, reused[0].caseId);
        Assert.isTrue(reused[0].message.contains(created[0].caseNumber));
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM CaseComment WHERE ParentId = :created[0].caseId],
            'Reusing an open ticket should append a published Case Comment.'
        );

        Case networkCase = [SELECT ContactId, Reused_Existing_Ticket__c FROM Case WHERE Id = :created[0].caseId];
        Assert.areEqual(student.Id, networkCase.ContactId);
        Assert.isTrue(networkCase.Reused_Existing_Ticket__c, 'Reusing an open ticket should stamp Reused Existing Ticket.');

        Assert.isFalse(hardware[0].isExistingTicket, 'Hardware is a different queue and should open a new Case.');
        Assert.isTrue(reusedHardware[0].isExistingTicket, 'A second Hardware report should reuse the open Hardware Case.');
        Assert.areEqual(hardware[0].caseId, reusedHardware[0].caseId);
        Assert.isFalse(forcedNew[0].isExistingTicket, 'Force New Ticket must insert even when an open Case exists.');
        Assert.areNotEqual(hardware[0].caseId, forcedNew[0].caseId);
        Assert.areEqual(3, [SELECT COUNT() FROM Case WHERE Student_ID__c = 'S90000001']);
    }

    @IsTest
    static void routing_usesCustomMetadataOverridesAndAliases() {
        ITDeskRoutingService.useCustomMetadataRouting = true;
        ITDeskRoutingService.metadataOverrides = new List<IT_Category_Queue_Map__mdt>{
            new IT_Category_Queue_Map__mdt(
                Keyword__c = 'network',
                Aliases__c = 'wifi, vpn',
                Queue_Developer_Name__c = TEST_QUEUE_NETWORK,
                Is_Default__c = false
            ),
            new IT_Category_Queue_Map__mdt(
                Queue_Developer_Name__c = TEST_QUEUE_GENERAL,
                Is_Default__c = true
            )
        };

        Assert.areEqual(TEST_QUEUE_NETWORK, ITDeskRoutingService.resolveQueueDeveloperName('wifi outage'));
        Assert.areEqual(TEST_QUEUE_NETWORK, ITDeskRoutingService.resolveQueueDeveloperName('Campus VPN'));
        Assert.areEqual(TEST_QUEUE_GENERAL, ITDeskRoutingService.resolveQueueDeveloperName('Dining'));
        Assert.areEqual(
            0,
            ITDeskRoutingService.queryQueuesByDeveloperName(new Set<String>()).size()
        );
        Assert.areEqual(0, ITDeskRoutingService.queryContactsByStudentId(new Set<String>()).size());
        Assert.areEqual(0, ITDeskRoutingService.queryOpenCasesByStudentId(new Set<String>()).size());
        Assert.isNull(
            ITDeskRoutingService.findReusableOpenCase(
                'S0',
                'Network',
                TEST_QUEUE_NETWORK,
                new Map<String, List<Case>>(),
                new Map<Id, Group>()
            )
        );

        Case userOwned = new Case(
            Subject = 'Campus IT: Network — wifi dropout',
            OwnerId = UserInfo.getUserId()
        );
        Case matchedBySubject = ITDeskRoutingService.findReusableOpenCase(
            'S1',
            'Network',
            TEST_QUEUE_NETWORK,
            new Map<String, List<Case>>{ 'S1' => new List<Case>{ userOwned } },
            new Map<Id, Group>()
        );
        Assert.areEqual(userOwned, matchedBySubject);
        Assert.areEqual(0, ITDeskRoutingService.queryQueuesById(new Set<Id>()).size());
        Assert.isNull(ITDeskRoutingService.newPublishedComment(null, 'body'));
        Assert.isNull(ITDeskRoutingService.newPublishedComment(UserInfo.getUserId(), '  '));
        ITDeskRoutingService.insertPublishedComments(null);
        ITDeskRoutingService.insertPublishedComments(new List<CaseComment>());
        Assert.areEqual(0, ITDeskRoutingService.tokenize(null).size());
    }

    private static void useTestQueueMap() {
        ITDeskRoutingService.useCustomMetadataRouting = false;
        ITDeskRoutingService.metadataOverrides = null;
        ITDeskRoutingService.defaultQueueDeveloperName = TEST_QUEUE_GENERAL;
        ITDeskRoutingService.categoryKeywordToQueueDevName = new Map<String, String>{
            'network' => TEST_QUEUE_NETWORK,
            'wifi' => TEST_QUEUE_NETWORK,
            'vpn' => TEST_QUEUE_NETWORK,
            'hardware' => TEST_QUEUE_HARDWARE,
            'laptop' => TEST_QUEUE_HARDWARE,
            'printer' => TEST_QUEUE_HARDWARE,
            'software' => TEST_QUEUE_SOFTWARE,
            'application' => TEST_QUEUE_SOFTWARE,
            'license' => TEST_QUEUE_SOFTWARE,
            'email' => TEST_QUEUE_SOFTWARE,
            'outlook' => TEST_QUEUE_SOFTWARE,
            'account' => TEST_QUEUE_IDENTITY,
            'password' => TEST_QUEUE_IDENTITY,
            'login' => TEST_QUEUE_IDENTITY,
            'identity' => TEST_QUEUE_IDENTITY,
            'mfa' => TEST_QUEUE_IDENTITY
        };
    }

    private static ITDeskTicketEscalation.EscalationRequest newRequest(
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

    private static Id queueId(String developerName) {
        return [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :developerName
            LIMIT 1
        ].Id;
    }

    /**
     * Group is a setup object; creating QueueSobject in the same runAs avoids mixed-DML errors.
     * Re-entrant so leftover queues from a prior test run do not fail @TestSetup.
     */
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
