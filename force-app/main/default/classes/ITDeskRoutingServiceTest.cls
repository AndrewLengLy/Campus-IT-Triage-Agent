/**
 * Unit coverage for ITDeskRoutingService: Custom Metadata rule matching, the default-rule
 * fallback, normalization helpers, Case reuse selection, and the bulk-safe query helpers.
 *
 * Routing rules are injected in memory so these tests describe the algorithm, not the
 * shipped configuration. ITDeskQueueRoutingTest covers the shipped configuration.
 */
@IsTest
private class ITDeskRoutingServiceTest {
    @TestSetup
    static void setupQueues() {
        ITDeskTestFactory.createTestQueues();
    }

    // ---------------------------------------------------------------- rule matching

    @IsTest
    static void resolveQueue_matchesEveryConfiguredRuleByKeyword() {
        ITDeskTestFactory.useTestRouting();

        Assert.areEqual(
            ITDeskTestFactory.QUEUE_NETWORK,
            ITDeskRoutingService.resolveQueueDeveloperName('Network'),
            'The network rule keyword must resolve to the network queue.'
        );
        Assert.areEqual(
            ITDeskTestFactory.QUEUE_HARDWARE,
            ITDeskRoutingService.resolveQueueDeveloperName('Hardware'),
            'The hardware rule keyword must resolve to the hardware queue.'
        );
        Assert.areEqual(
            ITDeskTestFactory.QUEUE_SOFTWARE,
            ITDeskRoutingService.resolveQueueDeveloperName('Software'),
            'The software rule keyword must resolve to the software queue.'
        );
        Assert.areEqual(
            ITDeskTestFactory.QUEUE_IDENTITY,
            ITDeskRoutingService.resolveQueueDeveloperName('Account'),
            'The account rule keyword must resolve to the identity queue.'
        );
    }

    @IsTest
    static void resolveQueue_matchesEveryAliasOnEveryRule() {
        ITDeskTestFactory.useTestRouting();

        Map<String, String> aliasToQueue = new Map<String, String>{
            'wifi' => ITDeskTestFactory.QUEUE_NETWORK,
            'vpn' => ITDeskTestFactory.QUEUE_NETWORK,
            'wireless' => ITDeskTestFactory.QUEUE_NETWORK,
            'laptop' => ITDeskTestFactory.QUEUE_HARDWARE,
            'printer' => ITDeskTestFactory.QUEUE_HARDWARE,
            'printing' => ITDeskTestFactory.QUEUE_HARDWARE,
            'application' => ITDeskTestFactory.QUEUE_SOFTWARE,
            'license' => ITDeskTestFactory.QUEUE_SOFTWARE,
            'email' => ITDeskTestFactory.QUEUE_SOFTWARE,
            'outlook' => ITDeskTestFactory.QUEUE_SOFTWARE,
            'lms' => ITDeskTestFactory.QUEUE_SOFTWARE,
            'password' => ITDeskTestFactory.QUEUE_IDENTITY,
            'login' => ITDeskTestFactory.QUEUE_IDENTITY,
            'identity' => ITDeskTestFactory.QUEUE_IDENTITY,
            'mfa' => ITDeskTestFactory.QUEUE_IDENTITY,
            'provisioning' => ITDeskTestFactory.QUEUE_IDENTITY
        };

        for (String alias : aliasToQueue.keySet()) {
            Assert.areEqual(
                aliasToQueue.get(alias),
                ITDeskRoutingService.resolveQueueDeveloperName(alias),
                'Alias "' + alias + '" must resolve to ' + aliasToQueue.get(alias) + '.'
            );
        }
    }

    @IsTest
    static void resolveQueue_isCaseInsensitiveAndMatchesInsideASentence() {
        ITDeskTestFactory.useTestRouting();

        Assert.areEqual(
            ITDeskTestFactory.QUEUE_NETWORK,
            ITDeskRoutingService.resolveQueueDeveloperName('WIFI'),
            'Category matching must ignore case.'
        );
        Assert.areEqual(
            ITDeskTestFactory.QUEUE_IDENTITY,
            ITDeskRoutingService.resolveQueueDeveloperName('  Password Reset  '),
            'A keyword inside a longer category must still match.'
        );
    }

    // ---------------------------------------------------------------- fallback behaviour

    @IsTest
    static void resolveQueue_unmatchedCategoryUsesTheDefaultRule() {
        ITDeskTestFactory.useTestRouting();

        Assert.areEqual(
            ITDeskTestFactory.QUEUE_GENERAL,
            ITDeskRoutingService.resolveQueueDeveloperName('Parking permits'),
            'A category no rule matches must fall through to the Is Default rule.'
        );
        Assert.areEqual(
            ITDeskTestFactory.QUEUE_GENERAL,
            ITDeskRoutingService.resolveQueueDeveloperName(null),
            'A null category must fall through to the Is Default rule.'
        );
        Assert.areEqual(
            ITDeskTestFactory.QUEUE_GENERAL,
            ITDeskRoutingService.resolveQueueDeveloperName('   '),
            'A blank category must fall through to the Is Default rule.'
        );
    }

    @IsTest
    static void resolveQueue_withoutADefaultRuleUsesTheHardcodedDefault() {
        ITDeskRoutingService.useCustomMetadataRouting = true;
        ITDeskRoutingService.defaultQueueDeveloperName = ITDeskTestFactory.QUEUE_GENERAL;
        ITDeskRoutingService.metadataOverrides = new List<IT_Category_Queue_Map__mdt>{
            ITDeskTestFactory.newRoutingRule('network', null, ITDeskTestFactory.QUEUE_NETWORK, false)
        };

        Assert.areEqual(
            ITDeskTestFactory.QUEUE_GENERAL,
            ITDeskRoutingService.resolveQueueDeveloperName('Dining'),
            'With no Is Default row configured, routing must still land on a queue rather than null.'
        );
    }

    @IsTest
    static void resolveQueue_withNoRulesAtAllUsesTheHardcodedDefault() {
        ITDeskRoutingService.useCustomMetadataRouting = true;
        ITDeskRoutingService.metadataOverrides = new List<IT_Category_Queue_Map__mdt>();
        ITDeskRoutingService.categoryKeywordToQueueDevName = new Map<String, String>();
        ITDeskRoutingService.defaultQueueDeveloperName = ITDeskTestFactory.QUEUE_GENERAL;

        Assert.areEqual(
            ITDeskTestFactory.QUEUE_GENERAL,
            ITDeskRoutingService.resolveQueueDeveloperName('Network'),
            'An empty rule set must not throw; every Case still needs an owner.'
        );

        ITDeskRoutingService.categoryKeywordToQueueDevName = null;
        Assert.areEqual(
            ITDeskTestFactory.QUEUE_GENERAL,
            ITDeskRoutingService.resolveQueueDeveloperName('Network'),
            'A null in-memory fallback map must not throw.'
        );
    }

    @IsTest
    static void resolveQueue_ignoresRulesMissingAKeywordOrAQueue() {
        ITDeskRoutingService.useCustomMetadataRouting = true;
        ITDeskRoutingService.defaultQueueDeveloperName = ITDeskTestFactory.QUEUE_GENERAL;
        ITDeskRoutingService.metadataOverrides = new List<IT_Category_Queue_Map__mdt>{
            ITDeskTestFactory.newRoutingRule('network', null, null, false),
            ITDeskTestFactory.newRoutingRule(null, null, ITDeskTestFactory.QUEUE_HARDWARE, false),
            ITDeskTestFactory.newRoutingRule('  ', 'wifi , , vpn', ITDeskTestFactory.QUEUE_NETWORK, false)
        };

        Assert.areEqual(
            ITDeskTestFactory.QUEUE_GENERAL,
            ITDeskRoutingService.resolveQueueDeveloperName('Network'),
            'A rule with no queue must be skipped rather than routing to null.'
        );
        Assert.areEqual(
            ITDeskTestFactory.QUEUE_NETWORK,
            ITDeskRoutingService.resolveQueueDeveloperName('vpn'),
            'Blank alias segments must be skipped without dropping the surrounding aliases.'
        );
        Assert.areEqual(
            ITDeskTestFactory.QUEUE_NETWORK,
            ITDeskRoutingService.resolveQueueDeveloperName('wifi'),
            'Aliases must be trimmed before matching.'
        );
    }

    @IsTest
    static void resolveQueue_isDefaultRuleWinsOverTheStaticDefault() {
        ITDeskRoutingService.useCustomMetadataRouting = true;
        ITDeskRoutingService.defaultQueueDeveloperName = ITDeskTestFactory.QUEUE_NETWORK;
        ITDeskRoutingService.metadataOverrides = new List<IT_Category_Queue_Map__mdt>{
            ITDeskTestFactory.newRoutingRule(null, null, ITDeskTestFactory.QUEUE_GENERAL, true)
        };

        Assert.areEqual(
            ITDeskTestFactory.QUEUE_GENERAL,
            ITDeskRoutingService.resolveQueueDeveloperName('Unmapped'),
            'An admin-configured default rule must beat the compiled-in default.'
        );
    }

    /**
     * Characterisation test, not a specification.
     *
     * resolveQueueDeveloperName iterates Map.keySet(), and Apex does not define an iteration
     * order for Map. When a category contains two keywords from different rules the winner is
     * whichever key the map happens to yield first, so this asserts only that the result is one
     * of the two configured queues. See "Known issues" in ARCHITECTURE.md: the routing rules
     * need an explicit precedence column before this can be tightened to a single expected value.
     */
    @IsTest
    static void resolveQueue_multipleMatchingRulesHaveUnspecifiedPrecedence() {
        ITDeskTestFactory.useTestRouting();

        String resolved = ITDeskRoutingService.resolveQueueDeveloperName('email account recovery');
        Assert.isTrue(
            resolved == ITDeskTestFactory.QUEUE_SOFTWARE || resolved == ITDeskTestFactory.QUEUE_IDENTITY,
            'A category matching two rules must still resolve to one of them, but got ' + resolved
        );

        String networkPrinter = ITDeskRoutingService.resolveQueueDeveloperName('network printer offline');
        Assert.isTrue(
            networkPrinter == ITDeskTestFactory.QUEUE_NETWORK ||
            networkPrinter == ITDeskTestFactory.QUEUE_HARDWARE,
            'A category matching two rules must still resolve to one of them, but got ' + networkPrinter
        );
    }

    // ---------------------------------------------------------------- category labels

    @IsTest
    static void resolveCategoryLabel_mapsEveryQueueToItsCaseLabel() {
        ITDeskTestFactory.useTestRouting();

        Assert.areEqual('Network', ITDeskRoutingService.resolveCategoryLabel('wifi'));
        Assert.areEqual('Hardware', ITDeskRoutingService.resolveCategoryLabel('printer'));
        Assert.areEqual('Software', ITDeskRoutingService.resolveCategoryLabel('outlook'));
        Assert.areEqual('Account', ITDeskRoutingService.resolveCategoryLabel('mfa'));
        Assert.areEqual('General', ITDeskRoutingService.resolveCategoryLabel('parking'));
        Assert.areEqual(
            'General',
            ITDeskRoutingService.resolveCategoryLabel(null),
            'A null category must still produce a storable Case label.'
        );
    }

    @IsTest
    static void resolveCategoryLabel_unknownQueueNameFallsBackToGeneral() {
        ITDeskRoutingService.useCustomMetadataRouting = true;
        ITDeskRoutingService.metadataOverrides = new List<IT_Category_Queue_Map__mdt>{
            ITDeskTestFactory.newRoutingRule('badge', null, 'Facilities_Badging', false),
            ITDeskTestFactory.newRoutingRule(null, null, 'Facilities_Front_Desk', true)
        };

        Assert.areEqual(
            'General',
            ITDeskRoutingService.resolveCategoryLabel('badge'),
            'A queue outside the five known names must still map to a valid Case category.'
        );
    }

    // ---------------------------------------------------------------- priority mapping

    @IsTest
    static void resolvePriority_mapsUrgencyVocabularyOntoCasePriority() {
        Map<String, String> urgencyToPriority = new Map<String, String>{
            'Critical' => 'High',
            'emergency' => 'High',
            'URGENT' => 'High',
            'high' => 'High',
            'P1' => 'High',
            'p2' => 'High',
            'sev1' => 'High',
            'it is critical, exam tomorrow' => 'High',
            'low' => 'Low',
            'P4' => 'Low',
            'sev4' => 'Low',
            'normal' => 'Medium',
            'p3' => 'Medium',
            'whenever someone is free' => 'Medium'
        };

        for (String urgency : urgencyToPriority.keySet()) {
            Assert.areEqual(
                urgencyToPriority.get(urgency),
                ITDeskRoutingService.resolvePriority(urgency),
                'Urgency "' + urgency + '" must map to ' + urgencyToPriority.get(urgency) + '.'
            );
        }

        Assert.areEqual('Medium', ITDeskRoutingService.resolvePriority(null), 'Null urgency defaults to Medium.');
        Assert.areEqual('Medium', ITDeskRoutingService.resolvePriority('  '), 'Blank urgency defaults to Medium.');
    }

    // ---------------------------------------------------------------- normalization helpers

    @IsTest
    static void normalizeStudentId_stripsPunctuationAndUppercases() {
        Assert.areEqual('S10000001', ITDeskRoutingService.normalizeStudentId('s 1000-0001'));
        Assert.areEqual('S10000001', ITDeskRoutingService.normalizeStudentId('  S10000001  '));
        Assert.areEqual('S10000001', ITDeskRoutingService.normalizeStudentId('s.10.000.001'));
        Assert.isNull(ITDeskRoutingService.normalizeStudentId(null), 'Null in, null out.');
        Assert.isNull(ITDeskRoutingService.normalizeStudentId('   '), 'Blank in, null out.');
        Assert.isNull(
            ITDeskRoutingService.normalizeStudentId('---'),
            'A value with no alphanumeric characters has no usable student ID.'
        );
    }

    @IsTest
    static void studentIdsMatch_comparesNormalizedForms() {
        Assert.isTrue(ITDeskRoutingService.studentIdsMatch('s10000001', 'S-10000001'));
        Assert.isFalse(ITDeskRoutingService.studentIdsMatch('S10000001', 'S10000002'));
        Assert.isFalse(ITDeskRoutingService.studentIdsMatch(null, 'S10000001'), 'Null never matches.');
        Assert.isFalse(ITDeskRoutingService.studentIdsMatch(null, null), 'Two nulls must not be treated as a match.');
    }

    @IsTest
    static void normalizeIssueText_foldsSpokenContractions() {
        Assert.areEqual('wifi is down', ITDeskRoutingService.normalizeIssueText('Wi-Fi is down'));
        Assert.areEqual('my laptop wont boot', ITDeskRoutingService.normalizeIssueText('My laptop won\'t boot'));
        Assert.areEqual('i cant log in', ITDeskRoutingService.normalizeIssueText('I can\'t log in'));
        Assert.areEqual('it isnt working', ITDeskRoutingService.normalizeIssueText('It isn\'t working'));
        Assert.areEqual('', ITDeskRoutingService.normalizeIssueText(null), 'Null text normalizes to empty, not null.');
    }

    @IsTest
    static void caseNumberLookupKeys_coversSpokenAndPaddedForms() {
        Set<String> keys = ITDeskRoutingService.caseNumberLookupKeys('1234');
        Assert.isTrue(keys.contains('1234'), 'The spoken form must be retained.');
        Assert.isTrue(keys.contains('00001234'), 'The zero-padded stored form must be derivable.');

        Set<String> fromPadded = ITDeskRoutingService.caseNumberLookupKeys('00001234');
        Assert.isTrue(fromPadded.contains('1234'), 'The unpadded form must be derivable.');
        Assert.isTrue(fromPadded.contains('00001234'));

        Set<String> noisy = ITDeskRoutingService.caseNumberLookupKeys('case # 1234');
        Assert.isTrue(noisy.contains('00001234'), 'Digits must be extracted from surrounding words.');

        Assert.areEqual(0, ITDeskRoutingService.caseNumberLookupKeys(null).size());
        Assert.areEqual(0, ITDeskRoutingService.caseNumberLookupKeys('   ').size());
        Assert.areEqual(
            1,
            ITDeskRoutingService.caseNumberLookupKeys('abc').size(),
            'A value with no digits yields only the literal input.'
        );
    }

    @IsTest
    static void tokenize_splitsOnNonAlphanumericAndKeepsTheWholeString() {
        Set<String> tokens = ITDeskRoutingService.tokenize('P1 - Critical!');
        Assert.isTrue(tokens.contains('p1'));
        Assert.isTrue(tokens.contains('critical'));
        Assert.isTrue(tokens.contains('p1 - critical!'), 'The whole normalized string is also a token.');
        Assert.areEqual(0, ITDeskRoutingService.tokenize(null).size());
        Assert.areEqual(0, ITDeskRoutingService.tokenize('   ').size());
    }

    // ---------------------------------------------------------------- query helpers

    @IsTest
    static void queryHelpers_returnEmptyForNullAndEmptyInput() {
        Assert.areEqual(0, ITDeskRoutingService.queryQueuesByDeveloperName(null).size());
        Assert.areEqual(0, ITDeskRoutingService.queryQueuesByDeveloperName(new Set<String>()).size());
        Assert.areEqual(0, ITDeskRoutingService.queryQueuesById(null).size());
        Assert.areEqual(0, ITDeskRoutingService.queryQueuesById(new Set<Id>()).size());
        Assert.areEqual(0, ITDeskRoutingService.queryContactsByStudentId(null).size());
        Assert.areEqual(0, ITDeskRoutingService.queryContactsByStudentId(new Set<String>()).size());
        Assert.areEqual(0, ITDeskRoutingService.queryOpenCasesByStudentId(new Set<String>()).size());
        Assert.areEqual(0, ITDeskRoutingService.queryCasesByStudentId(new Set<String>()).size());
        Assert.areEqual(0, ITDeskRoutingService.queryCasesByNumber(null).size());
        Assert.areEqual(0, ITDeskRoutingService.queryCasesByNumber(new Set<String>()).size());
        Assert.isNull(ITDeskRoutingService.findCaseByNumber(null, '1234'));
        Assert.isNull(ITDeskRoutingService.findCaseByNumber(new Map<String, Case>(), null));
        Assert.isNull(ITDeskRoutingService.casesForStudent(null, 'S10000001'));
    }

    @IsTest
    static void queryContactsByStudentId_indexesRawAndNormalizedKeys() {
        insert new Contact(LastName = 'Rivera', Student_ID__c = 'S10000001');

        Test.startTest();
        Map<String, Contact> byStudentId = ITDeskRoutingService.queryContactsByStudentId(
            new Set<String>{ 's 1000-0001' }
        );
        Test.stopTest();

        Assert.isTrue(
            byStudentId.containsKey('S10000001'),
            'A spoken student ID must find the Contact stored under the normalized value.'
        );
    }

    @IsTest
    static void queryCasesByStudentId_returnsOpenTicketsFirstAndFiltersWhenAsked() {
        ITDeskTestFactory.useTestRouting();
        List<Case> tickets = ITDeskTestFactory.insertOpenCases(2, 'Network', null);
        update new Case(Id = tickets[0].Id, Status = ITDeskTestFactory.closedCaseStatus());

        Test.startTest();
        Map<String, List<Case>> openOnly = ITDeskRoutingService.queryOpenCasesByStudentId(
            new Set<String>{ ITDeskTestFactory.bulkStudentId(0), ITDeskTestFactory.bulkStudentId(1) }
        );
        Map<String, List<Case>> everything = ITDeskRoutingService.queryCasesByStudentId(
            new Set<String>{ ITDeskTestFactory.bulkStudentId(0), ITDeskTestFactory.bulkStudentId(1) }
        );
        Test.stopTest();

        Assert.isNull(
            ITDeskRoutingService.casesForStudent(openOnly, ITDeskTestFactory.bulkStudentId(0)),
            'A student whose only ticket is closed must not appear in the open-cases map.'
        );
        Assert.areEqual(
            1,
            ITDeskRoutingService.casesForStudent(openOnly, ITDeskTestFactory.bulkStudentId(1)).size(),
            'The student with an open ticket must appear in the open-cases map.'
        );
        Assert.areEqual(
            1,
            ITDeskRoutingService.casesForStudent(everything, ITDeskTestFactory.bulkStudentId(0)).size(),
            'The unfiltered lookup must still return the closed ticket.'
        );
    }

    @IsTest
    static void findCaseByNumber_acceptsSpokenAndStoredForms() {
        ITDeskTestFactory.useTestRouting();
        List<Case> tickets = ITDeskTestFactory.insertOpenCases(1, 'Network', null);
        String stored = tickets[0].CaseNumber;
        String spoken = stored.replaceFirst('^0+', '');

        Test.startTest();
        Map<String, Case> byNumber = ITDeskRoutingService.queryCasesByNumber(new Set<String>{ spoken });
        Test.stopTest();

        Assert.isNotNull(
            ITDeskRoutingService.findCaseByNumber(byNumber, spoken),
            'A Case Number spoken without leading zeros must resolve.'
        );
        Assert.isNotNull(
            ITDeskRoutingService.findCaseByNumber(byNumber, stored),
            'The stored Case Number must resolve from the same map.'
        );
        Assert.isNull(
            ITDeskRoutingService.findCaseByNumber(byNumber, '99999999'),
            'An unknown Case Number must return null rather than an arbitrary Case.'
        );
    }

    // ---------------------------------------------------------------- Case reuse

    @IsTest
    static void findReusableOpenCase_prefersACaseAlreadyOnTheTargetQueue() {
        Id networkQueue = ITDeskTestFactory.queueId(ITDeskTestFactory.QUEUE_NETWORK);
        Case onQueue = new Case(Id = fakeCaseId(1), OwnerId = networkQueue, Subject = 'Unrelated subject');

        Case match = ITDeskRoutingService.findReusableOpenCase(
            'S10000001',
            'Network',
            ITDeskTestFactory.QUEUE_NETWORK,
            new Map<String, List<Case>>{ 'S10000001' => new List<Case>{ onQueue } },
            new Map<Id, Group>{
                networkQueue => new Group(Id = networkQueue, DeveloperName = ITDeskTestFactory.QUEUE_NETWORK)
            }
        );

        Assert.areEqual(onQueue, match, 'An open Case already sitting on the target queue must be reused.');
    }

    @IsTest
    static void findReusableOpenCase_matchesOnTheStoredCategoryLabel() {
        ITDeskTestFactory.useTestRouting();
        Case userOwned = new Case(
            Id = fakeCaseId(2),
            OwnerId = UserInfo.getUserId(),
            IT_Category__c = 'Network',
            Subject = 'Nothing that mentions the category'
        );

        Case match = ITDeskRoutingService.findReusableOpenCase(
            'S10000001',
            'wifi',
            ITDeskTestFactory.QUEUE_NETWORK,
            new Map<String, List<Case>>{ 'S10000001' => new List<Case>{ userOwned } },
            new Map<Id, Group>()
        );

        Assert.areEqual(
            userOwned,
            match,
            'A technician-owned Case still carrying the same IT Category must be reused.'
        );
    }

    @IsTest
    static void findReusableOpenCase_fallsBackToASubjectContainsMatch() {
        ITDeskTestFactory.useTestRouting();
        Case userOwned = new Case(
            Id = fakeCaseId(3),
            OwnerId = UserInfo.getUserId(),
            Subject = 'Campus IT: Network — wifi dropout'
        );

        Case match = ITDeskRoutingService.findReusableOpenCase(
            'S10000001',
            'Network',
            ITDeskTestFactory.QUEUE_NETWORK,
            new Map<String, List<Case>>{ 'S10000001' => new List<Case>{ userOwned } },
            new Map<Id, Group>()
        );

        Assert.areEqual(userOwned, match, 'The subject fallback must find a Case with no IT Category set.');
    }

    @IsTest
    static void findReusableOpenCase_returnsNullWhenNothingIsComparable() {
        ITDeskTestFactory.useTestRouting();
        Case unrelated = new Case(
            Id = fakeCaseId(4),
            OwnerId = UserInfo.getUserId(),
            IT_Category__c = 'Hardware',
            Subject = 'Campus IT: Hardware — cracked screen'
        );

        Assert.isNull(
            ITDeskRoutingService.findReusableOpenCase(
                'S10000001',
                'Network',
                ITDeskTestFactory.QUEUE_NETWORK,
                new Map<String, List<Case>>{ 'S10000001' => new List<Case>{ unrelated } },
                new Map<Id, Group>()
            ),
            'A Case in another category must not be reused.'
        );
        Assert.isNull(
            ITDeskRoutingService.findReusableOpenCase(
                null,
                'Network',
                ITDeskTestFactory.QUEUE_NETWORK,
                new Map<String, List<Case>>(),
                new Map<Id, Group>()
            ),
            'A null student ID cannot select a Case to reuse.'
        );
        Assert.isNull(
            ITDeskRoutingService.findReusableOpenCase(
                'S10000001',
                'Network',
                ITDeskTestFactory.QUEUE_NETWORK,
                null,
                new Map<Id, Group>()
            ),
            'A null open-case map cannot select a Case to reuse.'
        );
        Assert.isNull(
            ITDeskRoutingService.findReusableOpenCase(
                'S10000001',
                'Network',
                ITDeskTestFactory.QUEUE_NETWORK,
                new Map<String, List<Case>>{ 'S10000001' => new List<Case>() },
                new Map<Id, Group>()
            ),
            'A student with no open Cases has nothing to reuse.'
        );
    }

    // ---------------------------------------------------------------- Case Comments

    @IsTest
    static void newPublishedComment_clipsToTheFieldLimitAndRejectsBadInput() {
        Id caseId = fakeCaseId(5);

        CaseComment ok = ITDeskRoutingService.newPublishedComment(caseId, 'A short update.');
        Assert.isNotNull(ok);
        Assert.isTrue(ok.IsPublished, 'Comments must be published so the student can see them.');
        Assert.areEqual(caseId, ok.ParentId);

        CaseComment clipped = ITDeskRoutingService.newPublishedComment(caseId, 'x'.repeat(5000));
        Assert.areEqual(4000, clipped.CommentBody.length(), 'Comment bodies must be clipped to the field limit.');

        Assert.isNull(ITDeskRoutingService.newPublishedComment(null, 'body'), 'No parent, no comment.');
        Assert.isNull(ITDeskRoutingService.newPublishedComment(caseId, '   '), 'No body, no comment.');
    }

    @IsTest
    static void insertPublishedComments_skipsNullBlankAndParentlessRows() {
        ITDeskTestFactory.useTestRouting();
        List<Case> tickets = ITDeskTestFactory.insertOpenCases(1, 'Network', null);

        Test.startTest();
        ITDeskRoutingService.insertPublishedComments(null);
        ITDeskRoutingService.insertPublishedComments(new List<CaseComment>());
        ITDeskRoutingService.insertPublishedComments(
            new List<CaseComment>{
                null,
                new CaseComment(ParentId = null, CommentBody = 'orphan'),
                new CaseComment(ParentId = tickets[0].Id, CommentBody = '   '),
                new CaseComment(ParentId = tickets[0].Id, CommentBody = 'kept', IsPublished = true)
            }
        );
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM CaseComment WHERE ParentId = :tickets[0].Id],
            'Only the well-formed comment should have been inserted.'
        );
    }

    /** Deterministic unsaved Case Id, so reuse selection can be unit tested without DML. */
    private static Id fakeCaseId(Integer seed) {
        String suffix = String.valueOf(seed);
        return Id.valueOf(
            Case.SObjectType.getDescribe().getKeyPrefix() + '0'.repeat(12 - suffix.length()) + suffix
        );
    }
}
